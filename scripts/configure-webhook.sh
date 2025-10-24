#!/bin/bash

# Script para configurar webhook de Slack paso a paso
# Uso: ./scripts/configure-webhook.sh

set -e

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🔗 Configurando Webhook de Slack${NC}"

echo -e "\n${YELLOW}📋 Para configurar tu webhook de Slack:${NC}"
echo -e "1. Ve a tu workspace de Slack"
echo -e "2. En el menú lateral, haz clic en 'Apps'"
echo -e "3. Busca 'Incoming Webhooks'"
echo -e "4. Haz clic en 'Add to Slack'"
echo -e "5. Selecciona el canal donde quieres recibir notificaciones"
echo -e "6. Haz clic en 'Add Incoming Webhooks integration'"
echo -e "7. Copia la URL del webhook (formato: https://hooks.slack.com/services/...)"

echo -e "\n${BLUE}📝 Una vez que tengas la URL del webhook:${NC}"
echo -e "1. Copia la URL completa"
echo -e "2. Ejecuta: nano .env"
echo -e "3. Reemplaza la línea vacía SLACK_WEBHOOK_URL= con tu URL"
echo -e "4. Guarda el archivo (Ctrl+X, Y, Enter)"

echo -e "\n${YELLOW}🔧 O ejecuta este comando para configurar automáticamente:${NC}"
echo -e "echo 'SLACK_WEBHOOK_URL=tu-url-aqui' >> .env"

echo -e "\n${GREEN}✅ Una vez configurado, ejecuta: ./scripts/test-slack.sh${NC}"

# Verificar si ya está configurado
if [ -f .env ]; then
    source .env
    if [ -n "$SLACK_WEBHOOK_URL" ] && [ "$SLACK_WEBHOOK_URL" != "" ]; then
        echo -e "\n${GREEN}✅ Webhook ya configurado: $SLACK_WEBHOOK_URL${NC}"
        echo -e "${YELLOW}¿Quieres probarlo ahora? (y/n)${NC}"
        read -p "> " response
        if [ "$response" = "y" ] || [ "$response" = "Y" ]; then
            ./scripts/test-slack.sh
        fi
    else
        echo -e "\n${RED}❌ Webhook no configurado${NC}"
        echo -e "${YELLOW}Sigue los pasos arriba para configurarlo${NC}"
    fi
else
    echo -e "\n${RED}❌ Archivo .env no encontrado${NC}"
    echo -e "${YELLOW}Ejecuta primero: ./scripts/auto-setup.sh${NC}"
fi
