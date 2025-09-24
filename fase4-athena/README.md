# Fase 4: Consulta e Análise com AWS Athena

## Visão Geral
Esta fase implementa consultas SQL no AWS Athena para validar o pipeline ETL e demonstrar que os dados estão prontos para consumo analítico.

## Componentes

### 1. consultas_athena.sql
Arquivo com consultas SQL organizadas em categorias:

#### Consultas de Validação
- Verificação de catalogação
- Estrutura das tabelas
- Contagem de registros

#### Validação das Transformações
- **Transformação A**: Verificação do volume médio mensal
- **Transformação B**: Validação das colunas renomeadas
- **Transformação C**: Conferência da média móvel de 7 dias

#### Consultas de Performance
- Utilização eficiente de partições
- Otimização por ticker e data
- Comparações entre ativos

#### Análises de Negócio
- Cálculo de volatilidade
- Comparação de performance
- Identificação de anomalias de volume

#### Qualidade de Dados
- Verificação de integridade
- Consistência temporal
- Métricas de monitoramento

## Configuração do Athena

### 1. Bucket de Resultados
Configure um bucket S3 para armazenar resultados das consultas:
```
s3://tech-challenge-bovespa-athena-results/
```

### 2. Workgroup
Crie um workgroup dedicado com configurações otimizadas:
- **Nome**: tech-challenge-bovespa
- **Localização dos resultados**: Bucket configurado acima
- **Criptografia**: Habilitada
- **Controle de custos**: Limites por consulta

### 3. Database
O database `tech_challenge_bovespa` é criado automaticamente pelo job Glue.

## Consultas Principais

### Validação Básica
```sql
-- Verificar se dados foram catalogados
SHOW DATABASES;

-- Listar tabelas do projeto
SHOW TABLES IN tech_challenge_bovespa;

-- Visualizar estrutura
DESCRIBE tech_challenge_bovespa.dados_refinados_petr4_sa;
```

### Consulta Otimizada com Partições
```sql
-- Busca eficiente por ticker e data específicos
SELECT 
    ticker, data, Abertura, Fechamento, Volume
FROM tech_challenge_bovespa.dados_refinados_petr4_sa
WHERE ticker = 'PETR4.SA' 
  AND data_particao = '2025-09-23';
```

### Análise Multi-Ativo
```sql
-- Comparar performance entre PETR4 e VALE3
SELECT 
    p.data,
    p.Fechamento as petr4_fechamento,
    v.Fechamento as vale3_fechamento,
    p.media_movel_7_dias_fechamento
FROM tech_challenge_bovespa.dados_refinados_petr4_sa p
JOIN tech_challenge_bovespa.dados_refinados_vale3_sa v
    ON p.data_particao = v.data_particao
WHERE p.data_particao >= '2025-09-01'
ORDER BY p.data DESC;
```

## Validação das Transformações

### Transformação A - Volume Médio Mensal
Verifica se o agrupamento e cálculo da média está correto:
```sql
SELECT 
    ticker,
    EXTRACT(YEAR FROM data) as ano,
    EXTRACT(MONTH FROM data) as mes,
    volume_medio_mensal,
    dias_negociacao
FROM tech_challenge_bovespa.dados_refinados_petr4_sa
GROUP BY ticker, ano, mes, volume_medio_mensal, dias_negociacao;
```

### Transformação B - Colunas Renomeadas  
Confirma que as colunas foram renomeadas corretamente:
```sql
SELECT 
    Abertura,      -- Era "abertura"
    Maxima_Dia,    -- Era "maxima"
    Fechamento,
    Volume
FROM tech_challenge_bovespa.dados_refinados_petr4_sa
LIMIT 5;
```

### Transformação C - Média Móvel
Valida o cálculo da média móvel de 7 dias:
```sql
SELECT 
    data,
    Fechamento,
    media_movel_7_dias_fechamento,
    algoritmo_media_movel
FROM tech_challenge_bovespa.dados_refinados_petr4_sa
ORDER BY data DESC
LIMIT 10;
```

## Análises de Negócio

### Volatilidade Diária
```sql
SELECT 
    ticker,
    data,
    ((Maxima_Dia - Minima_Dia) / Minima_Dia) * 100 as volatilidade_pct
FROM tech_challenge_bovespa.dados_refinados_petr4_sa
ORDER BY volatilidade_pct DESC
LIMIT 20;
```

### Anomalias de Volume
```sql
SELECT 
    ticker,
    data, 
    Volume,
    volume_medio_mensal,
    (Volume / volume_medio_mensal) as ratio_volume
FROM tech_challenge_bovespa.dados_refinados_petr4_sa
WHERE Volume > (volume_medio_mensal * 2)
ORDER BY ratio_volume DESC;
```

## Performance e Otimização

### Uso Eficiente de Partições
- **Sempre** inclua filtros por `ticker` e `data_particao`
- Evite `SELECT *` em consultas grandes
- Use `LIMIT` para testes exploratórios

### Exemplos de Consultas Otimizadas
```sql
-- ✅ Otimizada - usa partições
SELECT data, Fechamento 
FROM dados_refinados_petr4_sa
WHERE data_particao BETWEEN '2025-09-01' AND '2025-09-30';

-- ❌ Não otimizada - não usa partições  
SELECT data, Fechamento 
FROM dados_refinados_petr4_sa
WHERE data BETWEEN DATE '2025-09-01' AND DATE '2025-09-30';
```

## Monitoramento e Qualidade

### Métricas de Qualidade
```sql
-- Verificar dados nulos
SELECT 
    COUNT(*) as total,
    SUM(CASE WHEN Fechamento IS NULL THEN 1 ELSE 0 END) as fechamento_nulos,
    SUM(CASE WHEN Volume IS NULL THEN 1 ELSE 0 END) as volume_nulos
FROM tech_challenge_bovespa.dados_refinados_petr4_sa;
```

### Última Atualização
```sql
-- Verificar frescor dos dados
SELECT 
    MAX(data_processamento) as ultima_atualizacao,
    MAX(data) as ultima_data_dados,
    COUNT(*) as total_registros
FROM tech_challenge_bovespa.dados_refinados_petr4_sa;
```

## Custos e Limitações

### Estimativa de Custos
- **Por consulta**: ~$5-10 por TB de dados escaneados
- **Otimização**: Partições reduzem custo em 90%+
- **Workgroup**: Configure limites para controle

### Limitações
- Máximo 30 minutos por consulta
- Limite de 100 consultas simultâneas por conta
- Resultados expiraram após período configurado

## Próximos Passos

### Validação Completa
1. Execute consultas de validação básica
2. Confirme transformações aplicadas
3. Teste consultas com partições
4. Valide qualidade dos dados

### Casos de Uso Avançados
1. **Dashboard**: Conectar ao QuickSight
2. **Alertas**: Integrar com CloudWatch
3. **Automação**: Scheduled queries via EventBridge
4. **Machine Learning**: Exportar para SageMaker

## Troubleshooting

### Problemas Comuns
1. **Tabela não encontrada**: Verificar catalogação do Glue
2. **Partições não carregam**: Executar `MSCK REPAIR TABLE`
3. **Consulta lenta**: Verificar uso de partições
4. **Erro de sintaxe**: Validar SQL no editor

### Comandos de Manutenção
```sql
-- Reparar partições
MSCK REPAIR TABLE tech_challenge_bovespa.dados_refinados_petr4_sa;

-- Listar partições
SHOW PARTITIONS tech_challenge_bovespa.dados_refinados_petr4_sa;

-- Estatísticas da tabela
SHOW TABLE EXTENDED LIKE 'dados_refinados_petr4_sa';
```
