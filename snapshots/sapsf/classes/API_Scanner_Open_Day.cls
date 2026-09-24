/**
 * API REST para la app externa de scanner Open Day
 * Reemplaza al Flow API_Scanner_Open_Day
 */
@RestResource(urlMapping='/scanner-open-day/*')
global with sharing class API_Scanner_Open_Day {

    // Inputs
    global class RequestBody {
        global String varToken;
        global String varAccion; // LOOKUP, SCAN, PRODUCTO
        global String varNombreOpp;
        global String varDetalle;
        global Decimal varValor;
    }

    // Outputs
    global class ResponseBody {
        global String varResultado;
        global String varMensaje;
        global String varNombre;
        global String varCampania;
        global String varEmail;
        global String varPhone;
        global String varEmpresa;
        global Boolean varEsReEscaneo;
        global String varCMId;
        global String varOppId;
        global String varStatus;
    }

    @HttpPost
    global static ResponseBody processRequest() {
        ResponseBody resp = new ResponseBody();
        resp.varEsReEscaneo = false;

        RequestBody req;
        try {
            String rawBody = RestContext.request != null && RestContext.request.requestBody != null
                ? RestContext.request.requestBody.toString()
                : null;
            req = String.isBlank(rawBody) ? new RequestBody() : (RequestBody) JSON.deserialize(rawBody, RequestBody.class);
        } catch (Exception ex) {
            resp.varResultado = 'ERROR';
            resp.varMensaje = 'Payload invalido: ' + ex.getMessage();
            return resp;
        }

        try {
            if (String.isBlank(req.varToken)) {
                resp.varResultado = 'ERROR';
                resp.varMensaje = 'Token es requerido';
                return resp;
            }

            // Query completa: traer Account de Contact y su Owner para la Opportunity
            CampaignMember cm = [
                SELECT Id, Status, CampaignId, ContactId, LeadId, AccountId, QR_Catalogo_producto__c,
                       Campaign.Name, Campaign.EndDate,
                       Contact.Name, Contact.Email, Contact.Phone, Contact.AccountId,
                       Contact.Account.Name, Contact.Account.OwnerId,
                       Lead.Name, Lead.Email, Lead.Phone, Lead.Company,
                       Account.Name, Account.OwnerId
                FROM CampaignMember
                WHERE QR_Token__c = :req.varToken
                LIMIT 1
            ];

            if (cm == null) {
                resp.varResultado = 'ERROR';
                resp.varMensaje = 'Token invalido o no encontrado';
                return resp;
            }

            String validationError = validarOperacion(cm);
            if (validationError != null) {
                resp.varResultado = 'ERROR';
                resp.varMensaje = validationError;
                return resp;
            }

            resp.varCMId = cm.Id;
            resp.varStatus = cm.Status;
            resp.varCampania = cm.Campaign.Name;

            // Determinar AccountId para la Opportunity (resuelve cuenta desde Contact como en QR_pantalla_se_accion)
            Id oppAccountId = cm.AccountId;
            Id accountOwnerId = null;

            if (cm.ContactId != null) {
                resp.varNombre = cm.Contact.Name;
                resp.varEmail = cm.Contact.Email;
                resp.varPhone = cm.Contact.Phone;
                if (cm.Contact.AccountId != null) {
                    resp.varEmpresa = cm.Contact.Account.Name;
                    oppAccountId = cm.Contact.AccountId;
                    accountOwnerId = cm.Contact.Account.OwnerId;
                }
            } else if (cm.LeadId != null) {
                resp.varNombre = cm.Lead.Name;
                resp.varEmail = cm.Lead.Email;
                resp.varPhone = cm.Lead.Phone;
                resp.varEmpresa = cm.Lead.Company;
            } else if (cm.AccountId != null) {
                resp.varNombre = cm.Account.Name;
                resp.varEmpresa = cm.Account.Name;
                resp.varPhone = null;
                accountOwnerId = cm.Account.OwnerId;
            }

            // Verificar re-escaneo usando QR_Scan__c (objeto del Flow QR_Registrar_Scan)
            List<QR_Scan__c> ultimoScan = [
                SELECT Id
                FROM QR_Scan__c
                WHERE Token__c = :req.varToken
                AND Resultado__c = 'OK'
                ORDER BY CreatedDate DESC
                LIMIT 1
            ];
            resp.varEsReEscaneo = !ultimoScan.isEmpty();

            if (String.isBlank(req.varAccion) || req.varAccion == 'LOOKUP') {
                resp.varResultado = 'OK';
                resp.varMensaje = 'Datos del asistente obtenidos';
            } else if (req.varAccion == 'SCAN') {
                registrarScan(cm, req.varToken);
                cm.Status = 'Responded';
                update cm;
                resp.varResultado = 'OK';
                resp.varMensaje = 'Asistencia registrada exitosamente';
            } else if (req.varAccion == 'PRODUCTO') {
                // 1) Crear/reusar catalogo en CampaignMember
                Id catalogoId = cm.QR_Catalogo_producto__c;
                if (catalogoId == null) {
                    QR_Catalogo_productos__c catalogo = new QR_Catalogo_productos__c();
                    catalogo.Name = 'Catalogo - ' + (resp.varNombre != null ? resp.varNombre : 'Asistente');
                    insert catalogo;
                    catalogoId = catalogo.Id;

                    cm.QR_Catalogo_producto__c = catalogoId;
                    update cm;
                }

                // Completar relaciones base del catalogo como en flows QR activos
                actualizarCatalogoContexto(catalogoId, cm, oppAccountId, null, req.varValor);

                // 2) Crear Opportunity SOLO si hay cuenta (Account directa o desde Contact)
                Opportunity opp;
                if (oppAccountId != null) {
                    opp = new Opportunity();
                    String nombreBaseOpp = String.isNotBlank(req.varNombreOpp)
                        ? req.varNombreOpp.trim()
                        : 'Oportunidad - ' + (resp.varNombre != null ? resp.varNombre : 'Asistente');
                    opp.Name = nombreBaseOpp + ' - ' + (resp.varCampania != null ? resp.varCampania : 'Sin Campana');
                    opp.CampaignId = cm.CampaignId;
                    opp.CloseDate = System.today().addDays(30);
                    opp.Description = req.varDetalle;
                    if (req.varValor != null && req.varValor > 0) {
                        opp.Amount = req.varValor;
                    }
                    opp.StageName = 'Generación de Propuesta';
                    opp.AccountId = oppAccountId;
                    if (accountOwnerId != null) {
                        opp.OwnerId = accountOwnerId;
                    }
                    insert opp;
                    resp.varOppId = opp.Id;

                }

                // 3) Crear ICBFS_QR_Producto__c siempre (si hay Opp, se relaciona)
                ICBFS_QR_Producto__c qrProd = new ICBFS_QR_Producto__c();
                qrProd.Name = req.varNombreOpp != null ? req.varNombreOpp : 'Producto';
                qrProd.Descripcion__c = String.isNotBlank(req.varDetalle) ? req.varDetalle : null;

                Map<String, Schema.SObjectField> prodFields = ICBFS_QR_Producto__c.SObjectType.getDescribe().fields.getMap();
                if (req.varValor != null && req.varValor > 0) {
                    for (String valorField : new List<String>{ 'Valor_Aproximado__c' }) {
                        if (prodFields.containsKey(valorField) && prodFields.get(valorField).getDescribe().isCreateable()) {
                            qrProd.put(valorField, req.varValor);
                            break;
                        }
                    }
                }
                qrProd.QR_Catalogo_producto__c = catalogoId;

                if (opp != null) {
                    for (String oppField : new List<String>{ 'Oportunidad__c', 'Opportunity__c' }) {
                        if (prodFields.containsKey(oppField) && prodFields.get(oppField).getDescribe().isCreateable()) {
                            qrProd.put(oppField, opp.Id);
                            break;
                        }
                    }
                }

                insert qrProd;

                resp.varResultado = 'OK';
                resp.varMensaje = opp != null
                    ? 'Oportunidad y producto creados exitosamente'
                    : 'Producto agregado al catálogo (sin oportunidad por falta de cuenta)';
            }

        } catch (Exception e) {
            resp.varResultado = 'ERROR';
            resp.varMensaje = 'Error: ' + e.getMessage();
        }

        return resp;
    }

    private static void actualizarCatalogoContexto(
        Id catalogoId,
        CampaignMember cm,
        Id accountId,
        Id oportunidadId,
        Decimal valorAAgregar
    ) {
        if (catalogoId == null) {
            return;
        }

        Map<String, Schema.SObjectField> fields = QR_Catalogo_productos__c.SObjectType.getDescribe().fields.getMap();
        QR_Catalogo_productos__c updateCatalogo = new QR_Catalogo_productos__c(Id = catalogoId);
        Boolean shouldUpdate = false;

        if (fields.containsKey('Campa_a__c') && fields.get('Campa_a__c').getDescribe().isUpdateable() && cm.CampaignId != null) {
            updateCatalogo.put('Campa_a__c', cm.CampaignId);
            shouldUpdate = true;
        }

        if (fields.containsKey('Contacto__c') && fields.get('Contacto__c').getDescribe().isUpdateable() && cm.ContactId != null) {
            updateCatalogo.put('Contacto__c', cm.ContactId);
            shouldUpdate = true;
        }

        if (fields.containsKey('Candidato__c') && fields.get('Candidato__c').getDescribe().isUpdateable() && cm.LeadId != null) {
            updateCatalogo.put('Candidato__c', cm.LeadId);
            shouldUpdate = true;
        }

        if (fields.containsKey('Cliente__c') && fields.get('Cliente__c').getDescribe().isUpdateable() && accountId != null) {
            updateCatalogo.put('Cliente__c', accountId);
            shouldUpdate = true;
        }

        if (fields.containsKey('Oportunidad__c') && fields.get('Oportunidad__c').getDescribe().isUpdateable() && oportunidadId != null) {
            updateCatalogo.put('Oportunidad__c', oportunidadId);
            shouldUpdate = true;
        }

        if (valorAAgregar != null && valorAAgregar > 0) {
            String valorField = null;
            for (String candidate : new List<String>{ 'Valor_de_Catalogo__c', 'Valor_Catalogo__c' }) {
                if (fields.containsKey(candidate) && fields.get(candidate).getDescribe().isUpdateable()) {
                    valorField = candidate;
                    break;
                }
            }

            if (valorField != null) {
                Decimal valorActual = 0;
                List<SObject> rows = Database.query(
                    'SELECT ' + valorField + ' FROM QR_Catalogo_productos__c WHERE Id = :catalogoId LIMIT 1'
                );
                if (!rows.isEmpty()) {
                    Object raw = rows[0].get(valorField);
                    if (raw != null) {
                        valorActual = (Decimal) raw;
                    }
                }
                updateCatalogo.put(valorField, valorActual + valorAAgregar);
                shouldUpdate = true;
            }
        }

        if (shouldUpdate) {
            update updateCatalogo;
        }
    }

    private static String validarOperacion(CampaignMember cm) {
        if (cm == null || cm.CampaignId == null) {
            return 'No hay campaña activa para escanear.';
        }

        Map<String, Schema.SObjectType> gd = Schema.getGlobalDescribe();
        if (!gd.containsKey('Campaign')) {
            return null;
        }

        Id campaignId = cm.CampaignId;
        Map<String, Schema.SObjectField> campaignFields = Campaign.SObjectType.getDescribe().fields.getMap();
        if (campaignFields.containsKey('QR_Activo__c')) {
            List<SObject> rows = Database.query(
                'SELECT QR_Activo__c, EndDate FROM Campaign WHERE Id = :campaignId LIMIT 1'
            );
            if (rows.isEmpty()) {
                return 'No hay campañas activas para escanear.';
            }

            SObject camp = rows[0];
            Boolean qrActivo = (Boolean) camp.get('QR_Activo__c');
            if (qrActivo == false) {
                return 'No hay campañas activas para escanear. Último evento fue: ' + (cm.Campaign != null ? cm.Campaign.Name : 'Open Day');
            }

            Date endDate = (Date) camp.get('EndDate');
            if (endDate != null && Date.today() > endDate.addDays(1)) {
                return 'No hay campañas activas para escanear. Último evento fue: ' + (cm.Campaign != null ? cm.Campaign.Name : 'Open Day');
            }
        }

        if (!gd.containsKey('QR_Evento_Usuario__c')) {
            return 'Falta configuración de staff del evento. Contacta al administrador.';
        }

        Schema.SObjectType staffType = gd.get('QR_Evento_Usuario__c');
        Map<String, Schema.SObjectField> staffFields = staffType.getDescribe().fields.getMap();
        if (!staffFields.containsKey('Campaign__c') || !staffFields.containsKey('Usuario__c')) {
            return null;
        }

        Id currentUserId = UserInfo.getUserId();
        String staffQuery =
            'SELECT Id FROM QR_Evento_Usuario__c WHERE Campaign__c = :campaignId AND Usuario__c = :currentUserId';
        if (staffFields.containsKey('Activo__c')) {
            staffQuery += ' AND Activo__c = true';
        }
        staffQuery += ' LIMIT 1';

        List<SObject> staffRows = Database.query(staffQuery);
        if (staffRows.isEmpty()) {
            return 'Tu usuario no está autorizado como staff en este Open Day.';
        }

        return null;
    }

    // Simula el subflow QR_Registrar_Scan usando el objeto QR_Scan__c del Flow
    private static void registrarScan(CampaignMember cm, String token) {
        try {
            QR_Scan__c scan = new QR_Scan__c();
            scan.Campa_a__c = cm.CampaignId;
            scan.CampaignMemberId__c = cm.Id;
            scan.Fecha_Hora__c = System.now();
            scan.Resultado__c = 'OK';
            scan.Scan_Usuario__c = UserInfo.getUserId();
            scan.Token__c = token;
            if (cm.ContactId != null) {
                scan.Contacto__c = cm.ContactId;
            } else if (cm.LeadId != null) {
                scan.Prospecto__c = cm.LeadId;
            } else if (cm.AccountId != null) {
                scan.Cliente__c = cm.AccountId;
            }
            insert scan;
        } catch (Exception e) {
            System.debug('Error al registrar scan: ' + e.getMessage());
        }
    }
}