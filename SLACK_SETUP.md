# Configuración de Slack para Salesforce CI/CD

## 1. Configurar Webhook de Slack

### Paso 1: Crear Incoming Webhook
1. Ve a tu workspace de Slack
2. Navega a **Apps** → **Incoming Webhooks**
3. Haz clic en **Add to Slack**
4. Selecciona el canal donde quieres recibir notificaciones
5. Copia la URL del webhook (formato: `https://hooks.slack.com/services/...`)

### Paso 2: Configurar Variables de Entorno

#### Para GitHub Actions:
1. Ve a tu repositorio en GitHub
2. Navega a **Settings** → **Secrets and variables** → **Actions**
3. Agrega los siguientes secrets:
   - `SLACK_WEBHOOK_URL`: Tu URL de webhook de Slack
   - `SF_AUTH_URL`: Tu URL de autenticación de Salesforce

#### Para uso local:
```bash
# Crear archivo .env (no versionar)
echo "SLACK_WEBHOOK_URL=https://hooks.slack.com/services/YOUR/SLACK/WEBHOOK" > .env
echo "SF_AUTH_URL=sfdx://your-auth-url-here" >> .env

# Cargar variables de entorno
source .env
```

## 2. Configurar Canales de Slack

### Canales recomendados:
- `#salesforce-dev` - Para desarrollo y tests
- `#salesforce-deploy` - Para deployments
- `#salesforce-errors` - Para errores y warnings
- `#salesforce-ci` - Para integración continua

### Configurar notificaciones por canal:
```bash
# Canal para tests
export SLACK_TEST_CHANNEL="#salesforce-dev"

# Canal para deployments
export SLACK_DEPLOY_CHANNEL="#salesforce-deploy"

# Canal para errores
export SLACK_ERROR_CHANNEL="#salesforce-errors"
```

## 3. Comandos Disponibles

### Tests con notificación:
```bash
# Ejecutar todos los tests
npm run test:apex

# Ejecutar test específico
npm run test:apex:class ICB_QuoteExcelService_Test

# Ejecutar script directamente
./scripts/test-notify.sh ICB_QuoteExcelService_Test
```

### Deployments con notificación:
```bash
# Deploy a dev
npm run deploy:dev

# Deploy a production
npm run deploy:prod

# Deploy personalizado
./scripts/deploy-notify.sh dev force-app
```

## 4. GitHub Actions

### Workflows configurados:
- **salesforce-ci.yml**: CI/CD completo con tests y deployment
- **salesforce-tests.yml**: Tests específicos con notificaciones

### Triggers automáticos:
- Push a `main` o `develop`
- Pull requests a `main`
- Cambios en archivos `.cls` o `.trigger`
- Ejecución manual con `workflow_dispatch`

## 5. Personalización de Notificaciones

### Modificar mensajes de Slack:
Edita los archivos en `scripts/` para personalizar:
- Colores de las notificaciones
- Campos mostrados
- Formato de los mensajes
- Emojis y iconos

### Ejemplo de personalización:
```bash
# En scripts/test-notify.sh, modifica:
MESSAGE="🎉 ¡Tests pasaron en $REPO!"
COLOR="good"
```

## 6. Troubleshooting

### Problemas comunes:

#### Webhook no funciona:
```bash
# Verificar URL del webhook
curl -X POST -H 'Content-type: application/json' \
     --data '{"text":"Test message"}' \
     $SLACK_WEBHOOK_URL
```

#### Variables de entorno no cargan:
```bash
# Verificar variables
echo $SLACK_WEBHOOK_URL
echo $SF_AUTH_URL
```

#### Tests no ejecutan:
```bash
# Verificar autenticación
sf org list
sf apex run test --class-names ICB_QuoteExcelService_Test
```

## 7. Monitoreo y Logs

### Ver logs de GitHub Actions:
1. Ve a tu repositorio en GitHub
2. Navega a **Actions**
3. Selecciona el workflow que falló
4. Revisa los logs para debugging

### Ver logs locales:
```bash
# Ejecutar con verbose
./scripts/test-notify.sh ICB_QuoteExcelService_Test 2>&1 | tee test.log

# Ver logs de deployment
./scripts/deploy-notify.sh dev 2>&1 | tee deploy.log
```

## 8. Mejores Prácticas

### Seguridad:
- Nunca versiones archivos `.env`
- Usa secrets de GitHub para URLs sensibles
- Rota webhooks de Slack regularmente

### Performance:
- Ejecuta tests solo cuando sea necesario
- Usa `--wait` para evitar timeouts
- Configura timeouts apropiados

### Colaboración:
- Notifica al equipo sobre deployments importantes
- Usa canales específicos para diferentes tipos de notificaciones
- Documenta cambios en workflows
