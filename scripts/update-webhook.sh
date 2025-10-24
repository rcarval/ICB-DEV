#!/bin/bash

# Script para actualizar webhook de Slack
# Uso: ./scripts/update-webhook.sh

set -e

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🔗 Actualizando Webhook de Slack${NC}"

echo -e "\n${YELLOW}📋 Para obtener tu webhook real:${NC}"
echo -e "1. Ve a tu workspace de Slack"
echo -e "2. Busca 'Aplicaciones' o 'Apps' en el menú lateral"
echo -e "3. Busca 'Incoming Webhooks' o 'Webhooks entrantes'"
echo -e "4. Haz clic en 'Agregar a Slack'"
echo -e "5. Selecciona el canal donde quieres recibir notificaciones"
echo -e "6. Copia la URL del webhook (formato: https://hooks.slack.com/services/...)"

echo -e "\n${BLUE}📝 Una vez que tengas la URL:${NC}"
echo -e "1. Copia la URL completa"
echo -e "2. Ejecuta: nano .env"
echo -e "3. Reemplaza la línea SLACK_WEBHOOK_URL= con tu URL real"
echo -e "4. Guarda el archivo (Ctrl+X, Y, Enter)"

echo -e "\n${YELLOW}🔧 O ejecuta este comando:${NC}"
echo -e "echo 'SLACK_WEBHOOK_URL=tu-url-real-aqui' > .env"

echo -e "\n${GREEN}✅ Una vez actualizado, ejecuta: ./scripts/test-slack.sh${NC}"

# Verificar configuración actual
if [ -f .env ]; then
    source .env
    if [ -n "$SLACK_WEBHOOK_URL" ]; then
        echo -e "\n${BLUE}📋 Configuración actual:${NC}"
        echo -e "Webhook: $SLACK_WEBHOOK_URL"
        
        if [[ "$SLACK_WEBHOOK_URL" == *"T00000000"* ]]; then
            echo -e "${YELLOW}⚠️  Usando URL de ejemplo - necesitas configurar una URL real${NC}"
        else
            echo -e "${GREEN}✅ URL configurada${NC}"
        fi
    else
        echo -e "\n${RED}❌ Webhook no configurado${NC}"
    fi
else
    echo -e "\n${RED}❌ Archivo .env no encontrado${NC}"
fi
