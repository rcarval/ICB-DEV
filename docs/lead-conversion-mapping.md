# Mapeo post-conversion de Lead (flujo actual)

Fuente: `force-app/main/default/flows/LEAD_TRG_AfterUpdate.flow-meta.xml`.

## Disparo actual

- Tipo: Record-Triggered Flow (After Save).
- Objeto: `Lead`.
- Condicion: `IsConverted = true` y el registro debe haber cambiado para cumplir criterio.

## Lead -> Account (post-conversion)

El flujo actualiza la cuenta convertida (`$Record.ConvertedAccountId`) con:

- `BillingCity <- Lead.Direccion__City__s`
- `BillingCountry <- Lead.Direccion__CountryCode__s`
- `BillingPostalCode <- Lead.Direccion__PostalCode__s`
- `BillingStreet <- Lead.Direccion__Street__s`
- `Comuna_Facturaci_n__c <- Lead.Comunas__c`
- `Email__c <- Lead.Email`
- `Lead__c <- Lead.Id`
- `Nombre_de_contacto__c <- Lead.FirstName + ' ' + Lead.LastName`
- `ShippingCity <- Lead.Direccion_de_Despacho__City__s`
- `ShippingCountry <- Lead.Direccion_de_Despacho__CountryCode__s`
- `ShippingLatitude <- Lead.Direccion_de_Despacho__Latitude__s`
- `ShippingLongitude <- Lead.Direccion_de_Despacho__Longitude__s`
- `ShippingPostalCode <- Lead.Direccion_de_Despacho__PostalCode__s`
- `ShippingStreet <- Lead.Direccion_de_Despacho__Street__s`
- `Tipificaci_n_de_Origen__c <- Formula(Lead.LeadSource)`

Regla de formula para tipificacion:

- Si `LeadSource` es `Web Hablemos`, `Web Contactanos`, `Catalogo web` o `CCC`, mantiene ese valor.
- En otro caso asigna `Terreno`.

## Lead -> Contact (post-conversion)

El flujo actualiza el contacto convertido (`$Record.ConvertedContactId`) con:

- `MobilePhone <- Lead.Phone`

## Lead -> Lead (post-conversion)

El flujo actualiza el mismo lead con:

- `Account__c <- Lead.ConvertedAccountId`

## Ruta de correo

- Decision: si `Lead.RecordType.Name == 'Empresa'`.
- Accion: Email Alert `Account.Alerta_finanzas` usando `SObjectRowId = ConvertedAccountId`.

