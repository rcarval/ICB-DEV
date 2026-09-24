/**********************************************************************************
ICB Food Service
Desarrollado por: José Illanes
Fecha       : 2026-02-09
Descripción : Landing interno para QR. Obliga login (Salesforce core), registra scan
              reutilizando ICBFS_QrScanController y muestra “Bienvenido + Nombre”.
**********************************************************************************/
public with sharing class ICBFD_QR_LandingController {

    public String token { get; private set; }
    public String titulo { get; private set; }
    public String mensaje { get; private set; }
    public String resultado { get; private set; }

    public ICBFD_QR_LandingController() {
        token = ApexPages.currentPage().getParameters().get('token');

        if (String.isBlank(token)) {
            resultado = 'ERROR';
            titulo = 'Token faltante';
            mensaje = 'Falta token en la URL. Escanea nuevamente el QR.';
            return;
        }

        // 1) Buscar CampaignMember por token para armar bienvenida
        CampaignMember cm = null;
        List<CampaignMember> cms = [
            SELECT Id,
                   ContactId, Contact.Name,
                   LeadId, Lead.Name,
                   AccountId, Account.Name,
                   CampaignId, Campaign.Name
            FROM CampaignMember
            WHERE QR_Token__c = :token
            LIMIT 1
        ];
        if (!cms.isEmpty()) cm = cms[0];

        String nombre =
            (cm != null && cm.ContactId != null) ? cm.Contact.Name :
            (cm != null && cm.LeadId != null)    ? cm.Lead.Name :
            (cm != null && cm.AccountId != null) ? cm.Account.Name :
            'Participante';

        // 2) Reutilizar tu historial: registrar scan con tu controller existente (que llama el Flow)
        ICBFS_QrScanController.Resp resp = ICBFS_QrScanController.registrar(token);

        resultado = (resp != null && !String.isBlank(resp.resultado)) ? resp.resultado : 'OK';

        // 3) Mensaje final (Bienvenido + lo que venga del flow)
        titulo = 'Bienvenido, ' + nombre + ' 👋';

        String msgFlow = (resp != null) ? resp.mensaje : null;
        if (String.isBlank(msgFlow)) msgFlow = 'Escaneo procesado.';

        String camp = (cm != null && cm.CampaignId != null) ? cm.Campaign.Name : null;
        mensaje = msgFlow + (String.isBlank(camp) ? '' : (' • Campaña: ' + camp));
    }
}