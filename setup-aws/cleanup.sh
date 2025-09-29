#!/bin/bash

# Tech Challenge Bovespa - Limpeza de Recursos
# Script para remover todos os recursos AWS criados

echo "🧹 Tech Challenge Bovespa - Limpeza de Recursos"
echo "==============================================="
echo ""
echo "⚠️  ATENÇÃO: Este script irá REMOVER todos os recursos AWS criados!"
echo "   - Buckets S3 e todos os dados"
echo "   - Função Lambda"
echo "   - Job Glue e database"
echo "   - Workgroup Athena"
echo "   - Roles e policies IAM"
echo ""

read -p "Tem certeza que deseja continuar? (digite 'sim' para confirmar): " confirmacao

if [ "$confirmacao" != "sim" ]; then
    echo "❌ Operação cancelada"
    exit 0
fi

# Carregar configurações
if [ ! -f "config.env" ]; then
    echo "❌ Arquivo config.env não encontrado!"
    exit 1
fi

source ./config.env

echo ""
echo "🗑️ Iniciando limpeza dos recursos..."
echo ""

# 1. Remover notificação S3
echo "📢 Removendo notificação S3..."
aws s3api put-bucket-notification-configuration \
    --bucket "$BUCKET_NAME" \
    --notification-configuration '{}' 2>/dev/null || true

# 2. Esvaziar e remover buckets S3
echo "🪣 Removendo buckets S3..."
aws s3 rm "s3://${BUCKET_NAME}" --recursive 2>/dev/null || true
aws s3 rb "s3://${BUCKET_NAME}" 2>/dev/null || true

aws s3 rm "s3://${BUCKET_NAME}-scripts" --recursive 2>/dev/null || true
aws s3 rb "s3://${BUCKET_NAME}-scripts" 2>/dev/null || true

aws s3 rm "s3://${BUCKET_NAME}-athena-results" --recursive 2>/dev/null || true
aws s3 rb "s3://${BUCKET_NAME}-athena-results" 2>/dev/null || true

# 3. Remover função Lambda
echo "⚡ Removendo função Lambda..."
aws lambda delete-function --function-name "$LAMBDA_FUNCTION_NAME" 2>/dev/null || true

# 4. Remover job Glue
echo "⚙️ Removendo job Glue..."
aws glue delete-job --job-name "$GLUE_JOB_NAME" 2>/dev/null || true

# 5. Remover database Glue (opcional - pode conter outras tabelas)
read -p "Remover database Glue '$GLUE_DATABASE_NAME'? (s/n): " remove_db
if [ "$remove_db" = "s" ]; then
    echo "🗄️ Removendo database Glue..."
    aws glue delete-database --name "$GLUE_DATABASE_NAME" 2>/dev/null || true
fi

# 6. Remover workgroup Athena
echo "🔍 Removendo workgroup Athena..."
aws athena delete-work-group --work-group "$ATHENA_WORKGROUP_NAME" --recursive-delete-option 2>/dev/null || true

# 7. Remover roles IAM
echo "🔐 Removendo roles IAM..."

# Obter account ID
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Remover políticas anexadas e roles
echo "   Removendo role Glue..."
aws iam detach-role-policy --role-name "$GLUE_ROLE_NAME" --policy-arn "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole" 2>/dev/null || true
aws iam detach-role-policy --role-name "$GLUE_ROLE_NAME" --policy-arn "arn:aws:iam::${ACCOUNT_ID}:policy/${GLUE_ROLE_NAME}-policy" 2>/dev/null || true
aws iam delete-policy --policy-arn "arn:aws:iam::${ACCOUNT_ID}:policy/${GLUE_ROLE_NAME}-policy" 2>/dev/null || true
aws iam delete-role --role-name "$GLUE_ROLE_NAME" 2>/dev/null || true

echo "   Removendo role Lambda..."
aws iam detach-role-policy --role-name "$LAMBDA_ROLE_NAME" --policy-arn "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole" 2>/dev/null || true
aws iam detach-role-policy --role-name "$LAMBDA_ROLE_NAME" --policy-arn "arn:aws:iam::${ACCOUNT_ID}:policy/${LAMBDA_ROLE_NAME}-policy" 2>/dev/null || true
aws iam delete-policy --policy-arn "arn:aws:iam::${ACCOUNT_ID}:policy/${LAMBDA_ROLE_NAME}-policy" 2>/dev/null || true
aws iam delete-role --role-name "$LAMBDA_ROLE_NAME" 2>/dev/null || true

# 8. Remover arquivos temporários
echo "🧽 Limpando arquivos temporários..."
rm -f athena-queries/*.sql 2>/dev/null || true
rmdir athena-queries 2>/dev/null || true

echo ""
echo "✅ Limpeza concluída!"
echo ""
echo "📋 Recursos removidos:"
echo "   - Buckets S3 e dados"
echo "   - Função Lambda"
echo "   - Job Glue"
echo "   - Workgroup Athena"
echo "   - Roles e policies IAM"
echo ""
echo "💡 Para recriar o pipeline, execute: ./setup-all.sh"