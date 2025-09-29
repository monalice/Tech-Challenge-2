#!/bin/bash

# Tech Challenge Bovespa - Setup IAM
# Script para criar roles e policies IAM conforme roteiro original

echo "🔐 Configurando permissões IAM..."

# Carregar configurações
source ./config.env

echo "📋 Configurações:"
echo "  Glue Role: $GLUE_ROLE_NAME"
echo "  Lambda Role: $LAMBDA_ROLE_NAME"
echo "  Bucket: $BUCKET_NAME"

# 1. Criar política de confiança para o Glue
echo "📝 Criando política de confiança para Glue..."
cat > glue-trust-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "glue.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

# 2. Criar Role do Glue
echo "👤 Criando role do Glue..."
aws iam create-role \
    --role-name "$GLUE_ROLE_NAME" \
    --assume-role-policy-document file://glue-trust-policy.json

# 3. Criar política customizada para o Glue
echo "📋 Criando política customizada para Glue..."
cat > glue-custom-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::${BUCKET_NAME}",
        "arn:aws:s3:::${BUCKET_NAME}/raw/*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "s3:PutObject",
        "s3:DeleteObject"
      ],
      "Resource": [
        "arn:aws:s3:::${BUCKET_NAME}/refined/*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "glue:GetDatabase",
        "glue:CreateDatabase",
        "glue:GetTable",
        "glue:CreateTable",
        "glue:UpdateTable",
        "glue:DeleteTable",
        "glue:GetPartition",
        "glue:CreatePartition",
        "glue:UpdatePartition",
        "glue:DeletePartition",
        "glue:BatchCreatePartition",
        "glue:BatchDeletePartition"
      ],
      "Resource": [
        "arn:aws:glue:${AWS_REGION}:*:catalog",
        "arn:aws:glue:${AWS_REGION}:*:database/${GLUE_DATABASE_NAME}",
        "arn:aws:glue:${AWS_REGION}:*:table/${GLUE_DATABASE_NAME}/*"
      ]
    }
  ]
}
EOF

aws iam create-policy \
    --policy-name "${GLUE_ROLE_NAME}-policy" \
    --policy-document file://glue-custom-policy.json

# 4. Anexar políticas ao role do Glue
echo "🔗 Anexando políticas ao role do Glue..."
aws iam attach-role-policy \
    --role-name "$GLUE_ROLE_NAME" \
    --policy-arn "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
aws iam attach-role-policy \
    --role-name "$GLUE_ROLE_NAME" \
    --policy-arn "arn:aws:iam::${ACCOUNT_ID}:policy/${GLUE_ROLE_NAME}-policy"

# 5. Criar política de confiança para Lambda
echo "📝 Criando política de confiança para Lambda..."
cat > lambda-trust-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

# 6. Criar Role da Lambda
echo "👤 Criando role da Lambda..."
aws iam create-role \
    --role-name "$LAMBDA_ROLE_NAME" \
    --assume-role-policy-document file://lambda-trust-policy.json

# 7. Criar política customizada para Lambda
echo "📋 Criando política customizada para Lambda..."
cat > lambda-custom-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "glue:StartJobRun",
        "glue:GetJobRun",
        "glue:GetJob"
      ],
      "Resource": [
        "arn:aws:glue:${AWS_REGION}:*:job/${GLUE_JOB_NAME}"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:GetObjectMetadata"
      ],
      "Resource": [
        "arn:aws:s3:::${BUCKET_NAME}/raw/*"
      ]
    }
  ]
}
EOF

aws iam create-policy \
    --policy-name "${LAMBDA_ROLE_NAME}-policy" \
    --policy-document file://lambda-custom-policy.json

# 8. Anexar políticas ao role da Lambda
echo "🔗 Anexando políticas ao role da Lambda..."
aws iam attach-role-policy \
    --role-name "$LAMBDA_ROLE_NAME" \
    --policy-arn "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"

aws iam attach-role-policy \
    --role-name "$LAMBDA_ROLE_NAME" \
    --policy-arn "arn:aws:iam::${ACCOUNT_ID}:policy/${LAMBDA_ROLE_NAME}-policy"

# 9. Aguardar propagação das roles
echo "⏳ Aguardando propagação das roles (30s)..."
sleep 30

# 10. Verificar roles criadas
echo "🔍 Verificando roles criadas..."
aws iam get-role --role-name "$GLUE_ROLE_NAME" --query 'Role.RoleName'
aws iam get-role --role-name "$LAMBDA_ROLE_NAME" --query 'Role.RoleName'

echo "✅ Roles IAM configuradas com sucesso!"
echo "📍 Roles criadas:"
echo "   - Glue: ${GLUE_ROLE_NAME}"
echo "   - Lambda: ${LAMBDA_ROLE_NAME}"
echo ""
echo "📋 Próximos passos:"
echo "   1. Execute: ./03-setup-lambda.sh"

# Limpar arquivos temporários
rm -f glue-trust-policy.json glue-custom-policy.json
rm -f lambda-trust-policy.json lambda-custom-policy.json