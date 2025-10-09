"""
Extrator B3 via API Interna - Tech Challenge Bovespa
Extração direta da API interna do site oficial da B3 (SEM rate limiting!)
Solução alternativa ao yfinance que está bloqueando suas requisições.
"""

import requests
import pandas as pd
import json
import base64
import boto3
import pyarrow as pa
import pyarrow.parquet as pq
import io
import logging
import os
from datetime import datetime
from typing import Optional, Dict, List
import argparse

# Configuração de logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)


def scrape_b3_ibov_api(page_size: int = 120) -> Optional[pd.DataFrame]:
    """
    Extrai dados da carteira do IBOV usando a API interna oficial da B3
    
    VANTAGENS sobre yfinance:
    - Sem rate limiting (429 errors)
    - Dados oficiais direto da fonte
    - Mais rápido e confiável
    - Sem dependência de APIs de terceiros
    
    Args:
        page_size: Número de registros por página (120 pega todos)
    
    Returns:
        DataFrame com dados da carteira do IBOV
    """
    logger.info("🚀 Iniciando extração via API oficial B3...")

    # 1. Preparar payload para API (formato esperado pela B3)
    payload = {
        "language": "pt-br",
        "pageNumber": 1,
        "pageSize": page_size,
        "index": "IBOV",
        "segment": "1"
    }
    
    # Codificar payload em Base64 (formato exigido pela API)
    json_payload = json.dumps(payload)
    base64_payload = base64.b64encode(json_payload.encode('utf-8')).decode('utf-8')

    # 2. Montar URL da API interna
    api_url = f"https://sistemaswebb3-listados.b3.com.br/indexProxy/indexCall/GetPortfolioDay/{base64_payload}"

    # 3. Headers para simular navegador
    headers = {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
        'Accept': 'application/json, text/plain, */*',
        'Accept-Language': 'pt-BR,pt;q=0.9',
        'Referer': 'https://sistemaswebb3-listados.b3.com.br/indexPage/day/IBOV?language=pt-br'
    }

    try:
        # 4. Fazer requisição
        response = requests.get(api_url, headers=headers, timeout=30)
        response.raise_for_status()
        
        logger.info("✅ Resposta recebida da API B3")
        
        # 5. Parse JSON
        data = response.json()
        
        if not data.get('results'):
            logger.warning("⚠️  API não retornou dados")
            return None
        
        # 6. Converter para DataFrame
        df = pd.DataFrame(data['results'])
        
        # 7. Renomear e limpar colunas
        column_mapping = {
            'cod': 'codigo',
            'asset': 'acao',
            'part': 'participacao_percentual',
            'theoricalQty': 'quantidade_teorica',
            'type': 'tipo'
        }
        df.rename(columns=column_mapping, inplace=True)
        
        # 8. Converter tipos de dados
        # Participação: "0,547" -> 0.547
        if 'participacao_percentual' in df.columns:
            df['participacao_percentual'] = df['participacao_percentual'].str.replace(',', '.').astype(float)
        
        # Quantidade teórica: "466.632.333" -> 466632333.0
        if 'quantidade_teorica' in df.columns:
            df['quantidade_teorica'] = (df['quantidade_teorica']
                                       .astype(str)
                                       .str.replace('.', '')
                                       .str.replace(',', '.')
                                       .astype(float))
        
        # 9. Adicionar metadados
        df['data_extracao'] = datetime.now()
        df['data_carteira'] = datetime.now().date()
        df['indice'] = 'IBOV'
        df['fonte'] = 'B3_API_Oficial'
        
        # 10. Validações
        total_participacao = df['participacao_percentual'].sum()
        
        logger.info(f"📊 Total de ações: {len(df)}")
        logger.info(f"💯 Participação total: {total_participacao:.3f}%")
        
        if abs(total_participacao - 100.0) > 1.0:
            logger.warning(f"⚠️  Participação total difere de 100%: {total_participacao:.3f}%")
        
        return df

    except requests.exceptions.RequestException as e:
        logger.error(f"❌ Erro na requisição HTTP: {e}")
        return None
    except (KeyError, json.JSONDecodeError) as e:
        logger.error(f"❌ Erro ao processar JSON: {e}")
        return None
    except Exception as e:
        logger.error(f"❌ Erro inesperado: {e}")
        return None


