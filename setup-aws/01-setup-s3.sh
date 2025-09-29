#!/bin/bash

# Tech Challenge Bovespa - Setup S3
# Script para criar e configurar bucket S3 conforme roteiro original

echo "🪣 Configurando bucket S3..."

# Carregar configurações
source ./config.env

# Verificar se as variáveis estão definidas
if [[ -z "$BUCKET_NAME" || -z "$AWS_REGION" ]]; then
    echo "❌ Erro: Variáveis não definidas. Verifique config.env"
    exit 1
fi

echo "📋 Configurações:"
echo "  Bucket: $BUCKET_NAME"
echo "  Região: $AWS_REGION"

# 1. Criar bucket S3
echo "📦 Criando bucket S3..."
if [[ "$AWS_REGION" == "us-east-1" ]]; then
    aws s3 mb "s3://${BUCKET_NAME}"
else
    aws s3 mb "s3://${BUCKET_NAME}" --region "$AWS_REGION"
fi

if [ $? -eq 0 ]; then
    echo "✅ Bucket criado: s3://${BUCKET_NAME}"
else
    echo "❌ Erro ao criar bucket"
    exit 1
fi

# 2. Configurar versionamento
echo "🔄 Habilitando versionamento..."
aws s3api put-bucket-versioning \
    --bucket "$BUCKET_NAME" \
    --versioning-configuration Status=Enabled

# 3. Bloquear acesso público
echo "🔒 Configurando segurança..."
aws s3api put-public-access-block \
    --bucket "$BUCKET_NAME" \
    --public-access-block-configuration \
    "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"

# 4. Criar estrutura de pastas (prefixos)
echo "📁 Criando estrutura de pastas..."
echo "Pasta raw/" | aws s3 cp - "s3://${BUCKET_NAME}/raw/.keep"
echo "Pasta refined/" | aws s3 cp - "s3://${BUCKET_NAME}/refined/.keep"

# 5. Configurar notificações S3 (será feito depois da Lambda)
echo "⚠️  Notificação: Configure trigger S3->Lambda após criar a função Lambda"

# Verificar criação
echo "🔍 Verificando bucket..."
aws s3 ls "s3://${BUCKET_NAME}/"

if [ $? -eq 0 ]; then
    echo "✅ Bucket S3 configurado com sucesso!"
    echo "📍 Nome do bucket: ${BUCKET_NAME}"
    echo ""
    echo "📋 Próximos passos:"
    echo "   1. Execute: ./02-setup-iam.sh"
    echo "   2. Anote o nome do bucket para usar na extração"
else
    echo "❌ Erro na verificação do bucket"
    exit 1
fi