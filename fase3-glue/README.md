# Fase 3: Transformação e Catalogação com AWS Glue

## Visão Geral
Esta fase implementa o job ETL do AWS Glue que processa os dados brutos da Bovespa, aplica as transformações obrigatórias e salva os dados refinados com catalogação automática.

## Componentes

### 1. glue_etl_job.py
Script principal do job Glue que implementa:

#### Transformações Obrigatórias:
- **Transformação A (Agrupamento)**: Calcula volume médio negociado por mês para cada ativo
- **Transformação B (Renomeação)**: Renomeia colunas Open→Abertura, High→Maxima_Dia  
- **Transformação C (Cálculo Temporal)**: Adiciona média móvel de 7 dias dos preços de fechamento

#### Funcionalidades Adicionais:
- Particionamento automático por ticker e data
- Catalogação no Glue Data Catalog
- Logs detalhados de execução
- Tratamento robusto de erros

### 2. requirements.txt
**IMPORTANTE**: As dependências `awsglue` e `pyspark` são **pré-instaladas** no ambiente AWS Glue.
- **Não instale localmente**: Causará erro pois não estão disponíveis via pip
- **Para desenvolvimento local**: Use `requirements-dev.txt` (opcional)

### 3. glue-service-policy.json
Política IAM com permissões para:
- Leitura de dados brutos no S3
- Escrita de dados refinados no S3
- Operações no Glue Data Catalog
- Criação de logs no CloudWatch

## Desenvolvimento Local (Opcional)

Se você quiser testar a lógica ETL localmente:

```bash
# Instalar dependências de desenvolvimento
pip install -r requirements-dev.txt

# Ou instalar PySpark diretamente
pip install pyspark==3.3.0 boto3 pandas pyarrow
```

**Nota**: O código completo só funcionará no ambiente AWS Glue devido às bibliotecas específicas.

## Configuração do Job

### Parâmetros do Job
O job recebe os seguintes parâmetros da função Lambda:

| Parâmetro | Descrição | Exemplo |
|-----------|-----------|---------|
| source_bucket | Bucket dos dados brutos | tech-challenge-bovespa-exemplo |
| source_key | Chave do arquivo bruto | raw/ano=2025/mes=09/dia=23/PETR4.SA_2025-09-23.parquet |
| target_bucket | Bucket dos dados refinados | tech-challenge-bovespa-exemplo |
| target_prefix | Prefixo da pasta refined | refined/ |
| partition_year | Ano da partição | 2025 |
| partition_month | Mês da partição | 09 |
| partition_day | Dia da partição | 23 |
| ticker | Código do ativo | PETR4.SA |
| execution_time | Timestamp da execução | 2025-09-23T10:30:00 |

### Configurações Recomendadas
- **Job Type**: Spark ETL script
- **Glue Version**: 4.0
- **Language**: Python 3
- **Worker Type**: G.1X
- **Number of Workers**: 2-5 (dependendo do volume)
- **Job Timeout**: 60 minutos
- **Max Retries**: 2

## Estrutura de Dados

### Dados de Entrada (Raw)
```
├── data: timestamp
├── ticker: string  
├── abertura: double
├── maxima: double
├── minima: double
├── fechamento: double
├── volume: long
├── data_extracao: timestamp
├── ano: int
├── mes: int
└── dia: int
```

### Dados de Saída (Refined)
```
├── data: timestamp
├── ticker: string
├── Abertura: double              # Renomeado
├── Maxima_Dia: double           # Renomeado  
├── Minima_Dia: double
├── Fechamento: double
├── Volume: long
├── media_movel_7_dias_fechamento: double    # Novo cálculo
├── volume_medio_mensal: double              # Agregação
├── dias_negociacao: int                     # Agregação
├── primeira_data_mes: date                  # Agregação
├── ultima_data_mes: date                    # Agregação
├── data_processamento: timestamp            # Metadado
├── versao_processamento: string             # Metadado
├── algoritmo_media_movel: string            # Metadado
└── data_particao: string                    # Partição
```

## Particionamento de Saída