def save_to_s3_partitioned(df: pd.DataFrame, bucket_name: str, base_path: str = "raw") -> str:
    """
    Salva dados no S3 com particionamento por data (REQUISITO DO TECH CHALLENGE)
    
    Estrutura: s3://bucket/raw/ano=2025/mes=10/dia=02/arquivo.parquet
    
    Args:
        df: DataFrame com dados
        bucket_name: Nome do bucket S3
        base_path: Caminho base (default: "raw")
        
    Returns:
        Caminho completo do arquivo no S3
    """
    if df.empty:
        raise ValueError("DataFrame vazio")
    
    # Particionamento por data
    data_ref = datetime.now()
    ano = data_ref.year
    mes = f"{data_ref.month:02d}"
    dia = f"{data_ref.day:02d}"
    
    # Nome do arquivo
    timestamp = data_ref.strftime("%H%M%S")
    filename = f"ibov_carteira_{data_ref.strftime('%Y%m%d')}_{timestamp}.parquet"
    
    # Caminho particionado (conforme requisito)
    s3_key = f"{base_path}/ano={ano}/mes={mes}/dia={dia}/{filename}"
    
    try:
        s3_client = boto3.client('s3')
        
        # Converter para Parquet em memória
        table = pa.Table.from_pandas(df)
        buffer = io.BytesIO()
        pq.write_table(table, buffer)
        buffer.seek(0)
        
        # Upload para S3
        s3_client.put_object(
            Bucket=bucket_name,
            Key=s3_key,
            Body=buffer.getvalue(),
            ContentType='application/octet-stream',
            Metadata={
                'source': 'B3_API_Oficial',
                'extraction_date': data_ref.isoformat(),
                'record_count': str(len(df)),
                'index': 'IBOV',
                'format': 'parquet'
            }
        )
        
        s3_path = f"s3://{bucket_name}/{s3_key}"
        logger.info(f"✅ Salvo no S3: {s3_path}")
        logger.info(f"📦 Registros: {len(df)} | Formato: Parquet | Particionado: ✓")
        
        return s3_path
        
    except Exception as e:
        logger.error(f"❌ Erro ao salvar no S3: {e}")
        raise


def save_locally(df: pd.DataFrame, output_dir: str = "data") -> str:
    """
    Salva dados localmente para testes (formato Parquet)
    
    Args:
        df: DataFrame
        output_dir: Diretório de saída
        
    Returns:
        Caminho do arquivo
    """
    os.makedirs(output_dir, exist_ok=True)
    
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    filename = f"ibov_carteira_{timestamp}.parquet"
    filepath = os.path.join(output_dir, filename)
    
    table = pa.Table.from_pandas(df)
    pq.write_table(table, filepath)
    
    logger.info(f"✅ Salvo localmente: {filepath}")
    
    return filepath


def run_extraction(
    bucket_name: Optional[str] = None,
    save_to_s3: bool = True,
    save_local: bool = False,
    filter_tickers: Optional[List[str]] = None
) -> Dict:
    """
    Pipeline completo de extração (FASE 1 do Tech Challenge)
    
    Args:
        bucket_name: Nome do bucket S3
        save_to_s3: Salvar no S3?
        save_local: Salvar localmente?
        filter_tickers: Lista opcional de códigos para filtrar
        
    Returns:
        Dict com resultados da execução
    """
    start_time = datetime.now()
    
    logger.info("="*70)
    logger.info("🎯 PIPELINE B3 - EXTRAÇÃO CARTEIRA IBOVESPA")
    logger.info("="*70)
    logger.info(f"📅 Data/Hora: {start_time.strftime('%d/%m/%Y %H:%M:%S')}")
    logger.info(f"🗂️  Bucket S3: {bucket_name or 'N/A (modo local)'}")
    logger.info("="*70)
    
    try:
        # 1. Extrair dados da B3
        df_completo = scrape_b3_ibov_api()
        
        if df_completo is None or df_completo.empty:
            raise ValueError("Nenhum dado foi extraído da API B3")
        
        # 2. Filtrar se solicitado
        if filter_tickers:
            logger.info(f"🔍 Filtro ativo: {', '.join(filter_tickers)}")
            df_filtrado = df_completo[df_completo['codigo'].isin(filter_tickers)].copy()
            
            if df_filtrado.empty:
                logger.warning("⚠️  Nenhum ticker do filtro encontrado. Usando todos.")
                df_final = df_completo
            else:
                logger.info(f"✅ Filtrados: {len(df_filtrado)} de {len(df_completo)} ações")
                df_final = df_filtrado
        else:
            df_final = df_completo
        
        # 3. Preparar resultados
        results = {
            'status': 'success',
            'records_total': len(df_completo),
            'records_saved': len(df_final),
            'execution_time': None,
            'files_created': [],
            'top_5': df_final.nlargest(5, 'participacao_percentual')[
                ['codigo', 'acao', 'participacao_percentual']
            ].to_dict('records'),
            'total_participacao': df_final['participacao_percentual'].sum()
        }
        
        # 4. Salvar no S3 (REQUISITO 2)
        if save_to_s3 and bucket_name:
            try:
                s3_path = save_to_s3_partitioned(df_final, bucket_name)
                results['files_created'].append(s3_path)
                results['s3_success'] = True
            except Exception as e:
                logger.error(f"❌ Falha no S3: {e}")
                results['s3_error'] = str(e)
                results['s3_success'] = False
        
        # 5. Salvar localmente (para testes)
        if save_local:
            try:
                local_path = save_locally(df_final)
                results['files_created'].append(local_path)
                results['local_success'] = True
            except Exception as e:
                logger.error(f"❌ Falha local: {e}")
                results['local_error'] = str(e)
                results['local_success'] = False
        
        # 6. Finalizar
        execution_time = datetime.now() - start_time
        results['execution_time'] = str(execution_time)
        
        logger.info("="*70)
        logger.info(f"✅ SUCESSO! Tempo: {execution_time}")
        logger.info(f"📊 Registros salvos: {results['records_saved']}")
        logger.info(f"💯 Participação total: {results['total_participacao']:.3f}%")
        logger.info("="*70)
        
        return results
        
    except Exception as e:
        logger.error(f"❌ ERRO NO PIPELINE: {e}")
        return {
            'status': 'error',
            'error': str(e),
            'execution_time': str(datetime.now() - start_time)
        }


