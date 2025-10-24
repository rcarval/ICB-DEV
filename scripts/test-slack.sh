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
