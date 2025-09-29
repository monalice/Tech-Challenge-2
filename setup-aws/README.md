# 🎯 Setup AWS - Implementação Básica (Roteiro Original)

## Visão Geral
Esta pasta contém os scripts e instruções para configurar a infraestrutura AWS **manualmente**, seguindo exatamente o roteiro original do Tech Challenge.

## 📋 Pré-requisitos

1. **Conta AWS** ativa
2. **AWS CLI** instalado e configurado
3. **Permissões AWS**:
   - S3 (criar buckets)
   - Lambda (criar funções)
   - Glue (criar jobs)
   - IAM (criar roles)
   - Athena (criar workgroups)

## 🚀 Passo a Passo (Roteiro Original)

### Fase 0: Configuração do Ambiente AWS

#### 1. Configurar Bucket S3
```bash
# Execute o script de configuração do S3
./01-setup-s3.sh
```

#### 2. Configurar Permissões IAM
```bash
# Execute o script de configuração das roles
./02-setup-iam.sh
```

#### 3. Criar Função Lambda
```bash
# Execute o script de configuração da Lambda
./03-setup-lambda.sh
```

#### 4. Criar Job Glue
```bash
# Execute o script de configuração do Glue
./04-setup-glue.sh
```

#### 5. Configurar Athena
```bash
# Execute o script de configuração do Athena
./05-setup-athena.sh
```

## 📁 Arquivos

- `01-setup-s3.sh` - Criação e configuração do bucket S3
- `02-setup-iam.sh` - Criação das roles e policies IAM
- `03-setup-lambda.sh` - Deploy da função Lambda
- `04-setup-glue.sh` - Criação do job ETL Glue
- `05-setup-athena.sh` - Configuração do Athena
- `setup-all.sh` - Script que executa tudo em sequência
- `cleanup.sh` - Remove todos os recursos (para limpeza)

## ⚙️ Configuração

Antes de executar, configure suas variáveis:

```bash
# Copie o arquivo de exemplo
cp config.env.example config.env

# Edite com suas configurações
nano config.env
```

### Exemplo config.env:
```bash
# Configurações do Projeto
PROJECT_NAME="tech-challenge-bovespa"
ENVIRONMENT="dev"
AWS_REGION="us-east-1"
BUCKET_SUFFIX="seu-nome"

# Configurações específicas
LAMBDA_FUNCTION_NAME="tech-challenge-bovespa-trigger"
GLUE_JOB_NAME="tech-challenge-bovespa-etl"
GLUE_DATABASE_NAME="tech_challenge_bovespa"
```

## 🎯 Execução Simples

### Opção 1: Executar tudo de uma vez
```bash
chmod +x setup-all.sh
./setup-all.sh
```

### Opção 2: Executar passo a passo
```bash
chmod +x *.sh
./01-setup-s3.sh
./02-setup-iam.sh
./03-setup-lambda.sh
./04-setup-glue.sh
./05-setup-athena.sh
```

## ✅ Validação

Após executar os scripts, valide se tudo funcionou:

```bash
# Verificar bucket S3
aws s3 ls | grep tech-challenge-bovespa

# Verificar função Lambda
aws lambda list-functions --query 'Functions[?contains(FunctionName, `tech-challenge`)]'

# Verificar job Glue
aws glue get-jobs --query 'Jobs[?contains(Name, `tech-challenge`)]'
```

## 🧹 Limpeza

Para remover todos os recursos criados:

```bash
./cleanup.sh
```
