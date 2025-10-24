#!/bin/bash

# Script de configuración inicial para Slack + Salesforce
# Uso: ./scripts/setup-slack.sh

set -e

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🚀 Configurando Slack + Salesforce CI/CD${NC}"

# Verificar dependencias
echo -e "${YELLOW}📋 Verificando dependencias...${NC}"

# Verificar Salesforce CLI
if ! command -v sf &> /dev/null; then
    echo -e "${RED}❌ Salesforce CLI no encontrado${NC}"
    echo -e "${YELLOW}Instala con: npm install -g @salesforce/cli${NC}"
    exit 1
else
    echo -e "${GREEN}✅ Salesforce CLI encontrado${NC}"
fi

# Verificar curl
if ! command -v curl &> /dev/null; then
    echo -e "${RED}❌ curl no encontrado${NC}"
    exit 1
else
    echo -e "${GREEN}✅ curl encontrado${NC}"
fi

# Verificar git
if ! command -v git &> /dev/null; then
    echo -e "${RED}❌ git no encontrado${NC}"
    exit 1
else
    echo -e "${GREEN}✅ git encontrado${NC}"
fi

# Crear archivo .env si no existe
if [ ! -f .env ]; then
    echo -e "${YELLOW}📝 Creando archivo .env...${NC}"
    cat > .env << EOF
# Configuración de Slack
SLACK_WEBHOOK_URL=

# Configuración de Salesforce
SF_AUTH_URL=

# Configuración de GitHub
GITHUB_TOKEN=
EOF
    echo -e "${GREEN}✅ Archivo .env creado${NC}"
else
    echo -e "${YELLOW}⚠️  Archivo .env ya existe${NC}"
fi

# Verificar autenticación de Salesforce
echo -e "${YELLOW}🔐 Verificando autenticación de Salesforce...${NC}"
if sf org list &> /dev/null; then
    echo -e "${GREEN}✅ Autenticado en Salesforce${NC}"
    sf org list
else
    echo -e "${RED}❌ No autenticado en Salesforce${NC}"
    echo -e "${YELLOW}Autentica con: sf org login web --alias dev${NC}"
fi

# Verificar configuración de Git
echo -e "${YELLOW}📦 Verificando configuración de Git...${NC}"
if git remote -v &> /dev/null; then
    echo -e "${GREEN}✅ Repositorio Git configurado${NC}"
    git remote -v
else
    echo -e "${RED}❌ No hay repositorio Git configurado${NC}"
fi

# Mostrar próximos pasos
echo -e "\n${BLUE}📋 Próximos pasos:${NC}"
echo -e "${YELLOW}1. Configura tu webhook de Slack:${NC}"
echo -e "   - Ve a tu workspace de Slack"
echo -e "   - Apps → Incoming Webhooks"
echo -e "   - Copia la URL del webhook"
echo -e "   - Agrega la URL a .env: SLACK_WEBHOOK_URL=tu-url-aqui"

echo -e "\n${YELLOW}2. Configura autenticación de Salesforce:${NC}"
echo -e "   - sf org login web --alias dev"
echo -e "   - O agrega SF_AUTH_URL a .env"

echo -e "\n${YELLOW}3. Configura secrets de GitHub:${NC}"
echo -e "   - Ve a tu repo en GitHub"
echo -e "   - Settings → Secrets and variables → Actions"
echo -e "   - Agrega SLACK_WEBHOOK_URL y SF_AUTH_URL"

echo -e "\n${YELLOW}4. Prueba la configuración:${NC}"
echo -e "   - npm run test:apex"
echo -e "   - npm run deploy:dev"

echo -e "\n${GREEN}🎉 ¡Configuración completada!${NC}"
echo -e "${BLUE}Revisa SLACK_SETUP.md para más detalles${NC}"
