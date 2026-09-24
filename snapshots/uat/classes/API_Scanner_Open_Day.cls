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
                       Campaign.Name,
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
                // Lead sin cuenta: se crea Account desde Company para cumplir el requisito de SF
                if (String.isNotBlank(cm.Lead.Company)) {
                    Account leadAccount = new Account(Name = cm.Lead.Company);
                    insert leadAccount;
                    oppAccountId = leadAccount.Id;
                }
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

                // 2) Crear Opportunity SOLO si hay cuenta (Account directa o desde Contact)
                Opportunity opp;
                if (oppAccountId != null) {
                    opp = new Opportunity();
                    opp.Name = req.varNombreOpp != null ? req.varNombreOpp : 'Oportunidad - ' + resp.varNombre + ' - ' + resp.varCampania;
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
                List<String> descripcionPartes = new List<String>();
                if (req.varValor != null && req.varValor > 0) {
                    descripcionPartes.add('Valor aproximado: $' + String.valueOf(req.varValor.setScale(0)));
                }
                if (String.isNotBlank(req.varDetalle)) {
                    descripcionPartes.add('Detalle: ' + req.varDetalle);
                }
                qrProd.Descripcion__c = descripcionPartes.isEmpty() ? null : String.join(descripcionPartes, '\n');
                qrProd.QR_Catalogo_producto__c = catalogoId;
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