# Payloads y respuestas de los servicios Firma Digital (TuFirma)

Según el flujo actual y el log de ejemplo (Quote 00000474, contratoId FD-00000474).

---

## 1. POST /v1/firma/upload (solicitar URL de subida)

**Endpoint:** `https://integraciones-qa.icbfs.cl/v1/firma/upload`  
**Método:** POST  
**Headers:** `Content-Type: application/json`, `x-api-key` (Named Credential).

### Request (payload)

Estructura que envía `ICB_FirmaDigitalServiceImpl.solicitarUploadUrl()`:

```json
{
  "contratoId": "FD-00000474",
  "fileName": "documento.pdf",
  "signatureConfig": {
    "nombre": "Presupuesto Comodato Test1",
    "firmantes": [
      {
        "nombre": "Rodrigo Alonso Carvallo González",
        "email": "rodrigocarvallog@gmail.com",
        "rut": "17306316-4",
        "telefono": "+56912345678"
      }
    ]
  }
}
```

- `contratoId`: identificador único del contrato (ej. `FD-` + QuoteNumber).
- `fileName`: nombre del archivo PDF.
- `signatureConfig.nombre`: nombre del contrato (ej. nombre de la Quote).
- `signatureConfig.firmantes`: array con nombre, email, rut, telefono (desde **Contact.MobilePhone**) del Contact de la Quote.

### Response (ejemplo 200 OK)

El log indica **Response Size bytes=1995**. Estructura según `UploadResponseDto`:

```json
{
  "success": true,
  "contratoId": "FD-00000474",
  "uploadUrl": "https://icbfs-documents-qa.s3.us-east-1.amazonaws.com/unsigned/FD-00000474/documento.pdf?X-Amz-Algorithm=...",
  "expiresAt": "2026-02-24T20:16:03.000Z"
}
```

- `uploadUrl`: URL prefirmada de S3 para hacer el PUT del PDF (expira en 15 min típicamente).
- `expiresAt`: fecha de expiración de la URL.

---

## 2. PUT a uploadUrl (subir el PDF a S3)

**Endpoint:** el valor de `uploadUrl` devuelto en el POST anterior (dominio S3).  
**Método:** PUT  
**Headers:** los que vengan en la URL prefirmada (no se usa Named Credential; debe estar el host S3 en Remote Site Settings).

### Request (payload)

- **Body:** binario del PDF (no JSON). En el log: `BLOB(487728 bytes)`.
- No se envía ningún JSON; solo el contenido del archivo PDF.

### Response

- **StatusCode:** 200 OK (en el log: `CALLOUT_RESPONSE | System.HttpResponse[Status=OK, StatusCode=200]`).
- **Body:** vacío o mínimo (el log no muestra cuerpo; S3 suele devolver 200 sin cuerpo relevante).

---

## 3. GET /v1/firma/status/{contratoId} (consultar estado)

**Endpoint:** `https://integraciones-qa.icbfs.cl/v1/firma/status/FD-00000474`  
**Método:** GET  
**Headers:** `x-api-key` (Named Credential). Sin body.

### Request (payload)

- **Body:** ninguno (petición GET).

### Response (ejemplo 200 OK en tu log)

El log indica **Response Size bytes=86** y el log de Apex: `consultarEstado | ok | status=` (vacío).  
Eso indica que el API respondió 200 pero con `data` vacío o sin campos poblados todavía (el backend puede tardar en procesar el documento). Estructura según `StatusResponseDto`:

```json
{
  "success": true,
  "data": null
}
```

o, cuando el backend ya tiene el documento procesado, algo como:

```json
{
  "success": true,
  "data": {
    "contratoId": "FD-00000474",
    "status": "pending",
    "tufirmaDocumentId": "...",
    "uploadUrl": "...",
    "signedDocumentUrl": "https://...",
    "fileName": "documento.pdf",
    "createdAt": "...",
    "updatedAt": "..."
  },
  "error": null
}
```

En tu ejecución, al llamar a status justo después del PUT, `data` venía vacío o sin `tufirmaDocumentId` / `signedDocumentUrl`, por eso en Contrato_Digital__c esos campos quedan en blanco hasta que TuFirma los exponga (por ejemplo en una segunda consulta de status o por webhook).

---

## Resumen por llamada

| # | Servicio              | Payload (request)                          | Response (ejemplo)                          |
|---|------------------------|---------------------------------------------|---------------------------------------------|
| 1 | POST /v1/firma/upload  | JSON: contratoId, fileName, signatureConfig | JSON: success, contratoId, uploadUrl, expiresAt |
| 2 | PUT uploadUrl (S3)    | Binario: PDF (Body)                         | 200 OK, sin cuerpo relevante                 |
| 3 | GET /v1/firma/status/  | Sin body                                    | JSON: success, data (status, tufirmaDocumentId, signedDocumentUrl, …) o data null |

Si necesitas ver el JSON exacto de request/response en cada ejecución, se puede añadir en el servicio un log (truncado por tamaño) del body de request y de response para POST y GET; el PUT es binario y no se suele loguear entero.
