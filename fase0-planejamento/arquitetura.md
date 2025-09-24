# Fase 0: Planejamento e Configuração do Ambiente AWS

## Desenho da Arquitetura

### Fluxo de Dados

1. **Fonte de Dados**: API YFinance para dados da B3
2. **Extração**: Script Python local executa coleta
3. **Armazenamento Raw**: Dados salvos no S3 em formato Parquet particionado por data
4. **Trigger**: Upload no S3 aciona função Lambda
5. **Orquestração**: Lambda inicia Job do AWS Glue
6. **Transformação**: Job Glue processa dados e salva na camada refined
7. **Catalogação**: Glue cataloga dados no Data Catalog
8. **Consulta**: Dados consultados via AWS Athena

### Estrutura do Bucket S3

```
tech-challenge-bovespa-{nome}/
├── raw/
│   ├── ano=2025/
│   │   ├── mes=09/
│   │   │   ├── dia=23/
│   │   │   │   └── bovespa_data_20250923.parquet
│   │   │   └── dia=24/
│   │   └── mes=10/
│   └── ano=2026/
└── refined/
    ├── ticker=PETR4.SA/
    │   ├── data_particao=2025-09-23/
    │   │   └── refined_data.parquet
    │   └── data_particao=2025-09-24/
    ├── ticker=VALE3.SA/
    └── ticker=BVSP/
```

## Configuração de Permissões IAM

### Roles Necessárias

#### 1. GlueServiceRole
- **Propósito**: Executar jobs do Glue
- **Permissões**:
  - `s3:GetObject` em `arn:aws:s3:::tech-challenge-bovespa-*/raw/*`
  - `s3:PutObject` em `arn:aws:s3:::tech-challenge-bovespa-*/refined/*`
  - `glue:*` para operações do Data Catalog
  - `logs:CreateLogGroup`, `logs:CreateLogStream`, `logs:PutLogEvents`

#### 2. LambdaExecutionRole
- **Propósito**: Executar função Lambda e iniciar jobs Glue
- **Permissões**:
  - `glue:StartJobRun`
  - `logs:CreateLogGroup`, `logs:CreateLogStream`, `logs:PutLogEvents`
  - `s3:GetObject` para ler metadados do evento

### Políticas de Segurança

- Princípio do menor privilégio
- Acesso restrito por prefixos S3
- Logs de auditoria habilitados
- Criptografia em trânsito e em repouso

## Ativos da B3 Selecionados

| Código | Nome | Tipo |
|--------|------|------|
| PETR4.SA | Petrobras PN | Ação |
| VALE3.SA | Vale ON | Ação |
| ^BVSP | Ibovespa | Índice |

## Frequência de Execução

- **Extração**: Diária (após fechamento do mercado)
- **Processamento**: Automático via trigger
- **Retenção**: Raw (365 dias), Refined (permanente)

## Monitoramento

- CloudWatch Logs para todas as execuções
- CloudWatch Metrics para performance
- SNS para alertas de falhas
- CloudTrail para auditoria
