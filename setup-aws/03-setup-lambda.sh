#!/bin/bash

# Tech Challenge Bovespa - Setup Lambda
# Script para criar função Lambda conforme roteiro original

echo "⚡ Configurando função Lambda..."

# Carregar configurações
source ./config.env

echo "📋 Configurações:"
echo "  Função: $LAMBDA_FUNCTION_NAME"
echo "  Role: $LAMBDA_ROLE_NAME"
echo "  Bucket: $BUCKET_NAME"

# 1. Verificar se o código da Lambda existe
if [ ! -f "$LAMBDA_CODE_PATH" ]; then
    echo "❌ Erro: Código da Lambda não encontrado em $LAMBDA_CODE_PATH"
    exit 1
fi

# 2. Criar pacote de deployment
echo "📦 Criando pacote de deployment..."
cd "$(dirname "$LAMBDA_CODE_PATH")"
zip -r lambda-deployment.zip lambda_function.py
mv lambda-deployment.zip ../setup-aws/
cd - > /dev/null

# 3. Obter ARN da role da Lambda
echo "🔍 Obtendo ARN da role..."
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
LAMBDA_ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${LAMBDA_ROLE_NAME}"

echo "📍 Role ARN: $LAMBDA_ROLE_ARN"

# 4. Criar função Lambda
echo "⚡ Criando função Lambda..."
aws lambda create-function \
    --function-name "$LAMBDA_FUNCTION_NAME" \
    --runtime python3.9 \
    --role "$LAMBDA_ROLE_ARN" \
    --handler lambda_function.lambda_handler \
    --zip-file fileb://lambda-deployment.zip \
    --timeout 300 \
    --description "Tech Challenge Bovespa - Trigger S3 para Glue"

if [ $? -eq 0 ]; then
    echo "✅ Função Lambda criada: $LAMBDA_FUNCTION_NAME"
else
    echo "❌ Erro ao criar função Lambda"
    exit 1
fi

# 5. Configurar variável de ambiente
echo "⚙️ Configurando variáveis de ambiente..."
aws lambda update-function-configuration \
    --function-name "$LAMBDA_FUNCTION_NAME" \
    --environment Variables="{GLUE_JOB_NAME=${GLUE_JOB_NAME}}"

# 6. Adicionar permissão para S3 invocar a Lambda
echo "🔐 Configurando permissões S3..."
aws lambda add-permission \
    --function-name "$LAMBDA_FUNCTION_NAME" \
    --principal s3.amazonaws.com \
    --action lambda:InvokeFunction \
    --source-arn "arn:aws:s3:::${BUCKET_NAME}" \
    --statement-id s3-trigger-permission

# 7. Configurar notificação S3
echo "📢 Configurando notificação S3..."
cat > s3-notification.json << EOF
{
  "LambdaConfigurations": [
    {
      "Id": "bovespa-data-trigger",
      "LambdaFunctionArn": "arn:aws:lambda:${AWS_REGION}:${ACCOUNT_ID}:function:${LAMBDA_FUNCTION_NAME}",
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
    --bucket "$BUCKET_NAME" \
    --notification-configuration file://s3-notification.json

# 8. Verificar função criada
echo "🔍 Verificando função Lambda..."
aws lambda get-function --function-name "$LAMBDA_FUNCTION_NAME" --query 'Configuration.FunctionName'

if [ $? -eq 0 ]; then
    echo "✅ Função Lambda configurada com sucesso!"
    echo "📍 Função: ${LAMBDA_FUNCTION_NAME}"
    echo "📍 Trigger: s3://${BUCKET_NAME}/raw/*.parquet"
    echo ""
    echo "📋 Próximos passos:"
    echo "   1. Execute: ./04-setup-glue.sh"
else
    echo "❌ Erro na verificação da função Lambda"
    exit 1
fi

# Limpar arquivos temporários
rm -f lambda-deployment.zip s3-notification.json