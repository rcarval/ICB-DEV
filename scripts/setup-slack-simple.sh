#!/bin/bash

# Script simple para configurar Slack
# Uso: ./scripts/setup-slack-simple.sh

set -e

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🔧 Configurando Slack para Salesforce CI/CD${NC}"

# Crear archivo .env
cat > .env << 'EOF'
# Configuración de Slack
SLACK_WEBHOOK_URL=

# Configuración de Salesforce
SF_AUTH_URL=

# Configuración de GitHub
GITHUB_TOKEN=
EOF

echo -e "${GREEN}✅ Archivo .env creado${NC}"

# Obtener información del repositorio
REPO_URL=$(git config --get remote.origin.url)
REPO_NAME=$(basename "$REPO_URL" .git)
GITHUB_OWNER=$(echo "$REPO_URL" | sed 's/.*github.com[:/]\([^/]*\)\/.*/\1/')

echo -e "${BLUE}📋 Información del repositorio:${NC}"
echo -e "   Repositorio: $REPO_NAME"
echo -e "   Owner: $GITHUB_OWNER"
echo -e "   URL: $REPO_URL"

# Crear script para GitHub Secrets
cat > scripts/setup-github-secrets.sh << 'EOF'
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
    if [ -n "$SLACK_WEBHOOK_URL" ]; then
        echo "📤 Configurando SLACK_WEBHOOK_URL..."
        gh secret set SLACK_WEBHOOK_URL --body "$SLACK_WEBHOOK_URL"
        echo "✅ SLACK_WEBHOOK_URL configurado"
    else
        echo "⚠️  SLACK_WEBHOOK_URL no configurado en .env"
    fi
else
    echo "❌ Archivo .env no encontrado"
fi

echo "🎉 GitHub Secrets configurados!"
EOF

chmod +x scripts/setup-github-secrets.sh

echo -e "${GREEN}✅ Script de GitHub Secrets creado${NC}"

# Crear script de prueba
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

# Mostrar instrucciones
echo -e "\n${BLUE}📋 Próximos pasos:${NC}"
echo -e "${YELLOW}1. Configura tu webhook de Slack:${NC}"
echo -e "   - Ve a tu workspace de Slack"
echo -e "   - Apps → Incoming Webhooks"
echo -e "   - Copia la URL del webhook"
echo -e "   - Edita .env y agrega: SLACK_WEBHOOK_URL=tu-url-aqui"

echo -e "\n${YELLOW}2. Configura GitHub Secrets:${NC}"
echo -e "   - Ejecuta: ./scripts/setup-github-secrets.sh"
echo -e "   - O manualmente en: https://github.com/$GITHUB_OWNER/$REPO_NAME/settings/secrets/actions"

echo -e "\n${YELLOW}3. Prueba la configuración:${NC}"
echo -e "   - ./scripts/test-slack.sh"
echo -e "   - npm run test:apex"
echo -e "   - npm run deploy:dev"

echo -e "\n${GREEN}🎉 ¡Configuración completada!${NC}"
