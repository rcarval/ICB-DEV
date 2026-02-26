# Flujo Firma Digital desde Quote – Subir 1 PDF

Desde el registro de **Quote** un botón (Quick Action) abre un **Screen Flow** donde el usuario carga **1 y solo 1 documento PDF**. Ese PDF **no se guarda en Salesforce** (no se usa ContentVersion): se pasa en memoria (base64) al flujo y de ahí a la acción Apex, que lo envía a TuFirma y crea el registro en **Contrato_Digital__c**.

El flujo envía el PDF a TuFirma mediante **ICB_FirmaDigitalServiceImpl** y crea el registro en **Contrato_Digital__c** vinculado al Quote.

---

## 1. Flujo en XML (ya creado en el proyecto)

El flujo está en `force-app/main/default/flows/ICB_Subir_PDF_Firma_Digital.flow-meta.xml`:

- **Variable de entrada:** `varQuoteId` (Quote desde el que se lanza).
- **Variables de flujo:** `varPdfBase64` (String) y `varPdfFileName` (String): reciben el PDF en base64 y el nombre del archivo desde el componente de pantalla; **no se usa ContentVersion**.
- **Pantalla "Cargar documento PDF":** usa el componente **Subir PDF en memoria (Firma Digital)** (`c:flowPdfUploadMemory`), que expone `pdfBase64` y `pdfFileName`; el flujo los asigna a `varPdfBase64` y `varPdfFileName`.
- **Acción Apex:** "Enviar PDF Firma Digital" (`ICB_FirmaDigitalFlowAction`) recibe `varQuoteId`, `varPdfBase64` y `varPdfFileName`, envía el PDF a TuFirma y crea **Contrato_Digital__c**.
- **Pantalla "Archivo cargado":** mensaje de éxito.

**Si el flujo no aparece en el listado de Flows:** en **Setup** → **Flows**, usa el filtro **"Mostrar"** (o "Show") y elige **"Todos"** o **"Activos"** (el flujo se despliega como **Active**). Usa también el cuadro de búsqueda y escribe **"Subir"** o **"ICB_Subir"** o **"Firma Digital"**. Si aun así no lo ves, verifica en **Process Builder** (Setup → Process Builder) que no esté listado ahí por error.

---

## 1b. Si creas el flujo desde cero en la org (alternativa)

1. **Setup** → buscar **Flows** → **New Flow** → elegir **Screen Flow**.
2. **Guardar** el flujo con:
   - **Label:** `Subir PDF Firma Digital`
   - **API Name:** `ICB_Subir_PDF_Firma_Digital`  
   (debe coincidir con el nombre que usa la Quick Action en el proyecto).
3. **Input variable** (para recibir el Quote desde el botón):
   - **New Resource** → **Variable**
   - **Label:** Quote Id  
   - **API Name:** `varQuoteId`
   - **Data Type:** Text
   - **Available for input:** activado  
   - **Available for output:** desactivado  
   - Guardar.

4. **Pantalla 1 – Carga del PDF (en memoria, sin ContentVersion)**
   - Arrastra un elemento **Screen** al canvas.
   - **Label:** `Cargar documento PDF`
   - En la pantalla, agregar el componente **Subir PDF en memoria (Firma Digital)** (LWC flowPdfUploadMemory):
     - **File Upload** (estándar):
       - **Label:** “Seleccione un único archivo PDF”
       - **API Name:** En Outputs: pdfBase64 → varPdfBase64, pdfFileName → varPdfFileName.
       - **Allow multiple file upload:** desactivado (solo 1 archivo).
       - **Accepted file types:** elegir solo **PDF** (o escribir `.pdf` si hay campo de texto).
       - **Require file to continue:** activado.
     - Opcional: texto de ayuda indicando que solo se permite 1 PDF.
   - Conectar el **Start** del flujo a esta pantalla.

5. **Validación “solo 1 archivo”**  
   El componente File Upload con “Allow multiple” desactivado ya limita a 1 archivo en la UI. Si quieres validación extra:
   - Después de la pantalla, agrega una **Decision**:
     - **Condition:** si el número de elementos en la colección de archivos subidos es distinto de 1 → ir a una pantalla de error “Solo se permite un archivo PDF”.
     - Si es 1 → continuar.

