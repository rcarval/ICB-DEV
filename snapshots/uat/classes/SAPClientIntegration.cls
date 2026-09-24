public with sharing class SAPClientIntegration {

    public class ClienteRequest {
        @InvocableVariable(label='Account ID')
        public Id accountId;
        @InvocableVariable(label='Interfaz')
        public String interfaz;
        @InvocableVariable(label='Cliente')
        public String cliente;
        @InvocableVariable(label='GrupoCuentas')
        public String grupoCuentas;
        @InvocableVariable(label='Sociedad')
        public String sociedad;
        @InvocableVariable(label='OrgVentas')
        public String orgVentas;
        @InvocableVariable(label='Canal')
        public String canal;
        @InvocableVariable(label='Sector')
        public String sector;
        @InvocableVariable(label='Identificador')
        public String identificador;
        @InvocableVariable(label='Tratamiento')
        public String tratamiento;
        @InvocableVariable(label='Nombre')
        public String nombre;
        @InvocableVariable(label='NombreFantasia')
        public String nombreFantasia;
        @InvocableVariable(label='ConceptoBusqueda')
        public String conceptoBusqueda;
        @InvocableVariable(label='Calle')
        public String calle;
        @InvocableVariable(label='Distrito')
        public String distrito;
        @InvocableVariable(label='Poblacion')
        public String poblacion;
        @InvocableVariable(label='Pais')
        public String pais;
        @InvocableVariable(label='Region')
        public String region;
        @InvocableVariable(label='Idioma')
        public String idioma;
        @InvocableVariable(label='Telefono')
        public String telefono;
        @InvocableVariable(label='Celular')
        public String celular;
        @InvocableVariable(label='Fax')
        public String fax;
        @InvocableVariable(label='Email')
        public String email;
        @InvocableVariable(label='RamoControl')
        public String ramoControl;
        @InvocableVariable(label='NumIdentFiscal')
        public String numIdentFiscal;
        @InvocableVariable(label='PersonaFisica')
        public String personaFisica;
        @InvocableVariable(label='ImpVolNeg')
        public String impVolNeg;
        @InvocableVariable(label='RamoMkt')
        public String ramoMkt;
        @InvocableVariable(label='CodigoRamo')
        public String codigoRamo;
        @InvocableVariable(label='StatusJuridico')
        public String statusJuridico;
        @InvocableVariable(label='CuentaAsociada')
        public String cuentaAsociada;
        @InvocableVariable(label='ClaveClasific')
        public String claveClasific;
        @InvocableVariable(label='GrupoTesoreria')
        public String grupoTesoreria;
        @InvocableVariable(label='CondicionPago')
        public String condicionPago;
        @InvocableVariable(label='GrabaHistPago')
        public String grabaHistPago;
        @InvocableVariable(label='ProcedReclamo')
        public String procedReclamo;
        @InvocableVariable(label='ZonaVentas')
        public String zonaVentas;
        @InvocableVariable(label='OficinaVentas')
        public String oficinaVentas;
        @InvocableVariable(label='GrupoVendedores')
        public String grupoVendedores;
        @InvocableVariable(label='Rappel')
        public String rappel;
        @InvocableVariable(label='DetermPrecio')
        public String determPrecio;
        @InvocableVariable(label='CondPagoFact')
        public String condPagoFact;
        @InvocableVariable(label='Impuesto')
        public String impuesto;
        @InvocableVariable(label='AreaCtrlCred')
        public String areaCtrlCred;
        @InvocableVariable(label='LimiteCredito')
        public String limiteCredito;
        @InvocableVariable(label='ClaseRiesgo')
        public String claseRiesgo;
        @InvocableVariable(label='EquipoResponsable')
        public String equipoResponsable;
        @InvocableVariable(label='GrupoCredCliente')
        public String grupoCredCliente;
        @InvocableVariable(label='GrupoImputacion')
        public String grupoImputacion;
        @InvocableVariable(label='FechaFacturacion')
        public String fechaFacturacion;
        @InvocableVariable(label='FechaListaFactura')
        public String fechaListaFactura;
    }

    @InvocableMethod(label='Enviar Cliente a SAP y actualizar Respuesta_SAP')
    public static void enviarClientes(List<ClienteRequest> clientes) {
        List<Map<String, Object>> clientesAEnviar = new List<Map<String, Object>>();
        List<Id> accountIds = new List<Id>();

        // Preparar los datos para enviar a SAP
        for (ClienteRequest cliente : clientes) {
            Map<String, Object> clienteSAP = new Map<String, Object>();
            // clienteSAP.put('Interfaz', cliente.interfaz);
            clienteSAP.put('Cliente', cliente.cliente);
            clienteSAP.put('GrupoCuentas', cliente.grupoCuentas);
            clienteSAP.put('Sociedad', cliente.sociedad);
            clienteSAP.put('OrgVentas', cliente.orgVentas);
            clienteSAP.put('Canal', cliente.canal);
            clienteSAP.put('Sector', cliente.sector);
            clienteSAP.put('Identificador', cliente.identificador);
            clienteSAP.put('Tratamiento', cliente.tratamiento);
            clienteSAP.put('Nombre', cliente.nombre);
            clienteSAP.put('NombreFantasia', cliente.nombreFantasia);
            clienteSAP.put('ConceptoBusqueda', cliente.conceptoBusqueda);
            clienteSAP.put('Calle', cliente.calle);
            clienteSAP.put('Distrito', cliente.distrito);
            clienteSAP.put('Poblacion', cliente.poblacion);
            clienteSAP.put('Pais', cliente.pais);
            clienteSAP.put('Region', cliente.region);
            clienteSAP.put('Idioma', cliente.idioma);
            clienteSAP.put('Telefono', cliente.telefono);
            clienteSAP.put('Celular', cliente.celular);
            clienteSAP.put('Fax', cliente.fax);
            clienteSAP.put('Email', cliente.email);
            clienteSAP.put('RamoControl', cliente.ramoControl);
            clienteSAP.put('NumIdentFiscal', cliente.numIdentFiscal);
            clienteSAP.put('PersonaFisica', cliente.personaFisica);
            clienteSAP.put('ImpVolNeg', cliente.impVolNeg);
            clienteSAP.put('RamoMkt', cliente.ramoMkt);
            clienteSAP.put('CodigoRamo', cliente.codigoRamo);
            clienteSAP.put('StatusJuridico', cliente.statusJuridico);
            clienteSAP.put('CuentaAsociada', cliente.cuentaAsociada);
            clienteSAP.put('ClaveClasific', cliente.claveClasific);
            clienteSAP.put('GrupoTesoreria', cliente.grupoTesoreria);
            clienteSAP.put('CondicionPago', cliente.condicionPago);
            clienteSAP.put('GrabaHistPago', cliente.grabaHistPago);
            clienteSAP.put('ProcedReclamo', cliente.procedReclamo);
            clienteSAP.put('ZonaVentas', cliente.zonaVentas);
            clienteSAP.put('OficinaVentas', cliente.oficinaVentas);
            clienteSAP.put('GrupoVendedores', cliente.grupoVendedores);
            clienteSAP.put('Rappel', cliente.rappel);
            clienteSAP.put('DetermPrecio', cliente.determPrecio);
            clienteSAP.put('CondPagoFact', cliente.condPagoFact);
            clienteSAP.put('Impuesto', cliente.impuesto);
            clienteSAP.put('AreaCtrlCred', cliente.areaCtrlCred);
            clienteSAP.put('LimiteCredito', cliente.limiteCredito);
            clienteSAP.put('ClaseRiesgo', cliente.claseRiesgo);
            clienteSAP.put('EquipoResponsable', cliente.equipoResponsable);
            clienteSAP.put('GrupoCredCliente', cliente.grupoCredCliente);
            clienteSAP.put('GrupoImputacion', cliente.grupoImputacion);
            clienteSAP.put('FechaFacturacion', cliente.fechaFacturacion);
            clienteSAP.put('FechaListaFactura', cliente.fechaListaFactura);

            clientesAEnviar.add(clienteSAP);
            accountIds.add(cliente.accountId);
        }

        if (!clientesAEnviar.isEmpty()) {
            HttpRequest req = new HttpRequest();
            req.setEndpoint('https://integracion-salesforce-qa.icbfs.cl/clientes/v1/crear-cliente-completo'); // SBX
            req.setMethod('POST');
            req.setHeader('Content-Type', 'application/json');
            req.setHeader('x-api-key', 'URw2tdcKf9WSRM5hkGKi1CU4BW8lRzY49qUcUSGe'); // SBX
            req.setBody(JSON.serialize(new Map<String, Object>{
                'ClienteFacturadorSet' => clientesAEnviar
            }));

            Http http = new Http();
            HttpResponse res = http.send(req);

            if (res.getStatusCode() == 200) {
                // Parsear la respuesta JSON
                Map<String, Object> respuestaSAP = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
                String mensajeRespuesta = (String) respuestaSAP.get('message');

                // Actualizar el campo Respuesta_SAP en los registros de Account correspondientes
                List<Account> cuentasAActualizar = new List<Account>();
                for (Id accountId : accountIds) {
                    Account cuenta = [SELECT Id FROM Account WHERE Id = :accountId LIMIT 1];
                    cuenta.Respuesta_SAP__c = mensajeRespuesta;
                    cuentasAActualizar.add(cuenta);
                }

                if (!cuentasAActualizar.isEmpty()) {
                    update cuentasAActualizar;
                }
            } else {
                System.debug('Error al enviar datos a SAP: ' + res.getBody());
            }
        }
    }
}