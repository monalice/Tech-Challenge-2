#!/bin/bash

################################################################################
# Tech Challenge Bovespa - Cleanup Script AWS Academy
# 
# Este script remove todos os recursos AWS criados pelo setup.sh:
# - Função Lambda e permissões
# - Job AWS Glue
# - Database e tabelas do Glue Catalog
# - Bucket S3 e todo seu conteúdo
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

print_step "Iniciando cleanup do Tech Challenge Bovespa Pipeline"

# ============================================================================
# CARREGAR CONFIGURAÇÕES
# ============================================================================

if [ -f ".env.aws" ]; then
    print_info "Carregando configurações de .env.aws..."
    source .env.aws
    
    print_info "Configurações carregadas:"
    echo "  Bucket: ${BUCKET_NAME}"
    echo "  Lambda: ${LAMBDA_FUNCTION_NAME}"
    echo "  Glue Job: ${GLUE_JOB_NAME}"
    echo "  Database: ${GLUE_DATABASE}"
    echo "  Região: ${REGION}"
else
    print_warning "Arquivo .env.aws não encontrado. Solicitando informações manualmente..."
    
    read -p "Digite o sufixo usado no setup (ex: seu-nome): " UNIQUE_SUFFIX
    if [ -z "$UNIQUE_SUFFIX" ]; then
        print_error "Sufixo não pode ser vazio!"
        exit 1
    fi
    
    BUCKET_NAME="tech-challenge-bovespa-${UNIQUE_SUFFIX}"
    LAMBDA_FUNCTION_NAME="tech-challenge-lambda-${UNIQUE_SUFFIX}"
    GLUE_JOB_NAME="tech-challenge-bovespa-etl"
    GLUE_DATABASE="tech_challenge_bovespa"
    REGION=$(aws configure get region || echo "us-east-1")
fi

# Confirmação do usuário
echo ""
print_warning "ATENÇÃO: Esta operação é IRREVERSÍVEL!"
print_warning "Todos os recursos e dados serão permanentemente deletados."
echo ""
echo "Recursos que serão removidos:"
echo "  - Bucket S3: ${BUCKET_NAME} (incluindo TODOS os dados)"
echo "  - Função Lambda: ${LAMBDA_FUNCTION_NAME}"
echo "  - Job Glue: ${GLUE_JOB_NAME}"
echo "  - Database Glue: ${GLUE_DATABASE} (incluindo todas as tabelas)"
echo ""
read -p "Deseja continuar? Digite 'SIM' para confirmar: " CONFIRM

if [ "$CONFIRM" != "SIM" ]; then
    print_info "Operação cancelada pelo usuário."
    exit 0
fi

echo ""

# ============================================================================
# 1. REMOVER TRIGGER S3 E PERMISSÕES LAMBDA
# ============================================================================

print_step "Etapa 1/5: Removendo Trigger S3 e Permissões Lambda"

# Remover notificação do bucket S3
if aws s3api get-bucket-notification-configuration \
    --bucket "${BUCKET_NAME}" \
    --region "${REGION}" 2>/dev/null | grep -q "LambdaFunctionConfigurations"; then
    
    print_info "Removendo notificação S3..."
    aws s3api put-bucket-notification-configuration \
        --bucket "${BUCKET_NAME}" \
        --notification-configuration '{}' \
        --region "${REGION}" 2>/dev/null || true
    
    print_info "Notificação S3 removida"
else
    print_warning "Nenhuma notificação S3 encontrada"
fi

# Remover permissão Lambda
STATEMENT_ID="s3-trigger-${UNIQUE_SUFFIX:-default}"
print_info "Removendo permissão S3 -> Lambda..."
aws lambda remove-permission \
    --function-name "${LAMBDA_FUNCTION_NAME}" \
    --statement-id "${STATEMENT_ID}" \
    --region "${REGION}" 2>/dev/null || print_warning "Permissão não encontrada"

# ============================================================================
# 2. DELETAR FUNÇÃO LAMBDA
# ============================================================================

print_step "Etapa 2/5: Deletando Função Lambda"

if aws lambda get-function \
    --function-name "${LAMBDA_FUNCTION_NAME}" \
    --region "${REGION}" 2>/dev/null; then
    
    print_info "Deletando função Lambda ${LAMBDA_FUNCTION_NAME}..."
    aws lambda delete-function \
        --function-name "${LAMBDA_FUNCTION_NAME}" \
        --region "${REGION}"
    
    print_info "Função Lambda deletada"
else
    print_warning "Função Lambda ${LAMBDA_FUNCTION_NAME} não encontrada"
fi

# ============================================================================
# 3. DELETAR JOB GLUE
# ============================================================================

print_step "Etapa 3/5: Deletando Job Glue"

