#!/bin/bash

# Script para configurar webhook de Slack fácilmente
# Uso: ./scripts/setup-webhook.sh

set -e

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🔗 Configuración de Webhook de Slack${NC}"

# Verificar si ya está configurado
if [ -f .env ]; then
    source .env
    if [ -n "$SLACK_WEBHOOK_URL" ] && [ "$SLACK_WEBHOOK_URL" != "" ]; then
        echo -e "${GREEN}✅ Webhook ya configurado: $SLACK_WEBHOOK_URL${NC}"
        echo -e "${YELLOW}¿Quieres probarlo? (y/n)${NC}"
        read -p "> " response
        if [ "$response" = "y" ] || [ "$response" = "Y" ]; then
            ./scripts/test-slack.sh
        fi
        exit 0
    fi
fi

echo -e "\n${YELLOW}📋 Opciones para configurar el webhook:${NC}"
echo -e "1. Configuración manual (recomendada)"
echo -e "2. Usar URL de ejemplo para pruebas"
echo -e "3. Salir"

read -p "Selecciona una opción (1-3): " option

case $option in
    1)
        echo -e "\n${BLUE}📝 Configuración Manual:${NC}"
        echo -e "1. Ve a tu workspace de Slack"
        echo -e "2. Apps → Incoming Webhooks"
        echo -e "3. Add to Slack"
        echo -e "4. Selecciona canal"
        echo -e "5. Copia la URL del webhook"
        echo -e "\n${YELLOW}Pega la URL del webhook aquí:${NC}"
        read -p "> " webhook_url
        
        if [ -n "$webhook_url" ]; then
            # Actualizar .env
            if [ -f .env ]; then
                # Remover línea existente si existe
                sed -i.bak '/SLACK_WEBHOOK_URL=/d' .env
            fi
            echo "SLACK_WEBHOOK_URL=$webhook_url" >> .env
            echo -e "${GREEN}✅ Webhook configurado${NC}"
            
            # Probar webhook
            echo -e "${YELLOW}🧪 Probando webhook...${NC}"
            ./scripts/test-slack.sh
        else
            echo -e "${RED}❌ URL vacía${NC}"
        fi
        ;;
    2)
        echo -e "\n${YELLOW}⚠️  Usando URL de ejemplo para pruebas${NC}"
        echo -e "${BLUE}Nota: Esta URL no funcionará, es solo para pruebas${NC}"
        
        # Crear URL de ejemplo
        example_url="https://hooks.slack.com/services/T00000000/B00000000/XXXXXXXXXXXXXXXXXXXXXXXX"
        echo "SLACK_WEBHOOK_URL=$example_url" >> .env
        echo -e "${GREEN}✅ URL de ejemplo configurada${NC}"
        echo -e "${YELLOW}Recuerda cambiar por tu URL real${NC}"
        ;;
    3)
        echo -e "${YELLOW}👋 Saliendo...${NC}"
        exit 0
        ;;
    *)
        echo -e "${RED}❌ Opción inválida${NC}"
        exit 1
        ;;
esac

echo -e "\n${GREEN}🎉 Configuración completada!${NC}"
echo -e "${BLUE}Comandos disponibles:${NC}"
echo -e "• ./scripts/test-slack.sh - Probar notificaciones"
echo -e "• npm run test:apex - Tests con notificación"
echo -e "• npm run deploy:dev - Deploy con notificación"
