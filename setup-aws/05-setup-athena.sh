#!/bin/bash

# Tech Challenge Bovespa - Setup Athena
# Script para configurar Athena conforme roteiro original

echo "🔍 Configurando AWS Athena..."

# Carregar configurações
source ./config.env

echo "📋 Configurações:"
echo "  Workgroup: $ATHENA_WORKGROUP_NAME"
echo "  Database: $GLUE_DATABASE_NAME"
echo "  Bucket: $BUCKET_NAME"

# 1. Criar bucket para resultados do Athena
ATHENA_RESULTS_BUCKET="${BUCKET_NAME}-athena-results"
echo "📦 Criando bucket para resultados Athena..."

if [[ "$AWS_REGION" == "us-east-1" ]]; then
    aws s3 mb "s3://${ATHENA_RESULTS_BUCKET}" 2>/dev/null || echo "Bucket já existe"
else
    aws s3 mb "s3://${ATHENA_RESULTS_BUCKET}" --region "$AWS_REGION" 2>/dev/null || echo "Bucket já existe"
fi

# 2. Configurar workgroup do Athena
echo "🏢 Criando workgroup Athena..."
cat > athena-workgroup-config.json << EOF
{
  "Name": "$ATHENA_WORKGROUP_NAME",
  "Description": "Workgroup para Tech Challenge Bovespa",
  "Configuration": {
    "EnforceWorkGroupConfiguration": true,
    "PublishCloudWatchMetrics": true,
    "BytesScannedCutoffPerQuery": 1073741824,
    "ResultConfiguration": {
      "OutputLocation": "s3://${ATHENA_RESULTS_BUCKET}/",
      "EncryptionConfiguration": {
        "EncryptionOption": "SSE_S3"
      }
    }
  }
}
EOF

aws athena create-work-group --cli-input-json file://athena-workgroup-config.json 2>/dev/null || echo "Workgroup já existe"

# 3. Verificar se o database existe
echo "🗄️ Verificando database..."
aws glue get-database --name "$GLUE_DATABASE_NAME" > /dev/null 2>&1
if [ $? -ne 0 ]; then
    echo "⚠️ Database $GLUE_DATABASE_NAME não encontrado - será criado automaticamente pelo job Glue"
fi

# 4. Criar consultas de exemplo
echo "📋 Criando consultas de exemplo..."
mkdir -p athena-queries

# Consulta básica de validação
cat > athena-queries/01-validacao-basica.sql << EOF
-- Tech Challenge Bovespa - Consultas de Validação
-- Execute estas consultas no console do Athena após processar dados

-- 1. Verificar databases
SHOW DATABASES;

-- 2. Verificar tabelas (execute após processar dados)
SHOW TABLES IN ${GLUE_DATABASE_NAME};

-- 3. Exemplo de consulta com partição (substitua PETR4_SA pela tabela real)
-- SELECT * FROM ${GLUE_DATABASE_NAME}.dados_refinados_petr4_sa 
-- WHERE data_particao = '2025-09-29' 
-- LIMIT 10;
EOF

# Consulta para verificar transformações
cat > athena-queries/02-verificar-transformacoes.sql << EOF
-- Verificar Transformações Implementadas

-- Transformação A: Volume médio mensal
-- SELECT 
--     ticker,
--     EXTRACT(YEAR FROM data) as ano,
--     EXTRACT(MONTH FROM data) as mes,
--     volume_medio_mensal,
--     dias_negociacao
-- FROM ${GLUE_DATABASE_NAME}.dados_refinados_petr4_sa
-- GROUP BY ticker, ano, mes, volume_medio_mensal, dias_negociacao;

-- Transformação B: Colunas renomeadas
-- SELECT 
--     Abertura,      -- Era "abertura"
--     Maxima_Dia,    -- Era "maxima"
--     Fechamento,
--     Volume
-- FROM ${GLUE_DATABASE_NAME}.dados_refinados_petr4_sa
-- LIMIT 5;

-- Transformação C: Média móvel 7 dias
-- SELECT 
--     data,
--     Fechamento,
--     media_movel_7_dias_fechamento,
--     algoritmo_media_movel
-- FROM ${GLUE_DATABASE_NAME}.dados_refinados_petr4_sa
-- ORDER BY data DESC
-- LIMIT 10;
EOF

# 5. Verificar configuração
echo "🔍 Verificando workgroup Athena..."
aws athena get-work-group --work-group "$ATHENA_WORKGROUP_NAME" --query 'WorkGroup.Name'

if [ $? -eq 0 ]; then
    echo "✅ Athena configurado com sucesso!"
    echo "📍 Workgroup: ${ATHENA_WORKGROUP_NAME}"
    echo "📍 Resultados: s3://${ATHENA_RESULTS_BUCKET}/"
    echo "📍 Consultas: ./athena-queries/"
    echo ""
    echo "🎯 CONFIGURAÇÃO COMPLETA!"
    echo ""
    echo "📋 Próximos passos para testar o pipeline:"
    echo "   1. Execute extração de dados:"
    echo "      cd ../fase1-extracao"
    echo "      python extractor.py --bucket ${BUCKET_NAME}"
    echo ""
    echo "   2. Monitore o pipeline:"
    echo "      - Verifique logs da Lambda no CloudWatch"
    echo "      - Acompanhe execução do job Glue"
    echo "      - Execute consultas Athena após processamento"
    echo ""
    echo "   3. Acesse o console Athena:"
    echo "      - Use workgroup: ${ATHENA_WORKGROUP_NAME}"
    echo "      - Database: ${GLUE_DATABASE_NAME}"
    echo "      - Execute consultas em athena-queries/"
else
    echo "❌ Erro na verificação do Athena"
    exit 1
fi

# Limpar arquivos temporários
rm -f athena-workgroup-config.json