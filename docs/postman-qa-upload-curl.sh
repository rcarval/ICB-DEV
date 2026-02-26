#!/bin/bash
# Prueba POST /v1/firma/upload - QA
# Copiar a Postman: Import → Raw text, o ejecutar en terminal (bash postman-qa-upload-curl.sh)

API_KEY="CGMFX4QnyJ9pDLrGfKLdK3ghwArrpgJ1160DlaSJ"
BASE_URL="https://integraciones-qa.icbfs.cl"

curl -X POST "${BASE_URL}/v1/firma/upload" \
  -H "x-api-key: ${API_KEY}" \
  -H "Content-Type: application/json" \
  -d '{
    "contratoId": "TEST-POSTMAN-001",
    "fileName": "test.pdf",
    "signatureConfig": {
      "nombre": "Contrato Comodato - Prueba",
      "firmantes": [
        {
          "nombre": "Juan Pérez",
          "email": "juan.perez@empresa.cl",
          "rut": "12.345.678-9",
          "telefono": "+56912345678"
        }
      ]
    }
  }'