if aws glue get-job \
    --job-name "${GLUE_JOB_NAME}" \
    --region "${REGION}" 2>/dev/null; then
    
    print_info "Deletando job Glue ${GLUE_JOB_NAME}..."
    aws glue delete-job \
        --job-name "${GLUE_JOB_NAME}" \
        --region "${REGION}"
    
    print_info "Job Glue deletado"
else
    print_warning "Job Glue ${GLUE_JOB_NAME} não encontrado"
fi

# ============================================================================
# 4. DELETAR TABELAS E DATABASE DO GLUE CATALOG
# ============================================================================

print_step "Etapa 4/5: Deletando Database e Tabelas do Glue Catalog"

if aws glue get-database \
    --name "${GLUE_DATABASE}" \
    --region "${REGION}" 2>/dev/null; then
    
    # Listar todas as tabelas do database
    print_info "Listando tabelas do database ${GLUE_DATABASE}..."
    TABLES=$(aws glue get-tables \
        --database-name "${GLUE_DATABASE}" \
        --region "${REGION}" \
        --query 'TableList[].Name' \
        --output text)
    
    if [ ! -z "$TABLES" ]; then
        print_info "Deletando tabelas..."
        for TABLE in $TABLES; do
            print_info "  - Deletando tabela: ${TABLE}"
            aws glue delete-table \
                --database-name "${GLUE_DATABASE}" \
                --name "${TABLE}" \
                --region "${REGION}" 2>/dev/null || true
        done
        print_info "Todas as tabelas deletadas"
    else
        print_warning "Nenhuma tabela encontrada no database"
    fi
    
    # Deletar o database
    print_info "Deletando database ${GLUE_DATABASE}..."
    aws glue delete-database \
        --name "${GLUE_DATABASE}" \
        --region "${REGION}"
    
    print_info "Database deletado"
else
    print_warning "Database ${GLUE_DATABASE} não encontrado"
fi

# ============================================================================
# 5. DELETAR BUCKET S3 E TODO SEU CONTEÚDO
# ============================================================================

print_step "Etapa 5/5: Deletando Bucket S3 e todo seu conteúdo"

if aws s3 ls "s3://${BUCKET_NAME}" 2>/dev/null; then
    print_warning "Deletando TODOS os arquivos do bucket ${BUCKET_NAME}..."
    print_warning "Esta operação pode levar alguns minutos dependendo da quantidade de dados..."
    
    # Deletar todas as versões e delete markers (se versionamento estiver ativo)
    aws s3api delete-objects \
        --bucket "${BUCKET_NAME}" \
        --delete "$(aws s3api list-object-versions \
            --bucket "${BUCKET_NAME}" \
            --region "${REGION}" \
            --output=json \
            --query='{Objects: Versions[].{Key:Key,VersionId:VersionId}}')" \
        --region "${REGION}" 2>/dev/null || true
    
    aws s3api delete-objects \
        --bucket "${BUCKET_NAME}" \
        --delete "$(aws s3api list-object-versions \
            --bucket "${BUCKET_NAME}" \
            --region "${REGION}" \
            --output=json \
            --query='{Objects: DeleteMarkers[].{Key:Key,VersionId:VersionId}}')" \
        --region "${REGION}" 2>/dev/null || true
    
    # Remover todos os objetos
    aws s3 rm "s3://${BUCKET_NAME}" --recursive --region "${REGION}"
    
    print_info "Todos os arquivos deletados"
    
    # Deletar o bucket
    print_info "Deletando bucket ${BUCKET_NAME}..."
    aws s3 rb "s3://${BUCKET_NAME}" --region "${REGION}"
    
    print_info "Bucket deletado"
else
    print_warning "Bucket ${BUCKET_NAME} não encontrado"
fi

# ============================================================================
# 6. LIMPAR ARQUIVOS LOCAIS
# ============================================================================

print_info "Limpando arquivos de configuração local..."

if [ -f ".env.aws" ]; then
    rm .env.aws
    print_info "Arquivo .env.aws removido"
fi

# ============================================================================
# RESUMO FINAL
# ============================================================================

echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║         CLEANUP CONCLUÍDO COM SUCESSO! ✓                       ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""
print_info "Recursos removidos:"
echo "  ✓ Função Lambda: ${LAMBDA_FUNCTION_NAME}"
echo "  ✓ Job Glue: ${GLUE_JOB_NAME}"
echo "  ✓ Database Glue: ${GLUE_DATABASE} (e todas as tabelas)"
echo "  ✓ Bucket S3: ${BUCKET_NAME} (e todo o conteúdo)"
echo "  ✓ Triggers e permissões removidos"
echo "  ✓ Arquivos de configuração local limpos"
echo ""
print_info "Ambiente AWS completamente limpo!"
echo ""
print_warning "Nota: Se você executar o setup.sh novamente, uma nova infraestrutura será criada."
echo ""
