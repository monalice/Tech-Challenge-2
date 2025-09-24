"""
Tech Challenge: Pipeline Batch Bovespa
Fase 3: Job ETL do AWS Glue

Este script processa os dados brutos da Bovespa aplicando as transformações
obrigatórias e salvando na camada refined com catalogação automática.
"""

import sys
from awsglue.transforms import *
from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext
from awsglue.context import GlueContext
from awsglue.job import Job
from pyspark.sql import DataFrame
from pyspark.sql.functions import *
from pyspark.sql.window import Window
from pyspark.sql.types import *
import logging

# Configuração de logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

def main():
    """Função principal do job Glue"""
    
    # Obter argumentos do job
    args = getResolvedOptions(sys.argv, [
        'JOB_NAME',
        'source_bucket',
        'source_key', 
        'target_bucket',
        'target_prefix',
        'partition_year',
        'partition_month',
        'partition_day',
        'ticker',
        'execution_time'
    ])
    
    # Inicializar contextos Spark e Glue
    sc = SparkContext()
    glueContext = GlueContext(sc)
    spark = glueContext.spark_session
    job = Job(glueContext)
    job.init(args['JOB_NAME'], args)
    
    logger.info(f"Iniciando job ETL: {args['JOB_NAME']}")
    logger.info(f"Processando arquivo: s3://{args['source_bucket']}/{args['source_key']}")
    
    try:
        # 1. Leitura dos dados brutos
        df_raw = read_raw_data(glueContext, args['source_bucket'], args['source_key'])
        logger.info(f"Dados brutos carregados: {df_raw.count()} registros")
        
        # 2. Aplicar transformações obrigatórias
        df_transformed = apply_transformations(df_raw)
        logger.info(f"Transformações aplicadas: {df_transformed.count()} registros")
        
        # 3. Salvar dados refinados
        output_path = save_refined_data(
            df_transformed, 
            args['target_bucket'], 
            args['target_prefix'],
            args['ticker']
        )
        logger.info(f"Dados salvos em: {output_path}")
        
        # 4. Catalogar dados
        catalog_data(glueContext, output_path, args['ticker'])
        logger.info("Dados catalogados com sucesso")
        
        job.commit()
        logger.info("Job concluído com sucesso")
        
    except Exception as e:
        logger.error(f"Erro no job ETL: {str(e)}")
        raise e

def read_raw_data(glue_context: GlueContext, bucket: str, key: str) -> DataFrame:
    """
    Lê dados brutos do S3
    
    Args:
        glue_context: Contexto do Glue
        bucket: Nome do bucket
        key: Chave do arquivo
        
    Returns:
        DataFrame com dados brutos
    """
    s3_path = f"s3://{bucket}/{key}"
    
    # Criar DynamicFrame a partir do arquivo Parquet
    dynamic_frame = glue_context.create_dynamic_frame.from_options(
        format_options={},
        connection_type="s3",
        format="parquet",
        connection_options={
            "paths": [s3_path]
        }
    )
    
    # Converter para DataFrame do Spark
    df = dynamic_frame.toDF()
    
    return df

