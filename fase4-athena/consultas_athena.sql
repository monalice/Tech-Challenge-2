-- Tech Challenge: Pipeline Batch Bovespa
-- Fase 4: Consultas SQL do AWS Athena
-- 
-- Este arquivo contém consultas SQL para validar e analisar os dados
-- processados pelo pipeline ETL da Bovespa

-- =============================================================================
-- 1. CONSULTAS DE VALIDAÇÃO BÁSICA
-- =============================================================================

-- Verificar se os dados foram catalogados corretamente
SHOW DATABASES;

-- Listar tabelas do database
SHOW TABLES IN tech_challenge_bovespa;

-- Verificar estrutura das tabelas
DESCRIBE tech_challenge_bovespa.dados_refinados_petr4_sa;
DESCRIBE tech_challenge_bovespa.dados_refinados_vale3_sa;
DESCRIBE tech_challenge_bovespa.dados_refinados_indice_bvsp;

-- =============================================================================
-- 2. CONSULTAS EXPLORATÓRIAS
-- =============================================================================

-- Visualização geral dos dados - PETR4
SELECT 
    data,
    ticker,
    Abertura,
    Maxima_Dia,
    Minima_Dia,
    Fechamento,
    Volume,
    media_movel_7_dias_fechamento,
    volume_medio_mensal,
    data_particao
FROM tech_challenge_bovespa.dados_refinados_petr4_sa
ORDER BY data DESC
LIMIT 10;

-- Contagem de registros por ativo e período
SELECT 
    ticker,
    COUNT(*) as total_registros,
    MIN(data) as primeira_data,
    MAX(data) as ultima_data,
    COUNT(DISTINCT data_particao) as dias_distintos
FROM (
    SELECT ticker, data, data_particao FROM tech_challenge_bovespa.dados_refinados_petr4_sa
    UNION ALL
    SELECT ticker, data, data_particao FROM tech_challenge_bovespa.dados_refinados_vale3_sa
    UNION ALL  
    SELECT ticker, data, data_particao FROM tech_challenge_bovespa.dados_refinados_indice_bvsp
) dados_combinados
GROUP BY ticker;

-- =============================================================================
-- 3. CONSULTAS DE VALIDAÇÃO DAS TRANSFORMAÇÕES
-- =============================================================================

-- Verificar Transformação A: Volume médio mensal
SELECT 
    ticker,
    EXTRACT(YEAR FROM data) as ano,
    EXTRACT(MONTH FROM data) as mes,
    volume_medio_mensal,
    dias_negociacao,
    primeira_data_mes,
    ultima_data_mes,
    COUNT(*) as registros_mes
FROM tech_challenge_bovespa.dados_refinados_petr4_sa
WHERE data >= DATE '2025-09-01'
GROUP BY ticker, EXTRACT(YEAR FROM data), EXTRACT(MONTH FROM data), 
         volume_medio_mensal, dias_negociacao, primeira_data_mes, ultima_data_mes
ORDER BY ano, mes;

-- Verificar Transformação B: Colunas renomeadas
SELECT 
    'Abertura' as coluna_renomeada,
    AVG(Abertura) as valor_medio,
    COUNT(*) as total_registros
FROM tech_challenge_bovespa.dados_refinados_petr4_sa
WHERE Abertura IS NOT NULL

UNION ALL

SELECT 
    'Maxima_Dia' as coluna_renomeada,
    AVG(Maxima_Dia) as valor_medio,
    COUNT(*) as total_registros
FROM tech_challenge_bovespa.dados_refinados_petr4_sa
WHERE Maxima_Dia IS NOT NULL;

-- Verificar Transformação C: Média móvel de 7 dias
SELECT 
    ticker,
    data,
    Fechamento,
    media_movel_7_dias_fechamento,
    ABS(media_movel_7_dias_fechamento - Fechamento) as diferenca_media,
    algoritmo_media_movel
FROM tech_challenge_bovespa.dados_refinados_petr4_sa
WHERE data >= DATE '2025-09-01'
ORDER BY data DESC
LIMIT 20;

-- =============================================================================
-- 4. CONSULTAS DE PERFORMANCE COM PARTIÇÕES
-- =============================================================================

-- Consulta otimizada usando partições - dados específicos por ticker e data
SELECT 
    ticker,
    data,
    Abertura,
    Fechamento,
    Volume,
    media_movel_7_dias_fechamento
FROM tech_challenge_bovespa.dados_refinados_petr4_sa
WHERE ticker = 'PETR4.SA'
  AND data_particao = '2025-09-23'
ORDER BY data;

-- Consulta multi-partição para comparar ativos
SELECT 
    p.ticker as petr4_ticker,
    p.data as data,
    p.Fechamento as petr4_fechamento,
    v.Fechamento as vale3_fechamento,
    b.Fechamento as ibovespa_fechamento,
    p.media_movel_7_dias_fechamento as petr4_media_movel
FROM tech_challenge_bovespa.dados_refinados_petr4_sa p
FULL OUTER JOIN tech_challenge_bovespa.dados_refinados_vale3_sa v
    ON p.data_particao = v.data_particao
FULL OUTER JOIN tech_challenge_bovespa.dados_refinados_indice_bvsp b
    ON p.data_particao = b.data_particao
WHERE p.data_particao >= '2025-09-01'
ORDER BY p.data DESC
LIMIT 30;

-- =============================================================================
-- 5. ANÁLISES DE NEGÓCIO
-- =============================================================================

-- Volatilidade diária por ativo
SELECT 
    ticker,
    data,
    data_particao,
    Maxima_Dia,
    Minima_Dia,
    ((Maxima_Dia - Minima_Dia) / Minima_Dia) * 100 as volatilidade_percentual,
    Volume,
    volume_medio_mensal
