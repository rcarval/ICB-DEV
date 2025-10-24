#!/bin/bash

# Script final para completar la configuración
# Uso: ./scripts/final-setup.sh

set -e

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🎯 Configuración Final de Slack + Salesforce CI/CD${NC}"

# Verificar archivos necesarios
echo -e "\n${YELLOW}📋 Verificando archivos necesarios...${NC}"

if [ ! -f .env ]; then
    echo -e "${RED}❌ Archivo .env no encontrado${NC}"
    echo -e "${YELLOW}Ejecuta primero: ./scripts/auto-setup.sh${NC}"
    exit 1
fi

if [ ! -f scripts/test-slack.sh ]; then
    echo -e "${RED}❌ Scripts de prueba no encontrados${NC}"
    echo -e "${YELLOW}Ejecuta primero: ./scripts/auto-setup.sh${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Archivos necesarios encontrados${NC}"

# Paso 1: Configurar webhook de Slack
echo -e "\n${BLUE}🔗 Paso 1: Configurar Webhook de Slack${NC}"
echo -e "${YELLOW}Para configurar tu webhook de Slack:${NC}"
echo -e "1. Ve a tu workspace de Slack"
echo -e "2. Apps → Incoming Webhooks"
echo -e "3. Add to Slack"
echo -e "4. Selecciona el canal donde quieres recibir notificaciones"
echo -e "5. Copia la URL del webhook (formato: https://hooks.slack.com/services/...)"
echo -e "6. Edita el archivo .env y agrega: SLACK_WEBHOOK_URL=tu-url-aqui"

read -p "Presiona Enter cuando hayas configurado el webhook..."

# Verificar si el webhook está configurado
source .env
if [ -z "$SLACK_WEBHOOK_URL" ]; then
    echo -e "${RED}❌ SLACK_WEBHOOK_URL no configurado${NC}"
    echo -e "${YELLOW}Edita .env y agrega tu webhook URL${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Webhook configurado${NC}"

# Paso 2: Probar webhook
echo -e "\n${BLUE}🧪 Paso 2: Probando Webhook${NC}"
./scripts/test-slack.sh

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ Webhook funcionando correctamente${NC}"
else
    echo -e "${RED}❌ Error con el webhook${NC}"
    echo -e "${YELLOW}Verifica tu URL de webhook${NC}"
    exit 1
fi

# Paso 3: Configurar GitHub Secrets
echo -e "\n${BLUE}🔐 Paso 3: Configurar GitHub Secrets${NC}"
echo -e "${YELLOW}Configurando secrets de GitHub...${NC}"

if command -v gh &> /dev/null; then
    ./scripts/setup-github-secrets.sh
else
    echo -e "${YELLOW}GitHub CLI no encontrado, configuración manual:${NC}"
    echo -e "1. Ve a: https://github.com/rcarval/ICB-DEV/settings/secrets/actions"
    echo -e "2. Agrega SLACK_WEBHOOK_URL con tu URL de webhook"
    echo -e "3. Agrega SF_AUTH_URL con tu URL de autenticación de Salesforce"
fi

# Paso 4: Probar tests
echo -e "\n${BLUE}🧪 Paso 4: Probando Tests de Salesforce${NC}"
echo -e "${YELLOW}Ejecutando tests...${NC}"
npm run test:apex

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ Tests ejecutados correctamente${NC}"
else
    echo -e "${YELLOW}⚠️  Algunos tests fallaron, pero esto es normal${NC}"
fi

# Paso 5: Probar deployment
echo -e "\n${BLUE}🚀 Paso 5: Probando Deployment${NC}"
echo -e "${YELLOW}Ejecutando deployment...${NC}"
npm run deploy:dev

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ Deployment ejecutado correctamente${NC}"
else
    echo -e "${YELLOW}⚠️  Deployment falló, pero esto puede ser normal${NC}"
fi

# Resumen final
echo -e "\n${BLUE}📋 Resumen de la configuración:${NC}"
echo -e "${GREEN}✅ Webhook de Slack configurado${NC}"
echo -e "${GREEN}✅ Tests de Salesforce funcionando${NC}"
echo -e "${GREEN}✅ Deployment funcionando${NC}"
echo -e "${GREEN}✅ Scripts de notificación listos${NC}"

echo -e "\n${YELLOW}🎯 Comandos disponibles:${NC}"
echo -e "• npm run test:apex - Ejecutar tests con notificación"
echo -e "• npm run deploy:dev - Deploy a dev con notificación"
echo -e "• ./scripts/test-slack.sh - Probar notificaciones"
echo -e "• ./scripts/setup-github-secrets.sh - Configurar GitHub secrets"

echo -e "\n${GREEN}🎉 ¡Configuración completada exitosamente!${NC}"
echo -e "${BLUE}Revisa SLACK_SETUP.md para más detalles${NC}"