def apply_transformations(df: DataFrame) -> DataFrame:
    """
    Aplica as transformações obrigatórias do desafio
    
    Args:
        df: DataFrame com dados brutos
        
    Returns:
        DataFrame transformado
    """
    logger.info("Aplicando transformações obrigatórias")
    
    # Transformação A: Agrupamento - Volume médio negociado por mês
    df_monthly_avg = df.groupBy(
        "ticker", 
        "ano", 
        "mes"
    ).agg(
        avg("volume").alias("volume_medio_mensal"),
        count("*").alias("dias_negociacao"),
        min("data").alias("primeira_data_mes"),
        max("data").alias("ultima_data_mes")
    )
    
    # Transformação B: Renomear colunas conforme especificado
    df_renamed = df.withColumnRenamed("abertura", "Abertura") \
                   .withColumnRenamed("maxima", "Maxima_Dia") \
                   .withColumnRenamed("minima", "Minima_Dia") \
                   .withColumnRenamed("fechamento", "Fechamento") \
                   .withColumnRenamed("volume", "Volume")
    
    # Transformação C: Cálculo temporal - Média móvel de 7 dias
    window_spec = Window.partitionBy("ticker") \
                        .orderBy("data") \
                        .rowsBetween(-6, 0)  # 7 dias incluindo o atual
    
    df_with_moving_avg = df_renamed.withColumn(
        "media_movel_7_dias_fechamento",
        avg("Fechamento").over(window_spec)
    )
    
    # Adicionar as estatísticas mensais ao DataFrame principal
    df_final = df_with_moving_avg.join(
        df_monthly_avg,
        on=["ticker", "ano", "mes"],
        how="left"
    )
    
    # Adicionar colunas de metadados do processamento
    df_final = df_final.withColumn("data_processamento", current_timestamp()) \
                       .withColumn("versao_processamento", lit("1.0")) \
                       .withColumn("algoritmo_media_movel", lit("7_dias_simples"))
    
    # Ordenar por ticker e data
    df_final = df_final.orderBy("ticker", "data")
    
    return df_final

def save_refined_data(df: DataFrame, bucket: str, prefix: str, ticker: str) -> str:
    """
    Salva dados refinados no S3 com particionamento
    
    Args:
        df: DataFrame refinado
        bucket: Bucket de destino
        prefix: Prefixo da pasta refined
        ticker: Código do ativo
        
    Returns:
        Caminho de saída
    """
    # Adicionar coluna de partição por data
    df_partitioned = df.withColumn(
        "data_particao", 
        date_format("data", "yyyy-MM-dd")
    )
    
    # Caminho de saída particionado
    output_path = f"s3://{bucket}/{prefix}ticker={ticker}/"
    
    logger.info(f"Salvando dados refinados em: {output_path}")
    
    # Salvar como Parquet particionado por data
    df_partitioned.write \
        .mode("overwrite") \
        .partitionBy("data_particao") \
        .parquet(output_path)
    
    return output_path

def catalog_data(glue_context: GlueContext, s3_path: str, ticker: str):
    """
    Cataloga os dados refinados no Glue Data Catalog
    
    Args:
        glue_context: Contexto do Glue
        s3_path: Caminho dos dados no S3
        ticker: Código do ativo
    """
    database_name = "tech_challenge_bovespa"
    table_name = f"dados_refinados_{ticker.lower().replace('.', '_').replace('^', 'indice_')}"
    
    logger.info(f"Catalogando tabela: {database_name}.{table_name}")
    
    try:
        # Criar DynamicFrame dos dados refinados
        dynamic_frame = glue_context.create_dynamic_frame.from_options(
            format_options={},
            connection_type="s3",
            format="parquet",
            connection_options={
                "paths": [s3_path]
            }
        )
        
        # Catalogar no Data Catalog
        glue_context.write_dynamic_frame.from_catalog(
            frame=dynamic_frame,
            database=database_name,
            table_name=table_name,
            additional_options={
                "enableUpdateCatalog": True,
                "updateBehavior": "UPDATE_IN_DATABASE"
            }
        )
        
        logger.info(f"Tabela {table_name} catalogada com sucesso")
        
    except Exception as e:
        logger.warning(f"Erro na catalogação (não crítico): {str(e)}")
        # Não falhar o job por erro de catalogação

def create_database_if_not_exists(glue_context: GlueContext, database_name: str):
    """
    Cria database no Glue Data Catalog se não existir
    
    Args:
        glue_context: Contexto do Glue
        database_name: Nome do database
    """
    try:
        glue_client = glue_context.get_glue_client()
        
        glue_client.create_database(
            DatabaseInput={
                'Name': database_name,
                'Description': 'Database para dados da Bovespa - Tech Challenge'
            }
        )
        logger.info(f"Database {database_name} criado")
        
    except glue_client.exceptions.AlreadyExistsException:
        logger.info(f"Database {database_name} já existe")
    except Exception as e:
        logger.warning(f"Erro ao criar database: {str(e)}")

if __name__ == "__main__":
    main()
