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

def spark_to_glue_type(spark_type) -> str:
    """
    Converte tipos do Spark para tipos do Glue Catalog
    
    Args:
        spark_type: Tipo do Spark (DataType)
        
    Returns:
        String com tipo equivalente no Glue
    """
    type_mapping = {
        'StringType': 'string',
        'IntegerType': 'int',
        'LongType': 'bigint',
        'DoubleType': 'double',
        'FloatType': 'float',
        'BooleanType': 'boolean',
        'TimestampType': 'timestamp',
        'DateType': 'date',
        'DecimalType': 'decimal',
        'BinaryType': 'binary'
    }
    
    type_name = type(spark_type).__name__
    
    # Arrays
    if isinstance(spark_type, ArrayType):
        element_type = spark_to_glue_type(spark_type.elementType)
        return f'array<{element_type}>'
    
    # Structs
    if isinstance(spark_type, StructType):
        fields = []
        for field in spark_type.fields:
            field_type = spark_to_glue_type(field.dataType)
            fields.append(f'{field.name}:{field_type}')
        return f'struct<{",".join(fields)}>'
    
    # Maps
    if isinstance(spark_type, MapType):
        key_type = spark_to_glue_type(spark_type.keyType)
        value_type = spark_to_glue_type(spark_type.valueType)
        return f'map<{key_type},{value_type}>'
    
    # Tipos simples
    return type_mapping.get(type_name, 'string')

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
    logger.info(f"Colunas disponíveis: {df.columns}")
    
    # Mostrar schema para debug
    df.printSchema()
    logger.info(f"Total de registros: {df.count()}")
    logger.info("Primeiras 5 linhas:")
    df.show(5, truncate=False)
    
    # Verificar se temos dados de cotação ou composição de carteira
    columns_set = set(df.columns)
    
    # Dados de cotação possuem: ticker, abertura, fechamento, volume
    is_cotacao = 'ticker' in columns_set and 'abertura' in columns_set
    
    # Dados de carteira possuem: codigo, acao, participacao_percentual
    is_carteira = 'codigo' in columns_set and 'participacao_percentual' in columns_set
    
    if is_cotacao:
        logger.info("✅ Detectado: Dados de COTAÇÃO (ticker, abertura, fechamento...)")
        return apply_transformations_cotacao(df)
    elif is_carteira:
        logger.info("✅ Detectado: Dados de COMPOSIÇÃO DA CARTEIRA (codigo, acao, participacao_percentual...)")
        return apply_transformations_carteira(df)
    else:
        # Tentar inferir estrutura
        logger.warning(f"⚠️ Estrutura de dados desconhecida. Colunas: {df.columns}")
        logger.warning("Aplicando transformações genéricas...")
        return apply_transformations_generic(df)

def apply_transformations_cotacao(df: DataFrame) -> DataFrame:
    """
    Transformações para dados de cotação (ticker, data, abertura, fechamento, etc)
    """
    logger.info("Aplicando transformações para dados de COTAÇÃO")
    
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

