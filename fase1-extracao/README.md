# Fase 1: Extração e Ingestão dos Dados

## Visão Geral
Esta fase implementa a extração de dados da B3 usando a biblioteca `yfinance` e o armazenamento dos dados brutos no S3 em formato Parquet particionado.

## Componentes

### 1. extractor.py
Script principal que:
- Extrai dados dos ativos PETR4.SA, VALE3.SA e ^BVSP
- Converte para formato Parquet
- Salva no S3 com particionamento por data
- Adiciona metadados de extração

### 2. Estrutura de Particionamento
```
s3://bucket/raw/ano=YYYY/mes=MM/dia=DD/ticker_YYYY-MM-DD.parquet
```

## Instalação

```bash
cd fase1-extracao
pip install -r requirements.txt
```

## Configuração

### Variáveis de Ambiente
```bash
export AWS_ACCESS_KEY_ID=your_access_key
export AWS_SECRET_ACCESS_KEY=your_secret_key
export AWS_DEFAULT_REGION=us-east-1
```

## Uso

### Extração dos dados do dia atual
```bash
python extractor.py --bucket tech-challenge-bovespa-seu-nome
```

### Extração de data específica
```bash
python extractor.py --bucket tech-challenge-bovespa-seu-nome --date 2025-09-23
```

### Extração com região específica
```bash
python extractor.py --bucket tech-challenge-bovespa-seu-nome --region us-east-1
```

## Funcionamento

1. **Inicialização**: Configura cliente S3 e lista de ativos
2. **Extração**: Para cada ativo, baixa dados históricos via yfinance
3. **Processamento**: Adiciona metadados e prepara para particionamento
4. **Armazenamento**: Salva no S3 em formato Parquet particionado

## Transformações Aplicadas

- Adição de coluna `ticker` para identificação do ativo
- Adição de `data_extracao` para rastreabilidade
- Criação de colunas de particionamento (`ano`, `mes`, `dia`)
- Renomeação inicial de colunas para português

## Logs e Monitoramento

O script gera logs detalhados incluindo:
- Número de registros extraídos por ativo
- Tempo de execução
- Arquivos salvos no S3
- Erros e warnings

## Próximos Passos

Após a execução bem-sucedida:
1. Os dados estarão disponíveis no S3 na camada `raw/`
2. O upload acionará automaticamente a função Lambda (Fase 2)
3. A Lambda iniciará o job do Glue para processamento (Fase 3)
