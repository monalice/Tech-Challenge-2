#!/bin/bash

################################################################################
# Tech Challenge Bovespa - Setup Script AWS Academy
# 
# Este script configura toda a infraestrutura AWS necessária para o pipeline:
# - Bucket S3 com pastas raw/ e refined/
# - Função Lambda com trigger S3
# - Job AWS Glue para ETL
# - Database e tabelas no Glue Catalog
# - Permissões IAM (adaptadas para AWS Academy)
################################################################################

set -e  # Parar em caso de erro

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Função para imprimir mensagens coloridas
print_step() {
    echo -e "${BLUE}==>${NC} ${GREEN}$1${NC}"
}

print_error() {
    echo -e "${RED}[ERRO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[AVISO]${NC} $1"
}

print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

# Verificar se AWS CLI está instalado
if ! command -v aws &> /dev/null; then
    print_error "AWS CLI não está instalado. Instale em: https://aws.amazon.com/cli/"
    exit 1
fi

# Verificar se Python está instalado (necessário como fallback para zip)
if ! command -v python &> /dev/null && ! command -v python3 &> /dev/null; then
    print_error "Python não está instalado. É necessário Python 3.x"
    exit 1
fi

# Definir comando Python correto
if command -v python3 &> /dev/null; then
    PYTHON_CMD="python3"
else
    PYTHON_CMD="python"
fi

print_step "Iniciando setup do Tech Challenge Bovespa Pipeline"

# ============================================================================
# CONFIGURAÇÕES PRINCIPAIS
# ============================================================================

# Solicitar nome único para os recursos
read -p "Digite um sufixo único para seus recursos (ex: seu-nome): " UNIQUE_SUFFIX
if [ -z "$UNIQUE_SUFFIX" ]; then
    print_error "Sufixo não pode ser vazio!"
    exit 1
fi

# Variáveis de configuração
BUCKET_NAME="tech-challenge-bovespa-${UNIQUE_SUFFIX}"
LAMBDA_FUNCTION_NAME="tech-challenge-lambda-${UNIQUE_SUFFIX}"
GLUE_JOB_NAME="tech-challenge-bovespa-etl"
GLUE_DATABASE="tech_challenge_bovespa"
REGION=$(aws configure get region || echo "us-east-1")

# Obter Account ID
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Roles (AWS Academy usa LabRole pré-configurada)
LAB_ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/LabRole"

print_info "Configurações:"
print_info "  Região: ${REGION}"
print_info "  Account ID: ${ACCOUNT_ID}"
print_info "  Bucket: ${BUCKET_NAME}"
print_info "  Lambda: ${LAMBDA_FUNCTION_NAME}"
print_info "  Glue Job: ${GLUE_JOB_NAME}"
print_info "  Role: LabRole (AWS Academy)"

# ============================================================================
# 1. CRIAR BUCKET S3
# ============================================================================

print_step "Etapa 1/6: Criando Bucket S3"

if aws s3 ls "s3://${BUCKET_NAME}" 2>&1 | grep -q 'NoSuchBucket'; then
    if [ "$REGION" == "us-east-1" ]; then
        aws s3 mb "s3://${BUCKET_NAME}"
    else
        aws s3 mb "s3://${BUCKET_NAME}" --region "${REGION}"
    fi
    print_info "Bucket ${BUCKET_NAME} criado com sucesso"
else
    print_warning "Bucket ${BUCKET_NAME} já existe"
fi

# Criar estrutura de pastas
print_info "Criando estrutura de pastas..."
touch /tmp/placeholder.txt
aws s3 cp /tmp/placeholder.txt "s3://${BUCKET_NAME}/raw/.placeholder" --quiet
aws s3 cp /tmp/placeholder.txt "s3://${BUCKET_NAME}/refined/.placeholder" --quiet
aws s3 rm "s3://${BUCKET_NAME}/raw/.placeholder" --quiet 2>/dev/null || true
aws s3 rm "s3://${BUCKET_NAME}/refined/.placeholder" --quiet 2>/dev/null || true
rm /tmp/placeholder.txt

print_info "Estrutura de pastas criada: raw/ e refined/"

# ============================================================================
# 2. CRIAR DATABASE NO GLUE CATALOG
# ============================================================================

print_step "Etapa 2/6: Criando Database no Glue Catalog"

# Verificar se database já existe
if aws glue get-database --name "${GLUE_DATABASE}" --region "${REGION}" 2>/dev/null; then
    print_warning "Database ${GLUE_DATABASE} já existe"
else
    aws glue create-database \
        --database-input "{
            \"Name\": \"${GLUE_DATABASE}\",
            \"Description\": \"Database para dados da Bovespa - Tech Challenge\"
        }" \
        --region "${REGION}"
    print_info "Database ${GLUE_DATABASE} criado com sucesso"
fi

# ============================================================================
# 3. FAZER UPLOAD DO SCRIPT GLUE PARA S3
# ============================================================================