### Estrutura no S3
```
s3://bucket/refined/
├── ticker=PETR4.SA/
│   ├── data_particao=2025-09-23/
│   │   └── part-00000.parquet
│   └── data_particao=2025-09-24/
├── ticker=VALE3.SA/
└── ticker=BVSP/
```

## Catalogação

### Database: tech_challenge_bovespa
O job cria automaticamente tabelas no Data Catalog:

- `dados_refinados_petr4_sa`: Dados da Petrobras
- `dados_refinados_vale3_sa`: Dados da Vale  
- `dados_refinados_indice_bvsp`: Dados do Ibovespa

### Schema das Tabelas
As tabelas catalogadas incluem:
- Schema completo com tipos de dados
- Partições automáticas por `data_particao`
- Metadados de origem e processamento
- Formato Parquet otimizado para consultas

## Deploy do Job

### Via AWS CLI
```bash
# Fazer upload do script
aws s3 cp glue_etl_job.py s3://your-glue-scripts-bucket/

# Criar o job
aws glue create-job \
  --name tech-challenge-bovespa-etl \
  --role arn:aws:iam::ACCOUNT:role/glue-service-role \
  --command '{
    "Name": "glueetl",
    "ScriptLocation": "s3://your-glue-scripts-bucket/glue_etl_job.py",
    "PythonVersion": "3"
  }' \
  --default-arguments '{
    "--enable-metrics": "true",
    "--enable-continuous-cloudwatch-log": "true",
    "--job-language": "python"
  }' \
  --glue-version "4.0" \
  --worker-type "G.1X" \
  --number-of-workers 2 \
  --timeout 60
```

### Via Terraform
```hcl
resource "aws_glue_job" "bovespa_etl" {
  name     = "tech-challenge-bovespa-etl"
  role_arn = aws_iam_role.glue_service_role.arn
  
  command {
    name            = "glueetl"
    script_location = "s3://${aws_s3_bucket.scripts.bucket}/glue_etl_job.py"
    python_version  = "3"
  }
  
  default_arguments = {
    "--enable-metrics"                     = "true"
    "--enable-continuous-cloudwatch-log"  = "true"
    "--job-language"                       = "python"
  }
  
  glue_version      = "4.0"
  worker_type      = "G.1X"
  number_of_workers = 2
  timeout          = 60
  max_retries      = 2
}
```

## Monitoramento

### CloudWatch Logs
O job gera logs detalhados em:
```
/aws-glue/jobs/logs-v2
└── tech-challenge-bovespa-etl/
    └── {job-run-id}/
        ├── driver/
        └── executors/
```

### Métricas Importantes
- **Duração da execução**: Tempo total do job
- **Registros processados**: Número de linhas transformadas
- **Erros**: Falhas durante execução
- **Uso de recursos**: CPU e memória utilizados

### Exemplo de Logs
```
[INFO] Iniciando job ETL: tech-challenge-bovespa-etl
[INFO] Processando arquivo: s3://bucket/raw/ano=2025/mes=09/dia=23/PETR4.SA_2025-09-23.parquet
[INFO] Dados brutos carregados: 1 registros
[INFO] Transformações aplicadas: 1 registros
[INFO] Dados salvos em: s3://bucket/refined/ticker=PETR4.SA/
[INFO] Tabela dados_refinados_petr4_sa catalogada com sucesso
[INFO] Job concluído com sucesso
```

## Validação e Testes

### Teste Local (Desenvolvimento)
```bash
# Instalar dependências
pip install pyspark boto3

# Executar com dados de teste
python test_glue_job.py
```

### Validação no AWS
1. **Teste Manual**: Executar job via console
2. **Validação de Dados**: Verificar saída no S3
3. **Teste de Catalogação**: Consultar via Athena
4. **Monitoramento**: Verificar logs e métricas

## Próximos Passos

Após configuração do job Glue:
1. Teste com dados reais da Fase 1
2. Valide transformações aplicadas
3. Confirme catalogação no Data Catalog
4. Prossiga para Fase 4 (Consultas Athena)
