#!/bin/bash

# Script para ejecutar tests y notificar a Slack
# Uso: ./scripts/test-notify.sh [test-class-name]

set -e

# Configuración
SLACK_WEBHOOK_URL="${SLACK_WEBHOOK_URL:-}"
TEST_CLASS="${1:-}"

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}🧪 Ejecutando tests de Salesforce...${NC}"

# Ejecutar tests
if [ -n "$TEST_CLASS" ]; then
    echo -e "${YELLOW}Ejecutando test class: $TEST_CLASS${NC}"
    TEST_RESULT=$(sf apex run test --class-names "$TEST_CLASS" --result-format human --wait 10)
else
    echo -e "${YELLOW}Ejecutando todos los tests${NC}"
    TEST_RESULT=$(sf apex run test --result-format human --wait 10)
fi

# Verificar resultado
if [[ $TEST_RESULT == *"Passed"* ]] && [[ $TEST_RESULT != *"Failed"* ]]; then
    STATUS="success"
    MESSAGE="✅ Tests pasaron correctamente"
    COLOR="good"
    echo -e "${GREEN}✅ Tests exitosos${NC}"
else
    STATUS="failure"
    MESSAGE="❌ Tests fallaron"
    COLOR="danger"
    echo -e "${RED}❌ Tests fallaron${NC}"
fi

# Enviar notificación a Slack si está configurado
if [ -n "$SLACK_WEBHOOK_URL" ]; then
    echo -e "${YELLOW}📤 Enviando notificación a Slack...${NC}"
    
    # Extraer información del commit actual
    COMMIT_SHA=$(git rev-parse HEAD)
    COMMIT_MSG=$(git log -1 --pretty=%B)
    BRANCH=$(git branch --show-current)
    REPO=$(git config --get remote.origin.url | sed 's/.*github.com[:/]\([^.]*\).*/\1/')
    
    # Crear payload para Slack
    PAYLOAD=$(cat <<EOF
{
  "text": "🧪 $MESSAGE",
  "attachments": [
    {
      "color": "$COLOR",
      "fields": [
        {
          "title": "Repository",
          "value": "$REPO",
          "short": true
        },
        {
          "title": "Branch",
          "value": "$BRANCH",
          "short": true
        },
        {
          "title": "Test Class",
          "value": "${TEST_CLASS:-All Tests}",
          "short": true
        },
        {
          "title": "Commit",
          "value": "$COMMIT_SHA",
          "short": true
        },
        {
          "title": "Commit Message",
          "value": "$COMMIT_MSG",
          "short": false
        }
      ],
      "footer": "Salesforce Tests",
      "ts": $(date +%s)
    }
  ]
}
EOF
)
    
    # Enviar a Slack
    curl -X POST -H 'Content-type: application/json' \
         --data "$PAYLOAD" \
         "$SLACK_WEBHOOK_URL"
    
    echo -e "${GREEN}✅ Notificación enviada a Slack${NC}"
else
    echo -e "${YELLOW}⚠️  SLACK_WEBHOOK_URL no configurado, saltando notificación${NC}"
fi

# Mostrar resultado final
echo -e "\n${YELLOW}📋 Resultado del test:${NC}"
echo "$TEST_RESULT"

# Exit con código de error si los tests fallaron
if [ "$STATUS" = "failure" ]; then
    exit 1
fi