def main():
    """Função principal com argumentos de linha de comando"""
    parser = argparse.ArgumentParser(
        description='📊 Extração B3 - Alternativa ao yfinance (SEM rate limiting!)',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
💡 Exemplos de uso:

  # Salvar no S3
  python b3_scraper_new.py --bucket meu-bucket-tech-challenge

  # Salvar localmente (para testes)
  python b3_scraper_new.py --local --no-s3
  
  # Filtrar apenas algumas ações
  python b3_scraper_new.py --bucket meu-bucket --filter VALE3 PETR4 ITUB4 BBDC4
  
  # Ambos (S3 + local)
  python b3_scraper_new.py --bucket meu-bucket --local

🎯 Este scraper usa a API OFICIAL da B3, sem limitações!
        """
    )
    
    parser.add_argument('--bucket', help='Nome do bucket S3 (obrigatório para salvar no S3)')
    parser.add_argument('--region', default='us-east-1', help='Região AWS (default: us-east-1)')
    parser.add_argument('--local', action='store_true', help='Salvar arquivo local para testes')
    parser.add_argument('--no-s3', action='store_true', help='Não salvar no S3 (apenas local)')
    parser.add_argument(
        '--filter',
        nargs='+',
        help='Códigos de ações para filtrar (ex: VALE3 PETR4 ITUB4)'
    )
    
    args = parser.parse_args()
    
    # Validações
    if not args.no_s3 and not args.bucket and not args.local:
        parser.error("❌ Especifique --bucket para salvar no S3 OU use --local para salvar localmente")
    
    # Executar pipeline
    results = run_extraction(
        bucket_name=args.bucket,
        save_to_s3=(not args.no_s3 and args.bucket is not None),
        save_local=args.local,
        filter_tickers=args.filter
    )
    
    # Exibir resultados
    print("\n" + "="*70)
    print("📋 RESUMO DA EXTRAÇÃO")
    print("="*70)
    print(json.dumps(results, indent=2, default=str, ensure_ascii=False))
    
    if results.get('status') == 'success':
        print("\n🎉 Extração concluída com sucesso!")
        
        if results.get('top_5'):
            print("\n🏆 TOP 5 AÇÕES POR PARTICIPAÇÃO NO IBOV:")
            print("-" * 70)
            for i, stock in enumerate(results['top_5'], 1):
                codigo = stock.get('codigo', 'N/A')
                acao = stock.get('acao', 'N/A')
                part = stock.get('participacao_percentual', 0)
                print(f"  {i}. {codigo:8} - {acao:25} - {part:6.3f}%")
            print("-" * 70)
        
        # Instruções próximos passos
        print("\n📌 PRÓXIMOS PASSOS (Tech Challenge):")
        print("  1. ✅ Dados extraídos e salvos no S3 (Fase 1 concluída)")
        print("  2. ⏭️  Configure Lambda para acionar Glue (Fase 2)")
        print("  3. ⏭️  Crie Job do Glue para transformações (Fase 3)")
        print("  4. ⏭️  Configure Athena para consultas (Fase 4)")
        
        exit(0)
    else:
        print(f"\n❌ Erro na extração: {results.get('error')}")
        exit(1)


if __name__ == "__main__":
    main()