print_step "Etapa 3/6: Fazendo upload do script Glue para S3"

# Criar pasta para scripts
SCRIPTS_PATH="s3://${BUCKET_NAME}/glue-scripts/"

if [ -f "fase3-glue/glue_etl_job.py" ]; then
    aws s3 cp fase3-glue/glue_etl_job.py "${SCRIPTS_PATH}glue_etl_job.py"
    print_info "Script Glue enviado para ${SCRIPTS_PATH}glue_etl_job.py"
else
    print_error "Arquivo fase3-glue/glue_etl_job.py não encontrado!"
    exit 1
fi

# ============================================================================
# 4. CRIAR JOB GLUE
# ============================================================================

print_step "Etapa 4/6: Criando Job Glue"

# Verificar se job já existe
if aws glue get-job --job-name "${GLUE_JOB_NAME}" --region "${REGION}" 2>/dev/null; then
    print_warning "Job Glue ${GLUE_JOB_NAME} já existe. Atualizando..."
    
    aws glue update-job \
        --job-name "${GLUE_JOB_NAME}" \
        --job-update "{
            \"Role\": \"${LAB_ROLE_ARN}\",
            \"Command\": {
                \"Name\": \"glueetl\",
                \"ScriptLocation\": \"${SCRIPTS_PATH}glue_etl_job.py\",
                \"PythonVersion\": \"3\"
            },
            \"DefaultArguments\": {
                \"--job-language\": \"python\",
                \"--TempDir\": \"s3://${BUCKET_NAME}/glue-temp/\",
                \"--enable-metrics\": \"true\",
                \"--enable-spark-ui\": \"true\",
                \"--spark-event-logs-path\": \"s3://${BUCKET_NAME}/glue-logs/\",
                \"--enable-job-insights\": \"true\",
                \"--enable-glue-datacatalog\": \"true\"
            },
            \"MaxRetries\": 0,
            \"Timeout\": 2880,
            \"GlueVersion\": \"3.0\",
            \"NumberOfWorkers\": 2,
            \"WorkerType\": \"G.1X\"
        }" \
        --region "${REGION}"
    
    print_info "Job Glue atualizado"
else
    aws glue create-job \
        --name "${GLUE_JOB_NAME}" \
        --role "${LAB_ROLE_ARN}" \
        --command "{
            \"Name\": \"glueetl\",
            \"ScriptLocation\": \"${SCRIPTS_PATH}glue_etl_job.py\",
            \"PythonVersion\": \"3\"
        }" \
        --default-arguments "{
            \"--job-language\": \"python\",
            \"--TempDir\": \"s3://${BUCKET_NAME}/glue-temp/\",
            \"--enable-metrics\": \"true\",
            \"--enable-spark-ui\": \"true\",
            \"--spark-event-logs-path\": \"s3://${BUCKET_NAME}/glue-logs/\",
            \"--enable-job-insights\": \"true\",
            \"--enable-glue-datacatalog\": \"true\"
        }" \
        --max-retries 0 \
        --timeout 2880 \
        --glue-version "3.0" \
        --number-of-workers 2 \
        --worker-type "G.1X" \
        --region "${REGION}"
    
    print_info "Job Glue ${GLUE_JOB_NAME} criado com sucesso"
fi

# ============================================================================
# 5. CRIAR FUNÇÃO LAMBDA
# ============================================================================

print_step "Etapa 5/6: Criando Função Lambda"

# Preparar código Lambda
print_info "Preparando código Lambda..."
cd fase2-lambda

# Criar arquivo zip com a função Lambda
if [ -f "lambda_function.py" ]; then
    # Verificar se zip está disponível
    if command -v zip &> /dev/null; then
        zip -q lambda_function.zip lambda_function.py
    else
        # Usar Python como alternativa (sempre disponível)
        print_warning "Comando 'zip' não encontrado. Usando Python para criar o arquivo zip..."
        $PYTHON_CMD -c "import zipfile; zipfile.ZipFile('lambda_function.zip', 'w', zipfile.ZIP_DEFLATED).write('lambda_function.py')"
    fi
    print_info "Código Lambda empacotado"
else
    print_error "Arquivo lambda_function.py não encontrado!"
    cd ..
    exit 1
fi

# Criar ou atualizar função Lambda
if aws lambda get-function --function-name "${LAMBDA_FUNCTION_NAME}" --region "${REGION}" 2>/dev/null; then
    print_warning "Função Lambda ${LAMBDA_FUNCTION_NAME} já existe. Atualizando código..."
    
    aws lambda update-function-code \
        --function-name "${LAMBDA_FUNCTION_NAME}" \
        --zip-file fileb://lambda_function.zip \
        --region "${REGION}" \
        --output text > /dev/null
    
    print_info "Código Lambda atualizado"