def apply_transformations_carteira(df: DataFrame) -> DataFrame:
    """
    Transformações para dados de composição da carteira IBOVESPA
    (codigo, acao, participacao_percentual, quantidade_teorica, tipo)
    """
    logger.info("=" * 80)
    logger.info("Aplicando transformações para dados de COMPOSIÇÃO DA CARTEIRA")
    logger.info("=" * 80)
    logger.info(f"Registros de entrada: {df.count()}")
    
    # Adicionar data de referência
    df_with_date = df.withColumn("data_referencia", current_date())
    
    # Extrair ano, mês, dia para particionamento
    df_with_date = df_with_date.withColumn("ano", year("data_referencia")) \
                                 .withColumn("mes", month("data_referencia")) \
                                 .withColumn("dia", dayofmonth("data_referencia"))
    
    logger.info(f"Após adicionar datas: {df_with_date.count()} registros")
    
    # Transformação A: Agrupamento - Total por tipo de ativo
    df_grouped = df_with_date.groupBy("tipo").agg(
        count("*").alias("quantidade_ativos"),
        sum("participacao_percentual").alias("participacao_total"),
        avg("participacao_percentual").alias("participacao_media"),
        sum("quantidade_teorica").alias("quantidade_teorica_total")
    )
    
    logger.info("Transformação A - Agrupamento por tipo:")
    df_grouped.show()
    
    # Transformação B: Renomear colunas
    df_renamed = df_with_date.withColumnRenamed("codigo", "Codigo_Ativo") \
                              .withColumnRenamed("acao", "Nome_Ativo") \
                              .withColumnRenamed("participacao_percentual", "Participacao_Percentual") \
                              .withColumnRenamed("quantidade_teorica", "Quantidade_Teorica") \
                              .withColumnRenamed("tipo", "Tipo_Ativo")
    
    logger.info(f"Transformação B - Após renomear colunas: {df_renamed.count()} registros")
    
    # Transformação C: Cálculo - Ranking de participação
    window_spec = Window.orderBy(col("Participacao_Percentual").desc())
    
    df_with_rank = df_renamed.withColumn(
        "ranking_participacao",
        row_number().over(window_spec)
    ).withColumn(
        "percentil_participacao",
        percent_rank().over(window_spec) * 100
    )
    
    logger.info(f"Transformação C - Após adicionar ranking: {df_with_rank.count()} registros")
    logger.info("Top 5 por ranking:")
    df_with_rank.select("Codigo_Ativo", "Nome_Ativo", "Participacao_Percentual", "ranking_participacao").show(5)
    
    # Join com estatísticas agregadas
    df_final = df_with_rank.join(
        df_grouped,
        on="Tipo_Ativo",
        how="left"
    )
    
    logger.info(f"Após join com estatísticas: {df_final.count()} registros")
    
    # Adicionar metadados
    df_final = df_final.withColumn("data_processamento", current_timestamp()) \
                        .withColumn("versao_processamento", lit("1.0")) \
                        .withColumn("fonte_dados", lit("B3_API_Oficial")) \
                        .withColumn("indice", lit("IBOVESPA"))
    
    logger.info(f"Após adicionar metadados: {df_final.count()} registros")
    
    # Ordenar por ranking
    df_final = df_final.orderBy("ranking_participacao")
    
    logger.info(f"✅ Transformações concluídas. Total final: {df_final.count()} registros")
    logger.info("=" * 80)
    
    return df_final

def apply_transformations_generic(df: DataFrame) -> DataFrame:
    """
    Transformações genéricas quando estrutura não é reconhecida
    """
    logger.info("Aplicando transformações GENÉRICAS")
    
    # Adicionar colunas básicas
    df_with_meta = df.withColumn("data_processamento", current_timestamp()) \
                      .withColumn("versao_processamento", lit("1.0"))
    
    # Transformação A: Contagem total de registros
    total_count = df.count()
    df_with_meta = df_with_meta.withColumn("total_registros", lit(total_count))
    
    # Transformação B: Renomear primeira coluna (se existir)
    if len(df.columns) > 0:
        primeira_col = df.columns[0]
        df_with_meta = df_with_meta.withColumnRenamed(primeira_col, f"{primeira_col}_Processado")
    
    # Transformação C: Adicionar ID sequencial
    window_spec = Window.orderBy(monotonically_increasing_id())
    df_with_meta = df_with_meta.withColumn("id_sequencial", row_number().over(window_spec))
    
    return df_with_meta

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
    logger.info("=" * 80)
    logger.info("SALVANDO DADOS REFINADOS")
    logger.info("=" * 80)
    logger.info(f"Total de registros: {df.count()}")
    logger.info(f"Colunas: {df.columns}")
    df.printSchema()
    logger.info("Primeiras 5 linhas:")
    df.show(5, truncate=False)
    
    # Verificar qual coluna de data usar
    if 'data' in df.columns:
        # Dados de cotação
        date_column = 'data'
    elif 'data_referencia' in df.columns:
        # Dados de carteira
        date_column = 'data_referencia'
    elif 'data_processamento' in df.columns:
        # Usar data de processamento como fallback
        date_column = 'data_processamento'
    else:
        # Criar coluna de data de processamento
        df = df.withColumn('data_processamento', current_date())
        date_column = 'data_processamento'
    
    logger.info(f"Coluna de data selecionada: {date_column}")
    
    # Adicionar coluna de partição por data
    # Se for timestamp, converter para date primeiro
    if date_column == 'data_processamento':
        df_partitioned = df.withColumn(
            "data_particao", 
            date_format(to_date(col(date_column)), "yyyy-MM-dd")
        )
    else:
        df_partitioned = df.withColumn(
            "data_particao", 
            date_format(col(date_column), "yyyy-MM-dd")
        )
    
    logger.info("DataFrame com partição:")
    df_partitioned.select("data_particao").distinct().show()
    
    # Caminho de saída particionado
    output_path = f"s3://{bucket}/{prefix}ticker={ticker}/"
    
    logger.info(f"Caminho de saída: {output_path}")
    logger.info(f"Modo de escrita: overwrite")
    logger.info(f"Formato: Parquet")
    logger.info(f"Particionamento: data_particao")
    
    # Salvar como Parquet particionado por data
    logger.info("Iniciando escrita no S3...")
    df_partitioned.write \
        .mode("overwrite") \
        .partitionBy("data_particao") \
        .parquet(output_path)
    
    logger.info(f"✅ Dados salvos com sucesso em: {output_path}")
    
    return output_path

