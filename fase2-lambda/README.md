# Fase 2: Gatilho com AWS Lambda

## Visão Geral
Esta fase implementa uma função Lambda que é acionada automaticamente quando novos arquivos Parquet são adicionados à pasta `raw/` do bucket S3. A função então inicia o job do AWS Glue para processamento dos dados.

## Componentes

### 1. lambda_function.py
Função principal que:
- Processa eventos S3 de criação de objetos
- Filtra apenas arquivos Parquet na pasta `raw/`
- Extrai metadados do caminho do arquivo
- Inicia job do AWS Glue com parâmetros apropriados

### 2. lambda-policy.json
Política IAM com permissões mínimas necessárias:
- Iniciar jobs do Glue
- Ler metadados de objetos S3
- Escrever logs no CloudWatch

## Configuração

### Variáveis de Ambiente
A função Lambda deve ter as seguintes variáveis de ambiente configuradas:

| Variável | Descrição | Valor Exemplo |
|----------|-----------|---------------|
| GLUE_JOB_NAME | Nome do job do Glue | tech-challenge-bovespa-etl |

### Configurações da Lambda
- **Runtime**: Python 3.9+
- **Timeout**: 5 minutos
- **Memory**: 128 MB
- **Role**: Usar política do arquivo `lambda-policy.json`

## Trigger S3

### Configuração do Evento
- **Bucket**: tech-challenge-bovespa-{nome}
- **Event Type**: All object create events
- **Prefix**: raw/
- **Suffix**: .parquet

## Funcionamento

### Fluxo de Execução
1. **Trigger**: Arquivo Parquet é criado em `raw/`
2. **Validação**: Lambda verifica se é arquivo válido
3. **Extração**: Extrai metadados do caminho (ano, mês, dia, ticker)
4. **Glue Job**: Inicia job com parâmetros extraídos
5. **Log**: Registra resultado da operação

### Exemplo de Evento S3
```json
{
  "Records": [
    {
      "eventSource": "aws:s3",
      "eventName": "ObjectCreated:Put",
      "s3": {
        "bucket": {
          "name": "tech-challenge-bovespa-exemplo"
        },
        "object": {
          "key": "raw/ano=2025/mes=09/dia=23/PETR4.SA_2025-09-23.parquet"
        }
      }
    }
  ]
}
```

### Parâmetros Passados para o Glue
- `--source_bucket`: Nome do bucket S3
- `--source_key`: Chave do arquivo S3
- `--target_bucket`: Bucket de destino
- `--target_prefix`: Prefixo da pasta refined
- `--partition_year`: Ano da partição
- `--partition_month`: Mês da partição
- `--partition_day`: Dia da partição
- `--ticker`: Código do ativo
- `--execution_time`: Timestamp da execução

## Deploy

### Via AWS CLI
```bash
# Criar pacote de deployment
zip lambda-deployment.zip lambda_function.py

# Criar função Lambda
aws lambda create-function \
  --function-name tech-challenge-bovespa-trigger \
  --runtime python3.9 \
  --role arn:aws:iam::ACCOUNT:role/lambda-execution-role \
  --handler lambda_function.lambda_handler \
  --zip-file fileb://lambda-deployment.zip \
  --timeout 300

# Configurar variável de ambiente
aws lambda update-function-configuration \
  --function-name tech-challenge-bovespa-trigger \
  --environment Variables='{GLUE_JOB_NAME=tech-challenge-bovespa-etl}'

# Adicionar permissão para S3
aws lambda add-permission \
  --function-name tech-challenge-bovespa-trigger \
  --principal s3.amazonaws.com \
  --action lambda:InvokeFunction \
  --source-arn arn:aws:s3:::tech-challenge-bovespa-*
```

## Logs e Monitoramento

### CloudWatch Logs
A função gera logs detalhados incluindo:
- Eventos S3 recebidos
- Arquivos processados/ignorados
- Metadados extraídos
- Status de inicialização do job Glue
- Erros e warnings

### Exemplo de Log
```
[INFO] Processando arquivo: s3://bucket/raw/ano=2025/mes=09/dia=23/PETR4.SA_2025-09-23.parquet
[INFO] Metadados extraídos: {'ano': 2025, 'mes': 9, 'dia': 23, 'ticker': 'PETR4.SA'}
[INFO] Iniciando job do Glue: tech-challenge-bovespa-etl
[INFO] Job do Glue iniciado com sucesso. Job Run ID: jr_abc123
```

## Tratamento de Erros

A função implementa tratamento robusto de erros:
- Validação de formato de arquivo
- Verificação de pasta de origem
- Retry automático para falhas temporárias
- Logs detalhados para debugging

## Próximos Passos

Após configuração da Lambda:
1. Teste com upload manual de arquivo Parquet
2. Verifique logs no CloudWatch
3. Confirme se job do Glue foi iniciado
4. Prossiga para Fase 3 (Configuração do Glue)
