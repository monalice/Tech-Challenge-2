"""
Tech Challenge: Pipeline Batch Bovespa
Fase 1: Extração e Ingestão dos Dados Brutos

Este script extrai dados da B3 usando yfinance e salva no S3 em formato Parquet.
"""

import pandas as pd
import yfinance as yf
import boto3
from datetime import datetime, timedelta
import logging
import os
from typing import List, Dict
import pyarrow as pa
import pyarrow.parquet as pq

# Configuração de logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

class BovespaDataExtractor:
    """Classe responsável pela extração de dados da Bovespa"""
    
    def __init__(self, bucket_name: str, aws_region: str = 'us-east-1'):
        """
        Inicializa o extrator de dados
        
        Args:
            bucket_name: Nome do bucket S3
            aws_region: Região AWS
        """
        self.bucket_name = bucket_name
        self.aws_region = aws_region
        self.s3_client = boto3.client('s3', region_name=aws_region)
        
        # Ativos da B3 para extração
        self.tickers = ['PETR4.SA', 'VALE3.SA', '^BVSP']
        
    def extract_data(self, start_date: str = None, end_date: str = None) -> pd.DataFrame:
        """
        Extrai dados dos ativos usando yfinance
        
        Args:
            start_date: Data inicial (YYYY-MM-DD)
            end_date: Data final (YYYY-MM-DD)
            
        Returns:
            DataFrame com os dados extraídos
        """
        if not start_date:
            start_date = (datetime.now() - timedelta(days=1)).strftime('%Y-%m-%d')
        if not end_date:
            end_date = datetime.now().strftime('%Y-%m-%d')
            
        logger.info(f"Extraindo dados de {start_date} a {end_date}")
        
        all_data = []
        
        for ticker in self.tickers:
            try:
                logger.info(f"Extraindo dados para {ticker}")
                
                # Download dos dados
                stock = yf.Ticker(ticker)
                data = stock.history(start=start_date, end=end_date)
                
                if data.empty:
                    logger.warning(f"Nenhum dado encontrado para {ticker}")
                    continue
                
                # Reset index para ter Date como coluna
                data.reset_index(inplace=True)
                
                # Adicionar colunas de metadados
                data['ticker'] = ticker
                data['data_extracao'] = datetime.now()
                data['ano'] = data['Date'].dt.year
                data['mes'] = data['Date'].dt.month
                data['dia'] = data['Date'].dt.day
                
                # Renomear colunas para português (preparação para transformação)
                data = data.rename(columns={
                    'Date': 'data',
                    'Open': 'abertura',
                    'High': 'maxima',
                    'Low': 'minima',
                    'Close': 'fechamento',
                    'Volume': 'volume'
                })
                
                all_data.append(data)
                logger.info(f"Extraídos {len(data)} registros para {ticker}")
                
            except Exception as e:
                logger.error(f"Erro ao extrair dados para {ticker}: {str(e)}")
                continue
        
        if not all_data:
            raise ValueError("Nenhum dado foi extraído")
            
        # Concatenar todos os dados
        combined_data = pd.concat(all_data, ignore_index=True)
        logger.info(f"Total de {len(combined_data)} registros extraídos")
        
        return combined_data
    
    def save_to_s3(self, df: pd.DataFrame, date_str: str = None) -> List[str]:
        """
        Salva DataFrame no S3 em formato Parquet particionado
        
        Args:
            df: DataFrame com os dados
            date_str: Data para particionamento (YYYY-MM-DD)
            
        Returns:
            Lista com as chaves S3 dos arquivos salvos
        """
        if date_str is None:
            date_str = datetime.now().strftime('%Y-%m-%d')
            
        date_obj = datetime.strptime(date_str, '%Y-%m-%d')
        ano = date_obj.year
        mes = date_obj.month
        dia = date_obj.day
        
        uploaded_files = []
        
        # Agrupar por ticker para salvar separadamente
        for ticker in df['ticker'].unique():
            ticker_data = df[df['ticker'] == ticker].copy()
            
            # Criar o caminho particionado
            s3_key = f"raw/ano={ano}/mes={mes:02d}/dia={dia:02d}/{ticker}_{date_str}.parquet"
            
            try:
                # Converter para Parquet em memória
                table = pa.Table.from_pandas(ticker_data)
                parquet_buffer = pa.BufferOutputStream()
                pq.write_table(table, parquet_buffer)
                
                # Upload para S3
                self.s3_client.put_object(
                    Bucket=self.bucket_name,
                    Key=s3_key,
                    Body=parquet_buffer.getvalue().to_pybytes(),
                    ContentType='application/octet-stream'
                )
                
                uploaded_files.append(s3_key)
                logger.info(f"Arquivo salvo: s3://{self.bucket_name}/{s3_key}")
                
            except Exception as e:
                logger.error(f"Erro ao salvar {ticker} no S3: {str(e)}")
                raise
        
        return uploaded_files
    
    def run_extraction(self, date_str: str = None) -> Dict:
        """
        Executa o processo completo de extração
        
        Args:
            date_str: Data para extração (YYYY-MM-DD)
            
        Returns:
            Dicionário com informações da execução
        """
        start_time = datetime.now()
        
        try:
            # Extração dos dados
            df = self.extract_data()
            
            # Salvamento no S3
            uploaded_files = self.save_to_s3(df, date_str)
            
            end_time = datetime.now()
            duration = (end_time - start_time).total_seconds()
            
            result = {
                'status': 'success',
                'records_extracted': len(df),
                'tickers_processed': df['ticker'].nunique(),
                'files_uploaded': len(uploaded_files),
                'uploaded_files': uploaded_files,
                'duration_seconds': duration,
                'start_time': start_time.isoformat(),
                'end_time': end_time.isoformat()
            }
            
            logger.info(f"Extração concluída com sucesso: {result}")
            return result
            
        except Exception as e:
            logger.error(f"Erro na extração: {str(e)}")
            return {
                'status': 'error',
                'error_message': str(e),
                'duration_seconds': (datetime.now() - start_time).total_seconds()
            }

def main():
    """Função principal para execução standalone"""
    import argparse
    
    parser = argparse.ArgumentParser(description='Extração de dados da Bovespa')
    parser.add_argument('--bucket', required=True, help='Nome do bucket S3')
    parser.add_argument('--date', help='Data para extração (YYYY-MM-DD)')
    parser.add_argument('--region', default='us-east-1', help='Região AWS')
    
    args = parser.parse_args()
    
    # Inicializar extrator
    extractor = BovespaDataExtractor(
        bucket_name=args.bucket,
        aws_region=args.region
    )
    
    # Executar extração
    result = extractor.run_extraction(args.date)
    
    if result['status'] == 'success':
        print("✅ Extração concluída com sucesso!")
        print(f"📊 Registros extraídos: {result['records_extracted']}")
        print(f"📁 Arquivos enviados: {result['files_uploaded']}")
        print(f"⏱️ Duração: {result['duration_seconds']:.2f}s")
    else:
        print("❌ Erro na extração:")
        print(f"🚨 {result['error_message']}")
        exit(1)

if __name__ == "__main__":
    main()
