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
echo "Puedes verificar en: https://github.com/rcarval/ICB-DEV/settings/secrets/actions"
