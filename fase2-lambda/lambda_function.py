"""
Tech Challenge: Pipeline Batch Bovespa
Fase 2: Função Lambda para Gatilho S3

Esta função Lambda é acionada quando novos arquivos são adicionados ao bucket S3
e inicia o job do AWS Glue para processamento dos dados.
"""

import json
import boto3
import logging
from datetime import datetime
from typing import Dict, Any
import os

# Configuração de logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Inicializar clientes AWS
glue_client = boto3.client('glue')

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Função principal da Lambda
    
    Args:
        event: Evento do S3
        context: Contexto da Lambda
        
    Returns:
        Resposta da execução
    """
    logger.info(f"Evento recebido: {json.dumps(event)}")
    
    try:
        # Processar cada registro do evento S3
        processed_files = []
        
        for record in event.get('Records', []):
            if record.get('eventSource') == 'aws:s3':
                result = process_s3_event(record)
                processed_files.append(result)
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Processamento concluído com sucesso',
                'processed_files': len(processed_files),
                'files': processed_files
            })
        }
        
    except Exception as e:
        logger.error(f"Erro no processamento: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e)
            })
        }

def process_s3_event(record: Dict[str, Any]) -> Dict[str, Any]:
    """
    Processa um evento S3 individual
    
    Args:
        record: Registro do evento S3
        
    Returns:
        Resultado do processamento
    """
    # Extrair informações do evento
    bucket_name = record['s3']['bucket']['name']
    object_key = record['s3']['object']['key']
    event_name = record['eventName']
    
    logger.info(f"Processando arquivo: s3://{bucket_name}/{object_key}")
    
    # Verificar se é um arquivo da pasta raw/
    if not object_key.startswith('raw/'):
        logger.info(f"Arquivo não está na pasta raw/, ignorando: {object_key}")
        return {
            'file': object_key,
            'action': 'ignored',
            'reason': 'not_in_raw_folder'
        }
    
    # Verificar se é um arquivo Parquet
    if not object_key.endswith('.parquet'):
        logger.info(f"Arquivo não é Parquet, ignorando: {object_key}")
        return {
            'file': object_key,
            'action': 'ignored',
            'reason': 'not_parquet_file'
        }
    
    # Verificar se é evento de criação/upload
    if not any(create_event in event_name for create_event in ['ObjectCreated', 'Put', 'Post']):
        logger.info(f"Evento não é de criação, ignorando: {event_name}")
        return {
            'file': object_key,
            'action': 'ignored',
            'reason': 'not_create_event'
        }
    
    # Extrair metadados do caminho
    metadata = extract_file_metadata(object_key)
    
    # Iniciar job do Glue
    job_result = start_glue_job(bucket_name, object_key, metadata)
    
    return {
        'file': object_key,
        'action': 'processed',
        'metadata': metadata,
        'glue_job': job_result
    }

def extract_file_metadata(object_key: str) -> Dict[str, Any]:
    """
    Extrai metadados do caminho do arquivo S3
    
    Args:
        object_key: Chave do objeto S3
        
    Returns:
        Dicionário com metadados extraídos
    """
    # Exemplo: raw/ano=2025/mes=09/dia=23/PETR4.SA_2025-09-23.parquet
    parts = object_key.split('/')
    
    metadata = {
        'full_path': object_key,
        'filename': parts[-1] if parts else None
    }
    
    # Extrair partições
    for part in parts:
        if '=' in part:
            key, value = part.split('=', 1)
            try:
                metadata[key] = int(value) if value.isdigit() else value
            except ValueError:
                metadata[key] = value
    
    # Extrair ticker do nome do arquivo se possível
    if metadata.get('filename'):
        filename = metadata['filename']
        if '_' in filename:
            potential_ticker = filename.split('_')[0]
            metadata['ticker'] = potential_ticker
    
    logger.info(f"Metadados extraídos: {metadata}")
    return metadata

def start_glue_job(bucket_name: str, object_key: str, metadata: Dict[str, Any]) -> Dict[str, Any]:
    """
    Inicia o job do AWS Glue
    
    Args:
        bucket_name: Nome do bucket S3
        object_key: Chave do objeto S3
        metadata: Metadados extraídos
        
    Returns:
        Resultado da inicialização do job
    """
    job_name = os.environ.get('GLUE_JOB_NAME', 'tech-challenge-bovespa-etl')
    
    # Parâmetros para o job do Glue
    job_parameters = {
        '--source_bucket': bucket_name,
        '--source_key': object_key,
        '--target_bucket': bucket_name,
        '--target_prefix': 'refined/',
        '--partition_year': str(metadata.get('ano', '')),
        '--partition_month': str(metadata.get('mes', '')),
        '--partition_day': str(metadata.get('dia', '')),
        '--ticker': metadata.get('ticker', ''),
        '--execution_time': datetime.now().isoformat()
    }
    
    try:
        logger.info(f"Iniciando job do Glue: {job_name}")
        logger.info(f"Parâmetros: {job_parameters}")
        
        response = glue_client.start_job_run(
            JobName=job_name,
            Arguments=job_parameters
        )
        
        job_run_id = response['JobRunId']
        logger.info(f"Job do Glue iniciado com sucesso. Job Run ID: {job_run_id}")
        
        return {
            'status': 'started',
            'job_name': job_name,
            'job_run_id': job_run_id,
            'parameters': job_parameters
        }
        
    except Exception as e:
        logger.error(f"Erro ao iniciar job do Glue: {str(e)}")
        return {
            'status': 'error',
            'error': str(e),
            'job_name': job_name,
            'parameters': job_parameters
        }

def get_job_status(job_name: str, job_run_id: str) -> Dict[str, Any]:
    """
    Obtém o status de um job do Glue
    
    Args:
        job_name: Nome do job
        job_run_id: ID da execução do job
        
    Returns:
        Status do job
    """
    try:
        response = glue_client.get_job_run(
            JobName=job_name,
            RunId=job_run_id
        )
        
        job_run = response['JobRun']
        return {
            'status': job_run['JobRunState'],
            'started_on': job_run.get('StartedOn'),
            'completed_on': job_run.get('CompletedOn'),
            'execution_time': job_run.get('ExecutionTime'),
            'error_message': job_run.get('ErrorMessage')
        }
        
    except Exception as e:
        logger.error(f"Erro ao obter status do job: {str(e)}")
        return {
            'status': 'unknown',
            'error': str(e)
        }
