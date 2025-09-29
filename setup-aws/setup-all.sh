#!/bin/bash

# Tech Challenge Bovespa - Setup Completo
# Script para executar todos os passos de configuração AWS

echo "🚀 Tech Challenge Bovespa - Setup Completo"
echo "==========================================="
echo ""

# Verificar se arquivo de configuração existe
if [ ! -f "config.env" ]; then
    echo "❌ Arquivo config.env não encontrado!"
    echo "📋 Criando a partir do exemplo..."
    cp config.env.example config.env
    echo ""
    echo "⚠️  IMPORTANTE: Edite o arquivo config.env antes de continuar:"
    echo "   1. Altere BUCKET_SUFFIX para seu nome"
    echo "   2. Verifique outras configurações se necessário"
    echo "   3. Execute novamente: ./setup-all.sh"
    exit 1
fi

# Carregar configurações
source ./config.env

echo "📋 Configurações carregadas:"
echo "  Projeto: $PROJECT_NAME"
echo "  Ambiente: $ENVIRONMENT"
echo "  Região: $AWS_REGION"
echo "  Bucket: $BUCKET_NAME"
echo ""

# Verificar AWS CLI
echo "🔍 Verificando pré-requisitos..."
aws --version > /dev/null 2>&1
if [ $? -ne 0 ]; then
    echo "❌ AWS CLI não encontrado. Instale e configure antes de continuar."
    exit 1
fi

# Verificar credenciais
aws sts get-caller-identity > /dev/null 2>&1
if [ $? -ne 0 ]; then
    echo "❌ Credenciais AWS não configuradas. Execute 'aws configure' primeiro."
    exit 1
fi

echo "✅ Pré-requisitos verificados"
echo ""

# Tornar scripts executáveis
chmod +x *.sh

# Executar configurações em sequência
echo "🎯 Iniciando configuração do pipeline..."
echo ""

# 1. S3
echo "=== PASSO 1/5: Configurar S3 ==="
./01-setup-s3.sh
if [ $? -ne 0 ]; then
    echo "❌ Falha na configuração do S3"
    exit 1
fi
echo ""

# 2. IAM
echo "=== PASSO 2/5: Configurar IAM ==="
./02-setup-iam.sh
if [ $? -ne 0 ]; then
    echo "❌ Falha na configuração do IAM"
    exit 1
fi
echo ""

# 3. Lambda
echo "=== PASSO 3/5: Configurar Lambda ==="
./03-setup-lambda.sh
if [ $? -ne 0 ]; then
    echo "❌ Falha na configuração da Lambda"
    exit 1
fi
echo ""

# 4. Glue
echo "=== PASSO 4/5: Configurar Glue ==="
./04-setup-glue.sh
if [ $? -ne 0 ]; then
    echo "❌ Falha na configuração do Glue"
    exit 1
fi
echo ""

# 5. Athena
echo "=== PASSO 5/5: Configurar Athena ==="
./05-setup-athena.sh
if [ $? -ne 0 ]; then
    echo "❌ Falha na configuração do Athena"
    exit 1
fi
echo ""

# Resumo final
echo "🎉 CONFIGURAÇÃO COMPLETA!"
echo "========================"
echo ""
echo "✅ Recursos criados com sucesso:"
echo "   📦 S3 Bucket: $BUCKET_NAME"
echo "   ⚡ Lambda: $LAMBDA_FUNCTION_NAME"
echo "   ⚙️  Glue Job: $GLUE_JOB_NAME"
echo "   🗄️ Database: $GLUE_DATABASE_NAME"
echo "   🔍 Athena Workgroup: $ATHENA_WORKGROUP_NAME"
echo ""
echo "📋 Próximos passos:"
echo "   1. 📊 Testar extração de dados:"
echo "      cd ../fase1-extracao"
echo "      pip install -r requirements.txt"
echo "      python extractor.py --bucket $BUCKET_NAME"
echo ""
echo "   2. 🔍 Monitorar pipeline:"
echo "      - Lambda: aws logs tail /aws/lambda/$LAMBDA_FUNCTION_NAME --follow"
echo "      - Glue: aws glue get-job-runs --job-name $GLUE_JOB_NAME"
echo ""
echo "   3. 📈 Consultar dados (após processamento):"
echo "      - Acesse console Athena"
echo "      - Use workgroup: $ATHENA_WORKGROUP_NAME"
echo "      - Execute consultas em athena-queries/"
echo ""
echo "🎯 Pipeline configurado seguindo exatamente o roteiro do Tech Challenge!"