6. **Pantalla final**
   - Añade otra **Screen** con un mensaje tipo: “Documento cargado correctamente. En una próxima versión se enviará a Firma Digital y se creará el registro en Contrato Digital.”
   - Conectar la pantalla de carga (o la decisión “éxito”) a esta pantalla final.
   - En la pantalla final, **Allow Finish** activado para que el usuario pueda cerrar el flujo.

7. **Guardar** y **Activate** el flujo.

---

## 2. Botón en Quote (Quick Action)

En el proyecto hay una **Quick Action** de tipo Flow que abre este flujo:

- **Objeto:** Quote  
- **Archivo:** `force-app/main/default/objects/Quote/quickActions/ICB_Subir_PDF_Firma_Digital.quickAction-meta.xml`  
- **Label (nombre visible):** Subir PDF Firma Digital  
- **API Name:** `ICB_Subir_PDF_Firma_Digital`

### Dónde ver que la Quick Action existe (después del deploy)

1. **Setup** (Configuración) → **Object Manager** → **Quote** (Cotización).
2. En el menú izquierdo: **Buttons, Links, and Actions** (Botones, vínculos y acciones).
3. En la lista busca **"Subir PDF Firma Digital"** o **"ICB_Subir_PDF_Firma_Digital"**.  
   - Si no aparece, el metadata no está desplegado: despliega la carpeta `objects/Quote/quickActions` (o todo el proyecto).

### Hacer que el botón aparezca en la página del registro Quote

**Solo con desplegar la Quick Action no se muestra en la ficha del Quote.** Hay que añadirla al layout o a la página Lightning:

- **Lightning (recomendado):**  
  1. **Setup** → **Object Manager** → **Quote** → **Lightning Record Pages**.  
  2. Abre la página que usan tus Quotes (o la por defecto).  
  3. Arrastra **Quick Actions** al área de botones (o edita la sección de acciones) y añade **Subir PDF Firma Digital**.  
  4. Guardar y activar.

- **Page Layout (Classic):**  
  1. **Setup** → **Object Manager** → **Quote** → **Page Layouts**.  
  2. Edita el layout que usan tus Quotes.  
  3. En **Mobile & Lightning Actions** (o **Salesforce Mobile and Lightning Experience Actions**) añade **Subir PDF Firma Digital** a las acciones.  
  4. Guardar.

Para que el flujo reciba el Quote actual:

1. En **Flow Builder**, en el **Start** del flujo, configura el **Input** `varQuoteId` como **Available for input**.
2. En **Setup** → **Object Manager** → **Quote** → **Buttons, Links, and Actions** → abre la Quick Action **Subir PDF Firma Digital** y asegúrate de que en **Flow Input** (o parámetros del flujo) se pase el **Record ID** del Quote al input `varQuoteId`.

Si creaste la Quick Action manualmente en la org:

1. **Setup** → **Object Manager** → **Quote** → **Buttons, Links, and Actions** → **New Action**.
2. **Action Type:** Flow  
3. **Flow:** Subir PDF Firma Digital (ICB_Subir_PDF_Firma_Digital)  
4. **Label:** Subir PDF Firma Digital  
5. **Name:** `ICB_Subir_PDF_Firma_Digital`  
6. Marcar **Pre-populate flow input variables with values from this record** y mapear el **Record ID** a `varQuoteId`.  
7. Guardar y añadir la acción al **Page Layout** de Quote.

---

## 3. Orden de despliegue

1. Crear y activar el flujo **ICB_Subir_PDF_Firma_Digital** en la org (o desplegar el flujo si lo tienes en metadata).
2. Desplegar la Quick Action de Quote (o crearla en la org como arriba).
3. Añadir la Quick Action al layout de Quote si no se añade por defecto.

---

## 4. Objeto Contrato_Digital__c

El objeto **Contrato_Digital__c** debe tener al menos estos campos (si en tu org tiene otros nombres, ajusta la clase `ICB_FirmaDigitalFlowAction`):

