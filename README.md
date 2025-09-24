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
├── iac-terraform/             # Infraestrutura como código
└── docs/                      # Documentação adicional
```

## Fases de Implementação

### Fase 0: Planejamento e Configuração do Ambiente AWS
- ✅ Desenho da arquitetura
- ⏳ Configuração do bucket S3
- ⏳ Configuração de permissões IAM

### Fase 1: Extração e Ingestão dos Dados Brutos
- ⏳ Script de extração usando yfinance
- ⏳ Salvamento em formato Parquet particionado

### Fase 2: Gatilho com AWS Lambda
- ⏳ Função Lambda para processar eventos S3
- ⏳ Configuração de triggers

### Fase 3: Transformação e Catalogação com AWS Glue
- ⏳ Job ETL com transformações obrigatórias
- ⏳ Catalogação automática de dados

### Fase 4: Consulta e Análise com AWS Athena
- ⏳ Configuração de consultas SQL
- ⏳ Validação do pipeline

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

1. Configure suas credenciais AWS
2. Execute o Terraform para provisionar a infraestrutura
3. Execute o script de extração de dados
4. Monitore o pipeline através do CloudWatch

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