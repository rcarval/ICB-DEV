#!/bin/bash

# Script para deploy y notificar a Slack
# Uso: ./scripts/deploy-notify.sh [target-org] [source-dir]

set -e

# Configuración
SLACK_WEBHOOK_URL="${SLACK_WEBHOOK_URL:-}"
TARGET_ORG="${1:-ICBFOOD-DEV}"
SOURCE_DIR="${2:-force-app}"

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🚀 Iniciando deployment a Salesforce...${NC}"
echo -e "${YELLOW}Target Org: $TARGET_ORG${NC}"
echo -e "${YELLOW}Source Dir: $SOURCE_DIR${NC}"

# Ejecutar deployment
echo -e "${YELLOW}📦 Ejecutando sf project deploy start...${NC}"
DEPLOY_RESULT=$(sf project deploy start --source-dir "$SOURCE_DIR" --target-org "$TARGET_ORG" --wait 10 2>&1)

# Verificar resultado
if [ $? -eq 0 ]; then
    STATUS="success"
    MESSAGE="✅ Deployment exitoso"
    COLOR="good"
    echo -e "${GREEN}✅ Deployment completado exitosamente${NC}"
else
    STATUS="failure"
    MESSAGE="❌ Deployment falló"
    COLOR="danger"
    echo -e "${RED}❌ Deployment falló${NC}"
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
  "text": "🚀 $MESSAGE",
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
          "title": "Target Org",
          "value": "$TARGET_ORG",
          "short": true
        },
        {
          "title": "Source Dir",
          "value": "$SOURCE_DIR",
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
      "footer": "Salesforce Deployment",
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
echo -e "\n${YELLOW}📋 Resultado del deployment:${NC}"
echo "$DEPLOY_RESULT"

# Exit con código de error si el deployment falló
if [ "$STATUS" = "failure" ]; then
    exit 1
fi