else
    aws lambda create-function \
        --function-name "${LAMBDA_FUNCTION_NAME}" \
        --runtime python3.11 \
        --role "${LAB_ROLE_ARN}" \
        --handler lambda_function.lambda_handler \
        --zip-file fileb://lambda_function.zip \
        --timeout 300 \
        --memory-size 256 \
        --environment "Variables={
            GLUE_JOB_NAME=${GLUE_JOB_NAME},
            TARGET_BUCKET=${BUCKET_NAME}
        }" \
        --region "${REGION}" \
        --output text > /dev/null
    
    print_info "Função Lambda ${LAMBDA_FUNCTION_NAME} criada com sucesso"
    
    # Aguardar a função estar ativa
    print_info "Aguardando função Lambda ficar ativa..."
    aws lambda wait function-active \
        --function-name "${LAMBDA_FUNCTION_NAME}" \
        --region "${REGION}"
fi

# Limpar arquivo zip
rm lambda_function.zip
cd ..

# ============================================================================
# 6. CONFIGURAR TRIGGER S3 -> LAMBDA
# ============================================================================

print_step "Etapa 6/6: Configurando Trigger S3 -> Lambda"

# Dar permissão ao S3 para invocar a Lambda
print_info "Configurando permissões S3 -> Lambda..."

STATEMENT_ID="s3-trigger-${UNIQUE_SUFFIX}"

# Remover permissão antiga se existir
aws lambda remove-permission \
    --function-name "${LAMBDA_FUNCTION_NAME}" \
    --statement-id "${STATEMENT_ID}" \
    --region "${REGION}" 2>/dev/null || true

# Adicionar nova permissão
aws lambda add-permission \
    --function-name "${LAMBDA_FUNCTION_NAME}" \
    --statement-id "${STATEMENT_ID}" \
    --action "lambda:InvokeFunction" \
    --principal s3.amazonaws.com \
    --source-arn "arn:aws:s3:::${BUCKET_NAME}" \
    --region "${REGION}" \
    --output text > /dev/null

print_info "Permissão S3 -> Lambda configurada"

# Configurar notificação S3
print_info "Configurando notificação S3..."

LAMBDA_ARN=$(aws lambda get-function \
    --function-name "${LAMBDA_FUNCTION_NAME}" \
    --region "${REGION}" \
    --query 'Configuration.FunctionArn' \
    --output text)

# Criar configuração de notificação
cat > /tmp/notification.json <<EOF
{
    "LambdaFunctionConfigurations": [
        {
            "Id": "trigger-lambda-on-raw-upload",
            "LambdaFunctionArn": "${LAMBDA_ARN}",
            "Events": ["s3:ObjectCreated:*"],
            "Filter": {
                "Key": {
                    "FilterRules": [
                        {
                            "Name": "prefix",
                            "Value": "raw/"
                        },
                        {
                            "Name": "suffix",
                            "Value": ".parquet"
                        }
                    ]
                }
            }
        }
    ]
}
EOF

aws s3api put-bucket-notification-configuration \
    --bucket "${BUCKET_NAME}" \
    --notification-configuration file:///tmp/notification.json \
    --region "${REGION}"

rm /tmp/notification.json

print_info "Trigger S3 -> Lambda configurado com sucesso"

# ============================================================================
# RESUMO FINAL
# ============================================================================

echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║         SETUP CONCLUÍDO COM SUCESSO! ✓                         ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""
print_info "Recursos criados:"
echo "  ✓ Bucket S3: ${BUCKET_NAME}"
echo "  ✓ Database Glue: ${GLUE_DATABASE}"
echo "  ✓ Job Glue: ${GLUE_JOB_NAME}"
echo "  ✓ Função Lambda: ${LAMBDA_FUNCTION_NAME}"
echo "  ✓ Trigger S3 -> Lambda configurado"
echo ""
print_info "Próximos passos:"
echo "  1. Execute o scraper para coletar dados:"
echo "     cd fase1-extracao"
echo "     python b3_scraper_new.py --bucket ${BUCKET_NAME} --save-s3"
echo ""
echo "  2. O pipeline será executado automaticamente:"
echo "     Upload S3 -> Lambda -> Glue Job -> Catalog -> Athena"
echo ""
echo "  3. Consulte os dados no Athena:"
echo "     Database: ${GLUE_DATABASE}"
echo "     Tabelas: dados_refinados_*"
echo ""
print_warning "IMPORTANTE: Salve estas informações!"
echo ""
echo "BUCKET_NAME=${BUCKET_NAME}" > .env.aws
echo "LAMBDA_FUNCTION_NAME=${LAMBDA_FUNCTION_NAME}" >> .env.aws
echo "GLUE_JOB_NAME=${GLUE_JOB_NAME}" >> .env.aws
echo "GLUE_DATABASE=${GLUE_DATABASE}" >> .env.aws
echo "REGION=${REGION}" >> .env.aws
echo "ACCOUNT_ID=${ACCOUNT_ID}" >> .env.aws

print_info "Configurações salvas em .env.aws"
echo ""
