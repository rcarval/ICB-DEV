#!/bin/bash

# Script para configurar Slack automáticamente
# Uso: ./scripts/configure-slack.sh

set -e

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🔧 Configurando Slack para Salesforce CI/CD${NC}"

# Verificar si ya existe .env
if [ -f .env ]; then
    echo -e "${YELLOW}📝 Archivo .env ya existe, actualizando...${NC}"
else
    echo -e "${YELLOW}📝 Creando archivo .env...${NC}"
fi

# Crear/actualizar archivo .env
cat > .env << 'EOF'
# Configuración de Slack
SLACK_WEBHOOK_URL=

# Configuración de Salesforce
SF_AUTH_URL=

# Configuración de GitHub
GITHUB_TOKEN=
EOF

echo -e "${GREEN}✅ Archivo .env creado/actualizado${NC}"

# Obtener información del repositorio
REPO_URL=$(git config --get remote.origin.url)
REPO_NAME=$(basename "$REPO_URL" .git)
GITHUB_OWNER=$(echo "$REPO_URL" | sed 's/.*github.com[:/]\([^/]*\)\/.*/\1/')

echo -e "${BLUE}📋 Información del repositorio:${NC}"
echo -e "   Repositorio: $REPO_NAME"
echo -e "   Owner: $GITHUB_OWNER"
echo -e "   URL: $REPO_URL"

# Crear script para configurar GitHub Secrets
cat > scripts/setup-github-secrets.sh << EOF
#!/bin/bash

# Script para configurar GitHub Secrets
# Uso: ./scripts/setup-github-secrets.sh

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

# Obtener SF_AUTH_URL
if [ -f .env ]; then
    source .env
    if [ -n "\$SF_AUTH_URL" ]; then
        echo "📤 Configurando SF_AUTH_URL..."
        gh secret set SF_AUTH_URL --body "\$SF_AUTH_URL"
        echo "✅ SF_AUTH_URL configurado"
    else
        echo "⚠️  SF_AUTH_URL no configurado en .env"
    fi
else
    echo "❌ Archivo .env no encontrado"
fi

echo "🎉 GitHub Secrets configurados!"
echo "Puedes verificar en: https://github.com/$GITHUB_OWNER/$REPO_NAME/settings/secrets/actions"
EOF

chmod +x scripts/setup-github-secrets.sh

echo -e "${GREEN}✅ Script de GitHub Secrets creado${NC}"

# Crear script de prueba
cat > scripts/test-slack.sh << 'EOF'
#!/bin/bash

# Script para probar notificaciones de Slack
# Uso: ./scripts/test-slack.sh

set -e

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🧪 Probando notificaciones de Slack...${NC}"

# Cargar variables de entorno
if [ -f .env ]; then
    source .env
else
    echo -e "${RED}❌ Archivo .env no encontrado${NC}"
    exit 1
fi

# Verificar webhook URL
if [ -z "$SLACK_WEBHOOK_URL" ]; then
    echo -e "${RED}❌ SLACK_WEBHOOK_URL no configurado${NC}"
    echo -e "${YELLOW}Configura tu webhook en .env${NC}"
    exit 1
fi

# Crear mensaje de prueba
PAYLOAD=$(cat <<EOF
{
  "text": "🧪 Prueba de notificación de Slack",
  "attachments": [
    {
      "color": "good",
      "fields": [
        {
          "title": "Repository",
          "value": "$(git config --get remote.origin.url | sed 's/.*github.com[:/]\\([^.]*\\).*/\\1/')",
          "short": true
        },
        {
          "title": "Branch",
          "value": "$(git branch --show-current)",
          "short": true
        },
        {
          "title": "Commit",
          "value": "$(git rev-parse HEAD)",
          "short": true
        },
        {
          "title": "Test",
          "value": "Notificación de prueba desde Salesforce CI/CD",
          "short": false
        }
      ],
      "footer": "Salesforce CI/CD Test",
      "ts": $(date +%s)
    }
  ]
}
EOF
)

# Enviar notificación
echo -e "${YELLOW}📤 Enviando notificación de prueba...${NC}"
RESPONSE=$(curl -s -X POST -H 'Content-type: application/json' \
     --data "$PAYLOAD" \
     "$SLACK_WEBHOOK_URL")

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ Notificación enviada exitosamente${NC}"
    echo -e "${BLUE}Revisa tu canal de Slack${NC}"
else
    echo -e "${RED}❌ Error enviando notificación${NC}"
    echo -e "${YELLOW}Verifica tu webhook URL${NC}"
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
echo -e "${BLUE}Revisa SLACK_SETUP.md para más detalles${NC}"
