#!/bin/bash

# Script para configurar todo automáticamente
# Uso: ./scripts/auto-setup.sh

set -e

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🚀 Configuración Automática de Slack + Salesforce CI/CD${NC}"

# 1. Configurar archivo .env
echo -e "\n${YELLOW}📝 Paso 1: Configurando archivo .env...${NC}"
cat > .env << 'EOF'
# Configuración de Slack
SLACK_WEBHOOK_URL=

# Configuración de Salesforce
SF_AUTH_URL=

# Configuración de GitHub
GITHUB_TOKEN=
EOF
echo -e "${GREEN}✅ Archivo .env creado${NC}"

# 2. Obtener información del repositorio
REPO_URL=$(git config --get remote.origin.url)
REPO_NAME=$(basename "$REPO_URL" .git)
GITHUB_OWNER=$(echo "$REPO_URL" | sed 's/.*github.com[:/]\([^/]*\)\/.*/\1/')

echo -e "\n${BLUE}📋 Información del repositorio:${NC}"
echo -e "   Repositorio: $REPO_NAME"
echo -e "   Owner: $GITHUB_OWNER"
echo -e "   URL: $REPO_URL"

# 3. Crear script de configuración de GitHub
echo -e "\n${YELLOW}📝 Paso 2: Creando script de GitHub Secrets...${NC}"
cat > scripts/setup-github-secrets.sh << EOF
#!/bin/bash

echo "🔐 Configurando GitHub Secrets..."

# Verificar si gh CLI está instalado
if ! command -v gh &> /dev/null; then
    echo "❌ GitHub CLI no encontrado"
    echo "Instala con: brew install gh (macOS) o apt install gh (Ubuntu)"
    echo "O ve a: https://cli.github.com/"
    exit 1
fi

# Verificar autenticación
if ! gh auth status &> /dev/null; then
    echo "🔑 Autenticando con GitHub..."
    gh auth login
fi

# Obtener webhook URL del .env
if [ -f .env ]; then
    source .env
    if [ -n "\$SLACK_WEBHOOK_URL" ]; then
        echo "📤 Configurando SLACK_WEBHOOK_URL..."
        gh secret set SLACK_WEBHOOK_URL --body "\$SLACK_WEBHOOK_URL"
        echo "✅ SLACK_WEBHOOK_URL configurado"
    else
        echo "⚠️  SLACK_WEBHOOK_URL no configurado en .env"
    fi
else
    echo "❌ Archivo .env no encontrado"
fi

echo "🎉 GitHub Secrets configurados!"
echo "Puedes verificar en: https://github.com/$GITHUB_OWNER/$REPO_NAME/settings/secrets/actions"
EOF

chmod +x scripts/setup-github-secrets.sh
echo -e "${GREEN}✅ Script de GitHub Secrets creado${NC}"

# 4. Crear script de prueba
echo -e "\n${YELLOW}📝 Paso 3: Creando script de prueba...${NC}"
cat > scripts/test-slack.sh << 'EOF'
#!/bin/bash

echo "🧪 Probando notificaciones de Slack..."

# Cargar variables de entorno
if [ -f .env ]; then
    source .env
else
    echo "❌ Archivo .env no encontrado"
    exit 1
fi

# Verificar webhook URL
if [ -z "$SLACK_WEBHOOK_URL" ]; then
    echo "❌ SLACK_WEBHOOK_URL no configurado"
    echo "Configura tu webhook en .env"
    exit 1
fi

# Crear mensaje de prueba
PAYLOAD='{
  "text": "🧪 Prueba de notificación de Slack",
  "attachments": [
    {
      "color": "good",
      "fields": [
        {
          "title": "Repository",
          "value": "ICB-DEV",
          "short": true
        },
        {
          "title": "Test",
          "value": "Notificación de prueba desde Salesforce CI/CD",
          "short": false
        }
      ],
      "footer": "Salesforce CI/CD Test"
    }
  ]
}'

# Enviar notificación
echo "📤 Enviando notificación de prueba..."
curl -X POST -H 'Content-type: application/json' \
     --data "$PAYLOAD" \
     "$SLACK_WEBHOOK_URL"

if [ $? -eq 0 ]; then
    echo "✅ Notificación enviada exitosamente"
    echo "Revisa tu canal de Slack"
else
    echo "❌ Error enviando notificación"
    echo "Verifica tu webhook URL"
fi
EOF

chmod +x scripts/test-slack.sh
echo -e "${GREEN}✅ Script de prueba creado${NC}"

# 5. Crear script de configuración completa
echo -e "\n${YELLOW}📝 Paso 4: Creando script de configuración completa...${NC}"
cat > scripts/complete-setup.sh << 'EOF'
#!/bin/bash

echo "🔧 Configuración Completa de Slack + Salesforce CI/CD"

# 1. Configurar webhook de Slack
echo "📝 Configurando webhook de Slack..."
echo "Ve a tu workspace de Slack:"
echo "1. Apps → Incoming Webhooks"
echo "2. Add to Slack"
echo "3. Selecciona canal"
echo "4. Copia la URL del webhook"
echo "5. Edita .env y agrega: SLACK_WEBHOOK_URL=tu-url-aqui"

read -p "Presiona Enter cuando hayas configurado el webhook..."

# 2. Probar webhook
echo "🧪 Probando webhook..."
./scripts/test-slack.sh

# 3. Configurar GitHub Secrets
echo "🔐 Configurando GitHub Secrets..."
./scripts/setup-github-secrets.sh

# 4. Probar tests
echo "🧪 Probando tests de Salesforce..."
npm run test:apex

# 5. Probar deployment
echo "🚀 Probando deployment..."
npm run deploy:dev

echo "🎉 ¡Configuración completa!"
EOF

chmod +x scripts/complete-setup.sh
echo -e "${GREEN}✅ Script de configuración completa creado${NC}"

# 6. Mostrar resumen
echo -e "\n${BLUE}📋 Resumen de la configuración:${NC}"
echo -e "${GREEN}✅ Archivo .env creado${NC}"
echo -e "${GREEN}✅ Scripts de GitHub Secrets creados${NC}"
echo -e "${GREEN}✅ Scripts de prueba creados${NC}"
echo -e "${GREEN}✅ Scripts de configuración completa creados${NC}"

echo -e "\n${YELLOW}🚀 Para completar la configuración:${NC}"
echo -e "1. Ejecuta: ./scripts/complete-setup.sh"
echo -e "2. O sigue los pasos manuales en SLACK_SETUP.md"

echo -e "\n${GREEN}🎉 ¡Configuración automática completada!${NC}"
