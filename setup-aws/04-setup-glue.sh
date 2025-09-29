#!/bin/bash

# Tech Challenge Bovespa - Setup Glue
# Script para criar job Glue conforme roteiro original

echo "⚙️ Configurando AWS Glue..."

# Carregar configurações
source ./config.env

echo "📋 Configurações:"
echo "  Job: $GLUE_JOB_NAME"
echo "  Database: $GLUE_DATABASE_NAME"
echo "  Role: $GLUE_ROLE_NAME"

# 1. Verificar se o script do Glue existe
if [ ! -f "$GLUE_SCRIPT_PATH" ]; then
    echo "❌ Erro: Script do Glue não encontrado em $GLUE_SCRIPT_PATH"
    exit 1
fi

# 2. Criar bucket para scripts Glue (se não existir)
SCRIPTS_BUCKET="${BUCKET_NAME}-scripts"
echo "📦 Criando bucket para scripts..."

if [[ "$AWS_REGION" == "us-east-1" ]]; then
    aws s3 mb "s3://${SCRIPTS_BUCKET}" 2>/dev/null || echo "Bucket já existe"
else
    aws s3 mb "s3://${SCRIPTS_BUCKET}" --region "$AWS_REGION" 2>/dev/null || echo "Bucket já existe"
fi

# 3. Fazer upload do script Glue
echo "📤 Fazendo upload do script Glue..."
aws s3 cp "$GLUE_SCRIPT_PATH" "s3://${SCRIPTS_BUCKET}/glue_etl_job.py"

if [ $? -eq 0 ]; then
    echo "✅ Script Glue enviado para s3://${SCRIPTS_BUCKET}/glue_etl_job.py"
else
    echo "❌ Erro ao enviar script Glue"
    exit 1
fi

# 4. Criar database no Glue Data Catalog
echo "🗄️ Criando database no Data Catalog..."
aws glue create-database \
    --database-input Name="$GLUE_DATABASE_NAME",Description="Database para dados da Bovespa - Tech Challenge" \
    2>/dev/null || echo "Database já existe"

# 5. Obter ARN da role do Glue
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
GLUE_ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${GLUE_ROLE_NAME}"

echo "📍 Role ARN: $GLUE_ROLE_ARN"

# 6. Criar job do Glue
echo "⚙️ Criando job Glue..."
aws glue create-job \
    --name "$GLUE_JOB_NAME" \
    --role "$GLUE_ROLE_ARN" \
    --command Name=glueetl,ScriptLocation="s3://${SCRIPTS_BUCKET}/glue_etl_job.py",PythonVersion=3 \
    --default-arguments '{
        "--enable-metrics": "true",
        "--enable-continuous-cloudwatch-log": "true",
        "--job-language": "python"
    }' \
    --glue-version "4.0" \
    --worker-type "G.1X" \
    --number-of-workers 2 \
    --timeout 60 \
    --max-retries 2 \
    --description "Tech Challenge Bovespa - Job ETL para processamento de dados"

if [ $? -eq 0 ]; then
    echo "✅ Job Glue criado: $GLUE_JOB_NAME"
else
    echo "❌ Erro ao criar job Glue"
    exit 1
fi

# 7. Testar job Glue (opcional - apenas verificar se está acessível)
echo "🔍 Verificando job Glue..."
aws glue get-job --job-name "$GLUE_JOB_NAME" --query 'Job.Name'

if [ $? -eq 0 ]; then
    echo "✅ Job Glue configurado com sucesso!"
    echo "📍 Job: ${GLUE_JOB_NAME}"
    echo "📍 Script: s3://${SCRIPTS_BUCKET}/glue_etl_job.py"
    echo "📍 Database: ${GLUE_DATABASE_NAME}"
    echo ""
    echo "📋 Próximos passos:"
    echo "   1. Execute: ./05-setup-athena.sh"
    echo "   2. Teste o pipeline executando extração de dados"
else
    echo "❌ Erro na verificação do job Glue"
    exit 1
fi