#!/bin/bash

# Script para obtener webhook de Slack
# Uso: ./scripts/get-slack-webhook.sh

set -e

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🔗 Configurando Webhook de Slack${NC}"

# Verificar si Slack CLI está instalado
if ! command -v slack &> /dev/null; then
    echo -e "${YELLOW}📦 Instalando Slack CLI...${NC}"
    npm install -g @slack/cli
fi

# Verificar autenticación con Slack
if ! slack auth list &> /dev/null; then
    echo -e "${YELLOW}🔑 Autenticando con Slack...${NC}"
    slack login
fi

echo -e "${BLUE}📋 Lista de workspaces disponibles:${NC}"
slack auth list

echo -e "\n${YELLOW}🔧 Creando Incoming Webhook...${NC}"

# Crear webhook
WEBHOOK_URL=$(slack webhook create --channel "#general" --title "Salesforce CI/CD" --description "Notificaciones de Salesforce CI/CD" 2>/dev/null || echo "")

if [ -n "$WEBHOOK_URL" ]; then
    echo -e "${GREEN}✅ Webhook creado: $WEBHOOK_URL${NC}"
    
    # Actualizar .env
    if [ -f .env ]; then
        # Remover línea existente si existe
        sed -i.bak '/SLACK_WEBHOOK_URL=/d' .env
        # Agregar nueva línea
        echo "SLACK_WEBHOOK_URL=$WEBHOOK_URL" >> .env
        echo -e "${GREEN}✅ Archivo .env actualizado${NC}"
    else
        echo -e "${YELLOW}⚠️  Archivo .env no encontrado, creándolo...${NC}"
        cat > .env << EOF
# Configuración de Slack
SLACK_WEBHOOK_URL=$WEBHOOK_URL

# Configuración de Salesforce
SF_AUTH_URL=

# Configuración de GitHub
GITHUB_TOKEN=
EOF
        echo -e "${GREEN}✅ Archivo .env creado${NC}"
    fi
    
    echo -e "\n${BLUE}🧪 Probando webhook...${NC}"
    ./scripts/test-slack.sh
    
else
    echo -e "${RED}❌ Error creando webhook${NC}"
    echo -e "${YELLOW}Configura manualmente:${NC}"
    echo -e "1. Ve a tu workspace de Slack"
    echo -e "2. Apps → Incoming Webhooks"
    echo -e "3. Add to Slack"
    echo -e "4. Selecciona canal"
    echo -e "5. Copia la URL del webhook"
    echo -e "6. Edita .env y agrega: SLACK_WEBHOOK_URL=tu-url-aqui"
fi

echo -e "\n${GREEN}🎉 ¡Configuración de Slack completada!${NC}"
