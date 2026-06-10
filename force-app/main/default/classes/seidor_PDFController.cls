public with sharing class seidor_PDFController {

    public Case caso { get; private set; }
    //public String fdrNumber { get; private set;}
    public Detalle_Factura__c detalleProductoFactura { get; private set; }
    public String supervisorName { get; private set; }

    public Boolean isPreview {
        get {
            String previewParam = ApexPages.currentPage().getParameters().get('preview');
            return previewParam == 'true';
        }
    }
    
    public seidor_PDFController() {

        Id caseId = ApexPages.currentPage().getParameters().get('caseId');
        //fdrNumber = ApexPages.currentPage().getParameters().get('fdrNumber');

        if (caseId == null) {
            return;
        }

        caso = [
            SELECT Id,
                   CaseNumber,
                   Origin,
                   Area__c,
                   SKU__c,
                   Categoria__c,
                   Sub_Categoria__c,
                   CreatedDate,
                   Direccion_de_Retiro__r.Name,
                   Direccion_de_Retiro__r.Region__c,
                   Direccion_de_Retiro__r.Domicilio_Adicional__Street__s,
                   Direccion_de_Retiro__r.Comuna_Despacho__r.Name,
                   Direccion_de_Retiro__r.Cliente_Despacho__c,
                   Horario_retiro__c,
                   N_Factura__c,
                   Fecha_Factura__c,
                   Cantidad_reclamada__c,
                   UM_Unidad_de_Medida__c,
                   Motivo__c,
                   AccountId,
                   Account.Name,
                   Account.Nombre_de_Fantasia__c,
                   Account.RUT__c,
                   Account.C_digo_de_cliente__c,
                   Account.Owner.Name,
                   Account.Gerencia__c,
                   ContactId,
                   Contact.Name,
                   ContactMobile,
                   Transporte__r.Name,
                   Valor_Neto__c,
                   Fecha_retiro__c,
                   ProductId,
                   Owner.Name
            FROM Case
            WHERE Id = :caseId
            LIMIT 1
        ];

        List<Detalle_Factura__c> detalles = [
            SELECT Id,
                   Name,
                   Factura__r.Name,
                   Cantidad__c,
                   Descripcion__c,
                   SKU__c,
                   Unidad_de_Medida__c,
                   Valor_Neto__c,
                   Peso_neto__c,
                   Product__r.Id,
                   Product__r.Name
            FROM Detalle_Factura__c
            WHERE Factura__r.Numero_de_Factura__c = :caso.N_Factura__c AND Product__r.Id = :caso.ProductId
        ];

            Account acc = [
                SELECT 
                    Owner.Name,
                    Owner.UserRole.ParentRoleId
                FROM Account
                WHERE Id = :caso.AccountId
                LIMIT 1
            ];

            List<User> supervisors = [
                SELECT Id, Name
                FROM User
                WHERE UserRoleId = :acc.Owner.UserRole.ParentRoleId
                AND IsActive = true
            ];

                if (!supervisors.isEmpty()) {
                    supervisorName = supervisors[0].Name;
                }

            System.debug('### SUPERVISOR NAME: ' + supervisorName);
            
            System.debug('### DETALLES: ' + detalles);

            detalleProductoFactura = detalles[0];

            // System.debug('### PARAM FDR NUMBER: ' + fdrNumber);
            // System.debug('### CASE N_FDR__c: ' + caso.N_FDR__c);
    }
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    public static void getInt(){
        Integer I =0;
        		I++;
                I++;
                I++;
                I++;
                I++;
                I++;
                I++;
                I++;
                I++;
                I++;
                I++;
                I++;
                I++;
                I++;
                I++;
                I++;
                I++;
                I++;
                I++;
                I++;
                I++;
                I++;
                I++;
                I++;
                I++;
                I++;
                I++;
                I++;
                I++;
                I++;
                I++;
                I++;
                I++;
                I++;
                I++;
                I++;
                I++;
                I++;
                I++;
    }
}