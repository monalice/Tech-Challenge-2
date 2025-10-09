# Tech Challenge: Pipeline Batch Bovespa

## Visão Geral
Este projeto implementa um pipeline de dados batch para processamento de dados da Bovespa utilizando serviços da AWS. O pipeline segue a arquitetura de Data Lake com as camadas raw e refined, garantindo governança de dados e escalabilidade.

## Arquitetura

```
┌─────────────────┐    ┌─────────────┐    ┌─────────────┐    ┌─────────────┐
│   YFinance API  │───▶│   Script    │───▶│  S3 Raw     │───▶│   Lambda    │
│   (Dados B3)    │    │  Extração   │    │  (Parquet)  │    │  (Trigger)  │
└─────────────────┘    └─────────────┘    └─────────────┘    └─────────────┘
                                                                      │
┌─────────────────┐    ┌─────────────┐    ┌─────────────┐           │
│    Athena       │◀───│ Glue Data   │◀───│  AWS Glue   │◀──────────┘
│   (Consultas)   │    │  Catalog    │    │ ETL Job     │
└─────────────────┘    └─────────────┘    └─────────────┘
                                                  │
                                          ┌─────────────┐
                                          │ S3 Refined  │
                                          │ (Parquet)   │
                                          └─────────────┘
```

## Estrutura do Projeto

```
├── fase0-planejamento/         # Arquitetura e documentação
├── fase1-extracao/            # Scripts de extração de dados
├── fase2-lambda/              # Função Lambda para triggers
├── fase3-glue/                # Jobs ETL do AWS Glue
├── fase4-athena/              # Consultas SQL do Athena
├── setup-aws/                 # Configuração AWS (roteiro original)
└── docs/                      # Documentação adicional
```

## Fases de Implementação

### ✅ Fase 0: Planejamento e Configuração do Ambiente AWS

- ✅ Desenho da arquitetura
- ✅ Scripts de configuração AWS (setup-aws/)

### ✅ Fase 1: Extração e Ingestão dos Dados Brutos

- ✅ Script de extração usando yfinance
- ✅ Salvamento em formato Parquet particionado

### ✅ Fase 2: Gatilho com AWS Lambda

- ✅ Função Lambda para processar eventos S3
- ✅ Configuração de triggers automatizada

### ✅ Fase 3: Transformação e Catalogação com AWS Glue

- ✅ Job ETL com transformações obrigatórias
- ✅ Catalogação automática de dados

### ✅ Fase 4: Consulta e Análise com AWS Athena

- ✅ Configuração de consultas SQL
- ✅ Validação do pipeline

## Requisitos Técnicos

### Python Dependencies

```bash
pip install yfinance pandas boto3 pyarrow awswrangler
```

### AWS Services Utilizados

- **S3**: Data Lake (raw e refined)
- **Lambda**: Orquestração e triggers
- **Glue**: ETL e catalogação
- **Athena**: Consultas SQL
- **IAM**: Gerenciamento de permissões

## Como Executar

### 🚀 Opção 1: Setup Automatizado (AWS Academy)

**Recomendado para ambientes AWS Academy!**

Utilize os scripts automatizados para configurar toda a infraestrutura:

```bash
# 1. Execute o setup para criar todos os recursos
./setup.sh

# 2. Execute a extração de dados
cd fase1-extracao
pip install -r requirements.txt
python b3_scraper_new.py --bucket tech-challenge-bovespa-SEU-SUFIXO --save-s3

# 3. Verifique os dados no Athena (AWS Console)

# 4. Ao finalizar, execute o cleanup
./cleanup.sh
```

📖 **Documentação completa dos scripts:**
- [SCRIPTS_README.md](SCRIPTS_README.md) - Guia completo de uso
- [WINDOWS_SETUP_GUIDE.md](WINDOWS_SETUP_GUIDE.md) - Instruções específicas para Windows

### 🎯 Opção 2: Setup Manual (Configuração Tradicional)

Siga exatamente o roteiro do Tech Challenge:

#### 1. Configure o Ambiente AWS

```bash
# Siga o passo-a-passo em setup-aws/
cd setup-aws
# Execute os scripts de configuração manual
```

#### 2. Execute a Extração

```bash
cd fase1-extracao
pip install -r requirements.txt
python b3_scraper_new.py --bucket seu-bucket-name --save-s3
```

#### 3. Monitore o Pipeline

- Lambda será acionada automaticamente
- Job Glue processará os dados
- Consulte via Athena

### 🚀 Implementação Avançada (Opcional)
Para deploy automatizado com Terraform:

```bash
cd extras-avancado/iac-terraform
# Siga instruções específicas do Terraform
```

## Transformações Implementadas

1. **Agrupamento**: Agregação mensal do volume médio negociado
2. **Renomeação**: Colunas Open→Abertura, High→Maxima_Dia
3. **Cálculo Temporal**: Média móvel de 7 dias dos preços de fechamento

## Ativos Monitorados

- PETR4.SA (Petrobras)
- VALE3.SA (Vale)
- ^BVSP (Ibovespa)

## Licença

MIT License