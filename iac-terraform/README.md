# Infraestrutura como Código - Terraform

## Visão Geral
Este diretório contém a infraestrutura completa do pipeline Bovespa definida como código usando Terraform.

## Recursos Provisionados

### Armazenamento (S3)
- **Data Lake Bucket**: Armazenamento principal (raw/ e refined/)
- **Athena Results Bucket**: Resultados de consultas do Athena
- **Glue Scripts Bucket**: Scripts ETL do Glue

### Computação
- **Lambda Function**: Função de trigger para eventos S3
- **Glue Job**: Job ETL para processamento de dados

### Segurança (IAM)
- **Glue Service Role**: Permissões para executar jobs ETL
- **Lambda Execution Role**: Permissões para executar função Lambda

### Analytics
- **Glue Database**: Catálogo de dados
- **Athena Workgroup**: Ambiente de consultas SQL

### Monitoramento
- **CloudWatch Log Groups**: Logs para Lambda e Glue
- **Métricas**: Monitoramento de performance

## Estrutura de Arquivos

```
iac-terraform/
├── main.tf                    # Configuração principal
├── terraform.tfvars.example  # Exemplo de variáveis
└── README.md                  # Esta documentação
```

## Pré-requisitos

### 1. Instalar Terraform
```bash
# Windows (Chocolatey)
choco install terraform

# macOS (Homebrew)
brew install terraform

# Linux
# Baixar de https://terraform.io/downloads
```

### 2. Configurar AWS CLI
```bash
aws configure
# Inserir: Access Key, Secret Key, Region, Output format
```

### 3. Verificar Permissões
Certifique-se de ter permissões para:
- S3 (criar buckets, objetos)
- Lambda (criar funções)
- Glue (criar jobs, database)
- IAM (criar roles, policies)
- CloudWatch (criar log groups)
- Athena (criar workgroups)

## Deploy

### 1. Clonar e Configurar
```bash
cd iac-terraform
cp terraform.tfvars.example terraform.tfvars
# Editar terraform.tfvars com suas configurações
```

### 2. Inicializar Terraform
```bash
terraform init
```

### 3. Planejar Deploy
```bash
terraform plan
```

### 4. Aplicar Infraestrutura
```bash
terraform apply
# Digite 'yes' para confirmar
```

## Configuração de Variáveis

### terraform.tfvars
```hcl
aws_region    = "us-east-1"
project_name  = "tech-challenge-bovespa"
environment   = "dev"
project_owner = "seu-nome"
```

### Variáveis Disponíveis

| Variável | Descrição | Padrão | Obrigatória |
|----------|-----------|---------|-------------|
| aws_region | Região AWS | us-east-1 | Não |
| project_name | Nome do projeto | tech-challenge-bovespa | Não |
| environment | Ambiente | dev | Não |
| project_owner | Proprietário | tech-challenge | Não |

## Recursos Criados

### Buckets S3
- `{project_name}-{env}-{random}/`: Data Lake principal
- `{project_name}-{env}-{random}-athena-results/`: Resultados Athena
- `{project_name}-{env}-{random}-glue-scripts/`: Scripts Glue

### Funções Lambda
- `{project_name}-trigger`: Processa eventos S3

### Jobs Glue
- `{project_name}-etl`: Processamento ETL

### Recursos IAM
- `{project_name}-glue-service-role`: Role do Glue
- `{project_name}-lambda-execution-role`: Role da Lambda
- Policies correspondentes com permissões mínimas

## Outputs

Após o deploy, você receberá:

```bash
data_lake_bucket_name = "tech-challenge-bovespa-dev-a1b2c3d4"
athena_results_bucket_name = "tech-challenge-bovespa-dev-a1b2c3d4-athena-results"
glue_scripts_bucket_name = "tech-challenge-bovespa-dev-a1b2c3d4-glue-scripts"
glue_job_name = "tech-challenge-bovespa-etl"
lambda_function_name = "tech-challenge-bovespa-trigger"
athena_workgroup_name = "tech-challenge-bovespa-workgroup"
glue_database_name = "tech_challenge_bovespa"
```

## Segurança

### Princípios Implementados
- **Least Privilege**: Permissões mínimas necessárias
- **Encryption**: Criptografia em repouso (S3, Athena)
- **Network Isolation**: Buckets privados por padrão
- **Audit Trail**: CloudWatch logs para todas as operações

### Controles de Acesso
- Buckets S3 com public access bloqueado
- IAM roles com políticas específicas
- Resource-based permissions

## Monitoramento

### CloudWatch Logs
- `/aws/lambda/{function-name}`: Logs da Lambda
- `/aws-glue/jobs/logs-v2`: Logs do Glue

### Métricas
- Performance das funções Lambda
- Execução dos jobs Glue
- Consultas do Athena

## Custos Estimados

### Componentes Principais
- **S3**: ~$0.023/GB/mês
- **Lambda**: ~$0.20/1M requests
- **Glue**: ~$0.44/DPU-hour
- **Athena**: ~$5/TB escaneado

### Otimizações
- Particionamento reduz custos do Athena
- Lifecycle policies para S3
- Dimensionamento adequado do Glue

## Troubleshooting

### Problemas Comuns

#### 1. Erro de Permissões
```bash
Error: AccessDenied: User is not authorized
```
**Solução**: Verificar permissões IAM do usuário

#### 2. Nome de Bucket Já Existe
```bash
Error: BucketAlreadyExists
```
**Solução**: Bucket names são globalmente únicos, aguardar ou alterar random_id

#### 3. Limite de Recursos
```bash
Error: LimitExceeded
```
**Solução**: Verificar limites da conta AWS

## Manutenção

### Atualizações
```bash
# Verificar mudanças
terraform plan

# Aplicar atualizações
terraform apply
```

### Backup de Estado
```bash
# Backup manual do estado
cp terraform.tfstate terraform.tfstate.backup
```

### Destruição (Cuidado!)
```bash
# Remover toda infraestrutura
terraform destroy
# ATENÇÃO: Isso remove TODOS os recursos!
```

## Próximos Passos

1. **Deploy da Infraestrutura**: Execute `terraform apply`
2. **Teste de Conectividade**: Verifique se recursos foram criados
3. **Execute Pipeline**: Teste com dados da Fase 1
4. **Monitore Execução**: Verifique logs e métricas
5. **Validação**: Confirme funcionamento end-to-end

## Scripts Auxiliares

### Validação Pós-Deploy
```bash
# Verificar buckets
aws s3 ls | grep tech-challenge-bovespa

# Verificar função Lambda
aws lambda list-functions --query 'Functions[?contains(FunctionName, `tech-challenge`)]'

# Verificar job Glue
aws glue get-jobs --query 'Jobs[?contains(Name, `tech-challenge`)]'
```

### Limpeza de Recursos
```bash
# Esvaziar buckets antes de destroy
aws s3 rm s3://bucket-name --recursive

# Aplicar destroy
terraform destroy
```
