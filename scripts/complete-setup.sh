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