def catalog_data(glue_context: GlueContext, s3_path: str, ticker: str):
    """
    Cataloga os dados refinados no Glue Data Catalog
    
    Args:
        glue_context: Contexto do Glue
        s3_path: Caminho dos dados no S3
        ticker: Código do ativo ou identificador
    """
    import boto3
    
    glue_client = boto3.client('glue')
    database_name = "tech_challenge_bovespa"
    
    # Determinar nome da tabela baseado no tipo de dado
    if ticker and ticker != 'UNKNOWN':
        table_name = f"dados_refinados_{ticker.lower().replace('.', '_').replace('^', 'indice_')}"
    else:
        # Nome genérico para composição de carteira
        table_name = "dados_refinados_carteira_ibov"
    
    logger.info(f"Catalogando tabela: {database_name}.{table_name}")
    logger.info(f"Caminho S3: {s3_path}")
    
    try:
        # 1. Criar database se não existir
        try:
            glue_client.create_database(
                DatabaseInput={
                    'Name': database_name,
                    'Description': 'Database para dados refinados da Bovespa - Tech Challenge'
                }
            )
            logger.info(f"✅ Database {database_name} criado")
        except glue_client.exceptions.AlreadyExistsException:
            logger.info(f"✓ Database {database_name} já existe")
        
        # 2. Ler dados para obter schema
        dynamic_frame = glue_context.create_dynamic_frame.from_options(
            format_options={},
            connection_type="s3",
            format="parquet",
            connection_options={
                "paths": [s3_path],
                "recurse": True
            }
        )
        
        df = dynamic_frame.toDF()
        
        # 3. Converter schema Spark para Glue
        columns = []
        for field in df.schema.fields:
            glue_type = spark_to_glue_type(field.dataType)
            columns.append({
                'Name': field.name,
                'Type': glue_type,
                'Comment': ''
            })
        
        # 4. Criar/atualizar tabela
        table_input = {
            'Name': table_name,
            'Description': f'Dados refinados da Bovespa - Tabela {table_name}',
            'StorageDescriptor': {
                'Columns': columns,
                'Location': s3_path,
                'InputFormat': 'org.apache.hadoop.hive.ql.io.parquet.MapredParquetInputFormat',
                'OutputFormat': 'org.apache.hadoop.hive.ql.io.parquet.MapredParquetOutputFormat',
                'SerdeInfo': {
                    'SerializationLibrary': 'org.apache.hadoop.hive.ql.io.parquet.serde.ParquetHiveSerDe',
                    'Parameters': {
                        'serialization.format': '1'
                    }
                },
                'StoredAsSubDirectories': False
            },
            'PartitionKeys': [
                {
                    'Name': 'data_particao',
                    'Type': 'string',
                    'Comment': 'Partição por data (formato: yyyy-MM-dd)'
                }
            ],
            'TableType': 'EXTERNAL_TABLE'
        }
        
        try:
            glue_client.create_table(
                DatabaseName=database_name,
                TableInput=table_input
            )
            logger.info(f"✅ Tabela {table_name} CRIADA com sucesso")
        except glue_client.exceptions.AlreadyExistsException:
            glue_client.update_table(
                DatabaseName=database_name,
                TableInput=table_input
            )
            logger.info(f"✅ Tabela {table_name} ATUALIZADA com sucesso")
        
        # 5. Atualizar partições
        try:
            glue_client.start_crawler(CrawlerName=f'{database_name}_crawler')
            logger.info(f"✅ Crawler iniciado para descobrir partições")
        except:
            # Se não tiver crawler, criar partições manualmente via MSCK REPAIR
            logger.info("⚠️ Crawler não disponível. Use MSCK REPAIR TABLE no Athena para adicionar partições")
        
        logger.info(f"✅ Catalogação concluída: {database_name}.{table_name}")
        
    except Exception as e:
        logger.error(f"❌ Erro na catalogação: {str(e)}")
        import traceback
        logger.error(traceback.format_exc())
        # Não falhar o job por erro de catalogação

if __name__ == "__main__":
    main()