| Campo API | Tipo | Uso |
|-----------|------|-----|
| **Quote__c** | Lookup(Quote) | Cotización desde la que se envió el PDF. **Requerido** para vincular. |
| Estado__c | **Picklist** | El código usa los valores **"Enviado"** (éxito) y **"Error"** (fallo). El picklist debe incluir exactamente esos dos valores (o cambiar las constantes `ESTADO_ENVIADO` y `ESTADO_ERROR` en `ICB_FirmaDigitalFlowAction.cls`). |
| Contrato_ID__c | Texto | Identificador del contrato en TuFirma (upload response). |
| Documento_ID_TuFirma_del__c | Texto | ID del documento en TuFirma (se completa con GET status si el API lo devuelve). |
| URL_Firma__c | URL / Texto | URL de firma (desde status). |
| Firmante_Nombre__c | Texto | Nombre del Contact (firmante); lo rellena el código. |
| Firmante_Email__c | Email | Email del Contact; lo rellena el código. |
| Firmante_Telefono__c | Texto | Teléfono del firmante desde **Contact.MobilePhone**; lo rellena el código. |
| Fecha_Envio__c | Fecha/hora | Fecha de envío a TuFirma; lo rellena el código. |
| PDF_Original_URL__c | URL | URL del PDF original (si el API la devuelve). |
| PDF_Firmado_URL__c | URL | URL del PDF firmado (desde status o desde Platform Event). |
| Error_Message__c | Texto largo | Mensaje de error si falla el envío. |
| Fecha_Firma__c | Fecha/hora | Se rellena cuando llega el evento **DocumentoFirmado__e** (documento firmado en TuFirma). |
| Raw_Payload__c | Área de texto largo (32768) | Payload crudo del evento DocumentoFirmado__e (opcional). |

Cuando TuFirma notifica que el documento fue firmado, publica el Platform Event **DocumentoFirmado__e**. El trigger **DocumentoFirmadoTrigger** y el handler **ICB_DocumentoFirmadoTriggerHandler** actualizan el registro de Contrato_Digital__c (Estado__c, Documento_ID_TuFirma_del__c, Fecha_Firma__c, PDF_Firmado_URL__c, Raw_Payload__c). Ver **docs/PLATFORM_EVENT_DOCUMENTO_FIRMADO.md**.

Si el objeto ya existía sin lookup a Quote, crea el campo **Quote__c** (Lookup to Quote) para asociar cada contrato digital a la cotización.

---

## 5. Conectar el flujo con el servicio (acción invocable)

El flujo en metadata ya incluye la acción **Enviar PDF Firma Digital** (`ICB_FirmaDigitalFlowAction`). Si editas el flujo en Flow Builder:

1. **Action** "Enviar PDF a Firma Digital desde Quote": recibe **Quote Id** (`varQuoteId`), **PDF en base64** (`varPdfBase64`) y **Nombre del archivo PDF** (`varPdfFileName`). **No se usa Content Version**; el PDF viene del componente "Subir PDF en memoria".
2. **Variables de salida** (opcionales): **Éxito**, **Id Contrato Digital**, **Mensaje de error**; puedes asignarlas a variables del flujo para mostrar éxito/error o el Id del contrato.
3. **Conecta:** pantalla Cargar PDF → **Action** → (opcional) **Decision** (si éxito → pantalla Archivo cargado; si no → pantalla de error). O Action → directamente pantalla Archivo cargado.

Con esto, al seleccionar el PDF en la pantalla el flujo pasa el base64 a la acción, que llama a TuFirma (solicitar URL, subir PDF) y crea el registro en **Contrato_Digital__c** con **Quote__c** = Quote actual. El PDF **nunca se guarda en ContentVersion**.

---

## 6. Campos de Contrato_Digital__c que rellena el código

Tras el upload, el código:

- **Siempre rellena:** Estado__c, Contrato_ID__c, **Firmante_Nombre__c**, **Firmante_Email__c** (desde el Contact de la Quote), **Fecha_Envio__c** (fecha/hora actual).
- **Si la API de estado lo devuelve:** tras subir el PDF se llama a **GET /v1/firma/status/{contratoId}**; si TuFirma responde con datos, se completan **Documento_ID_TuFirma_del__c**, **URL_Firma__c**, **PDF_Firmado_URL__c** (y opcionalmente PDF_Original_URL__c). Si el backend aún no ha procesado el documento, estos campos pueden quedar vacíos hasta que TuFirma los exponga vía status o webhook.

**Email / WhatsApp:** el envío de la invitación a firmar (por correo o WhatsApp) lo hace el **backend de TuFirma**, no Salesforce. Si no te llega nada:

1. Confirmar con el equipo de TuFirma que en el ambiente **QA** se envían correos/SMS reales (a veces en QA están desactivados o usan un buzón de prueba).
2. Revisar si hace falta un paso adicional en el API para “disparar” el envío tras el upload.
3. Revisar bandeja de spam y que el email/teléfono del Contact sean los correctos.