FROM tech_challenge_bovespa.dados_refinados_petr4_sa
WHERE data >= DATE '2025-09-01'
ORDER BY volatilidade_percentual DESC
LIMIT 20;

-- Comparação de performance entre ativos
WITH performance_ativos AS (
    SELECT 
        'PETR4.SA' as ativo,
        data,
        Fechamento,
        LAG(Fechamento) OVER (ORDER BY data) as fechamento_anterior
    FROM tech_challenge_bovespa.dados_refinados_petr4_sa
    WHERE data >= DATE '2025-09-01'
    
    UNION ALL
    
    SELECT 
        'VALE3.SA' as ativo,
        data,
        Fechamento,
        LAG(Fechamento) OVER (ORDER BY data) as fechamento_anterior
    FROM tech_challenge_bovespa.dados_refinados_vale3_sa
    WHERE data >= DATE '2025-09-01'
)
SELECT 
    ativo,
    data,
    Fechamento,
    fechamento_anterior,
    CASE 
        WHEN fechamento_anterior IS NOT NULL AND fechamento_anterior != 0
        THEN ((Fechamento - fechamento_anterior) / fechamento_anterior) * 100
        ELSE NULL 
    END as variacao_percentual_diaria
FROM performance_ativos
WHERE fechamento_anterior IS NOT NULL
ORDER BY ativo, data DESC;

-- Volume médio vs. volume atual - identificar anomalias
SELECT 
    ticker,
    data,
    data_particao,
    Volume,
    volume_medio_mensal,
    (Volume / volume_medio_mensal) as ratio_volume_vs_media,
    CASE 
        WHEN Volume > (volume_medio_mensal * 2) THEN 'Alto Volume'
        WHEN Volume < (volume_medio_mensal * 0.5) THEN 'Baixo Volume'
        ELSE 'Volume Normal'
    END as classificacao_volume
FROM tech_challenge_bovespa.dados_refinados_petr4_sa
WHERE data >= DATE '2025-09-01'
ORDER BY ratio_volume_vs_media DESC
LIMIT 25;

-- =============================================================================
-- 6. CONSULTAS DE QUALIDADE DE DADOS
-- =============================================================================

-- Verificar integridade dos dados
SELECT 
    'dados_refinados_petr4_sa' as tabela,
    COUNT(*) as total_registros,
    COUNT(DISTINCT data) as datas_distintas,
    COUNT(DISTINCT data_particao) as particoes_distintas,
    SUM(CASE WHEN Abertura IS NULL THEN 1 ELSE 0 END) as abertura_nulos,
    SUM(CASE WHEN Fechamento IS NULL THEN 1 ELSE 0 END) as fechamento_nulos,
    SUM(CASE WHEN Volume IS NULL THEN 1 ELSE 0 END) as volume_nulos,
    SUM(CASE WHEN media_movel_7_dias_fechamento IS NULL THEN 1 ELSE 0 END) as media_movel_nulos
FROM tech_challenge_bovespa.dados_refinados_petr4_sa

UNION ALL

SELECT 
    'dados_refinados_vale3_sa' as tabela,
    COUNT(*) as total_registros,
    COUNT(DISTINCT data) as datas_distintas,
    COUNT(DISTINCT data_particao) as particoes_distintas,
    SUM(CASE WHEN Abertura IS NULL THEN 1 ELSE 0 END) as abertura_nulos,
    SUM(CASE WHEN Fechamento IS NULL THEN 1 ELSE 0 END) as fechamento_nulos,
    SUM(CASE WHEN Volume IS NULL THEN 1 ELSE 0 END) as volume_nulos,
    SUM(CASE WHEN media_movel_7_dias_fechamento IS NULL THEN 1 ELSE 0 END) as media_movel_nulos
FROM tech_challenge_bovespa.dados_refinados_vale3_sa;

-- Verificar consistência temporal
SELECT 
    ticker,
    data,
    data_particao,
    data_processamento,
    versao_processamento,
    CASE 
        WHEN DATE(data_particao) = DATE(data) THEN 'Consistente'
        ELSE 'Inconsistente'
    END as consistencia_data
FROM tech_challenge_bovespa.dados_refinados_petr4_sa
WHERE DATE(data_particao) != DATE(data)
ORDER BY data DESC;

-- =============================================================================
-- 7. MÉTRICAS DE MONITORAMENTO
-- =============================================================================

-- Última atualização por ativo
SELECT 
    'PETR4.SA' as ativo,
    MAX(data_processamento) as ultima_atualizacao,
    MAX(data) as ultima_data_dado,
    COUNT(*) as total_registros
FROM tech_challenge_bovespa.dados_refinados_petr4_sa

UNION ALL

SELECT 
    'VALE3.SA' as ativo,
    MAX(data_processamento) as ultima_atualizacao,
    MAX(data) as ultima_data_dado,
    COUNT(*) as total_registros
FROM tech_challenge_bovespa.dados_refinados_vale3_sa

UNION ALL

SELECT 
    'BVSP' as ativo,
    MAX(data_processamento) as ultima_atualizacao,
    MAX(data) as ultima_data_dado,
    COUNT(*) as total_registros
FROM tech_challenge_bovespa.dados_refinados_indice_bvsp;

-- Estatísticas de processamento
SELECT 
    versao_processamento,
    algoritmo_media_movel,
    COUNT(*) as registros_processados,
    MIN(data_processamento) as primeiro_processamento,
    MAX(data_processamento) as ultimo_processamento
FROM tech_challenge_bovespa.dados_refinados_petr4_sa
GROUP BY versao_processamento, algoritmo_media_movel
ORDER BY ultimo_processamento DESC;
