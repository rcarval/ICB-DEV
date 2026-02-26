# Credencial nombrada Firma Digital – Paso a paso (Dev/QA)

Según la documentación de arquitectura, el API usa **API Key** en el header `x-api-key`. En Salesforce se configura con **External Credential** + **Named Credential**. Usa **QA** si Dev no está disponible.

---

## Datos por ambiente (documentación)

| Ambiente | URL base | API Key (obtener en AWS Console → API Gateway → API Keys) |
|----------|----------|-----------------------------------------------------------|
| **DEV**  | `https://integraciones-dev.icbfs.cl`  | ID: `icbfs-integraciones-salesforce-key-*` (valor en AWS) |
| **QA**   | `https://integraciones-qa.icbfs.cl`   | ID: `icbfs-integraciones-salesforce-key-qa` – valor en AWS |
| **PROD** | `https://integraciones.icbfs.cl`     | ID: `icbfs-integraciones-salesforce-key-prod` – valor en AWS |

⚠️ El valor real de la API Key se obtiene en **AWS Console → API Gateway → API Keys** (por ambiente). No se debe versionar en el repo.

---

## Paso 1: Crear External Credential

1. En Salesforce: **Setup** (Configuración).
2. En la barra de búsqueda escribe **Named Credentials** y entra a **Named Credentials**.
3. Abre la pestaña **External Credentials**.
4. Pulsa **New External Credential**.
5. Completa:
   - **Label:** `Firma Digital API (ICB)`
   - **Name (Developer Name):** `ICB_FirmaDigital_External`  
     (este nombre se usará en el header como `{!$Credential.ICB_FirmaDigital_External.APIKey}`)
   - **Authentication Protocol:** **Custom** (o **Password** si en tu org no aparece Custom; si usas Password, el “Password” será la API Key).
6. **Save**.

---

## Paso 2: Permission Set y mapeo (guardar la API Key)

La API Key se guarda como **Authentication Parameter** en un mapeo de la External Credential.

1. Crea un **Permission Set** solo para contener el acceso a esta credencial (opcional pero recomendable):
   - **Setup → Permission Sets → New**
   - **Label:** `Firma Digital – API Access`
   - **API Name:** `Firma_Digital_API_Access`
   - **Save** (no hace falta asignar permisos extra; el uso de la credencial se controla por el mapeo).

2. En la **External Credential** que creaste, en la sección **Permission Set Mappings** pulsa **New**.

3. Configura el mapeo:
   - **Permission Set:** el que creaste (ej. `Firma Digital – API Access`) o uno existente que tengan los usuarios/perfiles que llamen al API.
   - **Sequence Number:** `1`
   - **Identity Type:** **Named Principal** (misma API Key para todos los usuarios que tengan el permission set).

4. En **Authentication Parameters** pulsa **Add**:
   - **Name (API name):** `APIKey`
   - **Value:** pega aquí el valor de la **API Key** del ambiente (DEV o QA) obtenido en AWS API Gateway.

5. **Save** en el mapeo y en la External Credential.

---

## Paso 3: Custom Header (enviar x-api-key)

1. En la misma **External Credential**, en la sección **Custom Headers** pulsa **New**.

2. Configura:
   - **Name:** `x-api-key`  
     (tal cual lo espera el API)
   - **Value:**  
     `{!$Credential.ICB_FirmaDigital_External.APIKey}`  
     (si cambiaste el Developer Name de la External Credential, sustituye `ICB_FirmaDigital_External` por ese nombre).
   - **Sequence Number:** `1` (o el que te deje por defecto).

3. **Save**.

Con esto, cuando se use la Named Credential que apunte a esta External Credential, Salesforce enviará el header `x-api-key` con el valor del parámetro `APIKey`.

---

## Paso 4: Crear la Named Credential

1. En **Setup → Named Credentials** abre la pestaña **Named Credentials** (no External Credentials).

---

## Buenas prácticas: header en Named Credential con fórmula

En muchos orgs los headers que se envían en el callout son los de la **Credencial nombrada**, no los de la Credencial externa. Para seguir buenas prácticas:

- **Dónde se guarda el API Key:** en la **External Credential** (rector → Parámetro de autenticación `APIKey`). Así se controla el acceso con Permission Set y se puede rotar la key sin tocar la Named Credential.
- **Dónde se define el header:** en la **Named Credential** → **Encabezados personalizados** → Nuevo.
  - **Nombre:** `x-api-key`
  - **Valor:** `{!$Credential.ICB_FirmaDigital_External.APIKey}` (fórmula que toma el valor del rector; no pongas aquí la key en texto plano).

Si el **Valor** del encabezado no acepta la fórmula, en la Named Credential activa **Permitir fórmulas en encabezado HTTP** (Allow formulas in HTTP header), guarda y vuelve a editar el encabezado para usar la fórmula.

Resumen: key solo en External Credential (rector); Named Credential solo referencia con `{!$Credential.ICB_FirmaDigital_External.APIKey}`.

---

Continuación **Paso 4** (crear la Named Credential):

2. Pulsa **New Named Credential**.

3. Completa:
   - **Label:** `ICB Firma Digital`
   - **Name (Developer Name):** `ICB_FirmaDigital`  
     (debe coincidir con la constante en `ICB_FirmaDigitalServiceImpl.cls`)
   - **URL:** según ambiente:
     - DEV: `https://integraciones-dev.icbfs.cl`
     - QA:  `https://integraciones-qa.icbfs.cl`
     (sin barra final)
   - **External Credential:** selecciona `ICB_FirmaDigital_External` (la creada en el paso 1).
   - **Generate Authorization Header:** desmarcado (la autenticación va por el custom header `x-api-key`).
   - Si vas a usar fórmula en el encabezado: **Permitir fórmulas en encabezado HTTP** marcado.

4. **Save**.

5. En la Named Credential creada, en **Encabezados personalizados** → **Nuevo**:
   - **Nombre:** `x-api-key`
   - **Valor:** `{!$Credential.ICB_FirmaDigital_External.APIKey}` (buena práctica: el valor vive en el rector).
6. **Save**.

---

## Paso 5: Asignar el Permission Set (si creaste uno nuevo)

Para que los usuarios/perfiles que ejecuten Apex o Flows que usen esta credencial puedan acceder a ella:

1. **Setup → Permission Sets** → abre el permission set (ej. `Firma Digital – API Access`).
2. **Manage Assignments** y asigna a los usuarios (o perfiles) que deban poder usar la integración Firma Digital.

---

## Paso 6: Remote Site (PUT a S3) — obligatorio

El **PUT del PDF** no usa la Named Credential; usa la **URL prefirmada** que devuelve el API (dominio S3). Si no añades este Remote Site, verás: *"Unauthorized endpoint, please check Setup->Security->Remote site settings"*.

1. **Setup → Security → Remote Site Settings → New Remote Site**
2. **Remote Site Name:** p. ej. `ICB_FirmaDigital_S3_QA`
3. **Remote Site URL:** debe coincidir con el host que devuelve el API. Por ejemplo:
   - **QA:** `https://icbfs-documents-qa.s3.us-east-1.amazonaws.com`  
     (incluye la región `us-east-1`; si el log muestra otro host, usa ese).
   - **PROD:** el que indique la documentación (p. ej. `https://icbfs-documents.s3.us-east-1.amazonaws.com`).
4. **Active:** marcado → **Save**.

Si el error sigue, revisa el log: el mensaje indica el `endpoint =` exacto; el Remote Site URL es solo **protocolo + host** (ej. `https://icbfs-documents-qa.s3.us-east-1.amazonaws.com`), sin path ni query.

---

## Resumen de nombres que usa el código

- **Named Credential Developer Name:** `ICB_FirmaDigital`  
  (constante `NAMED_CREDENTIAL` en `ICB_FirmaDigitalServiceImpl.cls`).

Si en tu org el flujo pide **Principal** en lugar de “Permission Set Mapping”, el equivalente es crear un **Named Principal** bajo la External Credential con el mismo parámetro `APIKey` y que la Named Credential use ese principal; la sintaxis del Custom Header sigue siendo `{!$Credential.ICB_FirmaDigital_External.APIKey}`.

---

## Comprobar

- Ejecutar un flujo o Apex que llame a `ICB_FirmaDigitalServiceImpl.solicitarUploadUrl(...)` con datos de prueba.
- Revisar que el request al API incluya el header `x-api-key` y que la respuesta sea 200 (o el código que espere tu ambiente). Si hay 403, revisar que el valor de la API Key en el Authentication Parameter coincida con el de API Gateway.
