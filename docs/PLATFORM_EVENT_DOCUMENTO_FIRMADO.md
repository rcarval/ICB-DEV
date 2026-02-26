# Platform Event DocumentoFirmado__e y actualización de Contrato_Digital__c

Cuando TuFirma notifica que un documento fue firmado, publica un **Platform Event** `DocumentoFirmado__e`. Un trigger actualiza el registro de **Contrato_Digital__c** que coincida por `Contrato_ID__c`.

## Evento DocumentoFirmado__e

| Campo (API) | Tipo | Uso |
|-------------|------|-----|
| ContratoId__c | Texto(100) | Identificador del contrato (debe coincidir con Contrato_Digital__c.Contrato_ID__c). |
| Estado__c | Texto(50) | Estado del documento (ej. Firmado). |
| ExternalTransactionId__c | Texto(100) | Se guarda en Documento_ID_TuFirma_del__c. |
| FechaFirma__c | Fecha/hora | Se guarda en Fecha_Firma__c. |
| PdfFirmadoUrl__c | Texto(255) | Se guarda en PDF_Firmado_URL__c. |
| RawPayload__c | Área de texto largo(32768) | Se guarda en Raw_Payload__c (truncado a 32768 si viene más largo). |

## Componentes

- **Trigger:** `DocumentoFirmadoTrigger` en `DocumentoFirmado__e` (after insert).
- **Handler:** `ICB_DocumentoFirmadoTriggerHandler.onAfterInsert(List<DocumentoFirmado__e>)`.

El handler busca `Contrato_Digital__c` con `Contrato_ID__c` igual a `ContratoId__c` del evento y actualiza: Estado__c, Documento_ID_TuFirma_del__c, Fecha_Firma__c, PDF_Firmado_URL__c, Raw_Payload__c. Si no hay registro coincidente, el evento se ignora.

## Campos requeridos en Contrato_Digital__c

Además de los ya usados por el flujo de envío (Estado__c, Contrato_ID__c, Documento_ID_TuFirma_del__c, PDF_Firmado_URL__c, etc.), el objeto debe tener:

| Campo API | Tipo | Uso |
|-----------|------|-----|
| Fecha_Firma__c | Fecha/hora | Fecha en que se firmó (desde el evento). |
| Raw_Payload__c | Área de texto largo (32768) | Payload crudo del evento (opcional; si no existe, crear el campo o quitar su uso en el handler). |

Si en tu org **Contrato_Digital__c** no tiene `Fecha_Firma__c` ni `Raw_Payload__c`, créalos en Object Manager o elimina/ajusta en el handler las líneas que los asignan.

## Tests

`ICB_DocumentoFirmadoTriggerHandler_Test` crea un `Contrato_Digital__c` con `Contrato_ID__c = 'FD-PE-TEST-001'`, invoca el handler con un evento con ese `ContratoId__c` y comprueba que el registro se actualiza. Para ejecutar los tests hace falta que el objeto tenga los campos indicados arriba.
