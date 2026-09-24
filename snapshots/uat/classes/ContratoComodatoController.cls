public with sharing class ContratoComodatoController {
    public Id opportunityId { get; set; }

    public String ciudadContrato {
        get { return 'Santiago'; }
    }
    public String razonSocialICB {
        get { return 'Importadora y Alimentos ICB Food Service Ltda.'; }
    }
    public String rutICB {
        get { return '77.965.620-9'; }
    }

    public String fechaContrato { get; private set; }
    public String fechaContratoLarga { get; private set; }
    public Opportunity opp { get; private set; }
    public Contact representanteLegal { get; private set; }
    public Contact contactoComercial { get; private set; }
    public Product2 maquina { get; private set; }
    public String tipoDeNegocio { get; private set; }
    public String direccionDespacho { get; private set; }
    public List<LineaEquipo> lineasMaquina { get; private set; }
    public List<LineaEquipo> lineasAccesorios { get; private set; }
    public List<LineaEquipo> lineasUbicacion { get; private set; }
    public List<LineaCondicionComercial> lineasCondicionesComerciales { get; private set; }

    private static final List<String> MESES = new List<String>{
        'enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio',
        'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre'
    };

    public ContratoComodatoController() {
        PageReference pg = ApexPages.currentPage();
        if (pg != null && pg.getParameters().containsKey('opportunityId')) {
            String oid = pg.getParameters().get('opportunityId');
            if (String.isNotBlank(oid)) {
                opportunityId = Id.valueOf(oid);
                loadData();
            }
        }
    }

    @TestVisible
    private void loadData() {
        Date hoy = Date.today();
        fechaContrato = hoy.format();
        fechaContratoLarga = String.valueOf(hoy.day()) + ' de ' + MESES.get(hoy.month() - 1) + ' de ' + String.valueOf(hoy.year());

        lineasMaquina = new List<LineaEquipo>();
        lineasAccesorios = new List<LineaEquipo>();
        lineasUbicacion = new List<LineaEquipo>();
        lineasCondicionesComerciales = new List<LineaCondicionComercial>();

        List<Opportunity> opps = [
            SELECT Id, Name, Owner.Name,
                   Account.Name, Account.RUT__c, Account.C_digo_de_cliente__c, Account.Nombre_de_Fantasia__c,
                   Account.Negocio_Gastronomico__r.Tipo_de_Empresa__c,
                   Account.Negocio_Gastronomico__r.Direcci_n_de_Despacho__c
            FROM Opportunity
            WHERE Id = :opportunityId
            LIMIT 1
        ];
        if (opps.isEmpty()) {
            return;
        }
        opp = opps[0];

        tipoDeNegocio = (opp.Account != null && opp.Account.Negocio_Gastronomico__r != null)
            ? opp.Account.Negocio_Gastronomico__r.Tipo_de_Empresa__c
            : null;
        if (String.isBlank(tipoDeNegocio)) {
            tipoDeNegocio = 'No informado';
        }

        Address despacho = (opp.Account != null && opp.Account.Negocio_Gastronomico__r != null)
            ? opp.Account.Negocio_Gastronomico__r.Direcci_n_de_Despacho__c
            : null;
        direccionDespacho = formatAddress(despacho);

        representanteLegal = obtenerRepresentanteLegal(opportunityId);
        contactoComercial = obtenerContactoComercial(opportunityId, representanteLegal);

        List<QuoteLineItem> lineas = [
            SELECT Product2Id, Product2.Name, Product2.Codigo__c, Product2.Precio_de_Lista__c,
                   Product2.Metodologia__c, Product2.Tag__c, Product2.Capacidad_Sugerida__c
            FROM QuoteLineItem
            WHERE Quote.OpportunityId = :opportunityId
            ORDER BY Quote.CreatedDate DESC, Id ASC
        ];

        for (QuoteLineItem li : lineas) {
            if (li.Product2.Capacidad_Sugerida__c != null || li.Product2.Metodologia__c != null) {
                maquina = li.Product2;
                break;
            }
        }

        if (maquina == null) {
            return;
        }

        LineaEquipo lineaMaquina = new LineaEquipo(maquina);
        lineasMaquina.add(lineaMaquina);
        lineasUbicacion.add(lineaMaquina.conDireccion(direccionDespacho));

        List<Comodato__c> comodatos = [
            SELECT Producto_Asociado__r.Name, Producto_Asociado__r.Codigo__c,
                   Cantidad_Aporte__c, Cantidad_Minima_Mensual__c,
                   Precio_Unitario_Neto__c, Tipo_de_Asociacion__c, Unidad_de_Medida__c
            FROM Comodato__c
            WHERE Maquina__c = :maquina.Id AND Producto_Asociado__c != null
        ];

        for (Comodato__c c : comodatos) {
            LineaEquipo lineaAccesorio = new LineaEquipo(c);
            lineasAccesorios.add(lineaAccesorio);
            lineasUbicacion.add(lineaAccesorio.conDireccion(direccionDespacho));
            if (c.Tipo_de_Asociacion__c == 'Insumo Mensual') {
                lineasCondicionesComerciales.add(new LineaCondicionComercial(c));
            }
        }
    }

    // Representante Legal: reusa el mismo criterio de busqueda que
    // ICB_FirmaDigitalFlowAction.obtenerRepresentanteLegal, pero sin
    // exigir RUT/movil/correo completos (aqui solo se arma el
    // contrato; la validacion dura de esos datos la sigue haciendo
    // ICB_FirmaDigitalPrecheckAction antes de enviar a firma).
    private static Contact obtenerRepresentanteLegal(Id oppId) {
        if (oppId == null) {
            return null;
        }
        List<OpportunityContactRole> roles = [
            SELECT Role, Contact.Id, Contact.Name, Contact.Email, Contact.MobilePhone,
                   Contact.RUT__c, Contact.RUT_Contacto__c
            FROM OpportunityContactRole
            WHERE OpportunityId = :oppId AND ContactId != null AND IsDeleted = false
            ORDER BY IsPrimary DESC, CreatedDate ASC
        ];
        for (OpportunityContactRole r : roles) {
            if (r.Role != null && r.Role.toLowerCase().contains('representante legal') && r.Contact != null) {
                return r.Contact;
            }
        }
        for (OpportunityContactRole r : roles) {
            if (r.Contact != null) {
                return r.Contact;
            }
        }
        return null;
    }

    private static Contact obtenerContactoComercial(Id oppId, Contact representante) {
        if (oppId == null) {
            return representante;
        }
        List<OpportunityContactRole> roles = [
            SELECT Role, IsPrimary, Contact.Id, Contact.Name, Contact.Email, Contact.MobilePhone,
                   Contact.RUT__c, Contact.RUT_Contacto__c
            FROM OpportunityContactRole
            WHERE OpportunityId = :oppId AND ContactId != null AND IsDeleted = false
            ORDER BY IsPrimary DESC, CreatedDate ASC
        ];

        for (OpportunityContactRole r : roles) {
            if (r.Contact == null) {
                continue;
            }
            if (representante != null && r.Contact.Id == representante.Id) {
                continue;
            }
            String role = r.Role != null ? r.Role.toLowerCase() : '';
            if (role.contains('comercial') || role.contains('contacto') || role.contains('comprador')) {
                return r.Contact;
            }
        }

        for (OpportunityContactRole r : roles) {
            if (r.Contact == null) {
                continue;
            }
            if (representante != null && r.Contact.Id == representante.Id) {
                continue;
            }
            return r.Contact;
        }
        return representante;
    }

    private static String formatAddress(Address addr) {
        if (addr == null) {
            return 'No informado';
        }
        List<String> parts = new List<String>();
        if (String.isNotBlank(addr.getStreet())) {
            parts.add(addr.getStreet());
        }
        if (String.isNotBlank(addr.getCity())) {
            parts.add(addr.getCity());
        }
        if (String.isNotBlank(addr.getStateCode())) {
            parts.add(addr.getStateCode());
        }
        return parts.isEmpty() ? 'No informado' : String.join(parts, ', ');
    }

    private static String formatCLP(Decimal amount) {
        Long intPart = amount.setScale(0).longValue();
        String s = String.valueOf(intPart);
        String result = '';
        Integer cnt = 0;
        for (Integer i = s.length() - 1; i >= 0; i--) {
            if (cnt > 0 && Math.mod(cnt, 3) == 0) {
                result = '.' + result;
            }
            result = s.substring(i, i + 1) + result;
            cnt++;
        }
        return '$' + result;
    }

    // Fila de las tablas "Equipos" y "Accesorios" (Bloque B) y de la
    // tabla de "Ubicacion" (Bloque C, agregando direccionDespacho).
    public class LineaEquipo {
        public String cantidad { get; private set; }
        public String codigo { get; private set; }
        public String numeroSerie { get; private set; }
        public String descripcion { get; private set; }
        public String tipoDeEquipo { get; private set; }
        public String valorLista { get; private set; }
        public String direccionDespacho { get; private set; }

        // La maquina principal (no tiene registro Comodato__c propio,
        // es el Product2 referenciado como Maquina__c por los demas).
        public LineaEquipo(Product2 m) {
            this.cantidad = '1';
            this.codigo = m.Codigo__c;
            this.numeroSerie = 'A completar en instalación';
            this.descripcion = m.Name;
            String metodologia = String.isNotBlank(m.Metodologia__c) ? m.Metodologia__c : '';
            String tag = String.isNotBlank(m.Tag__c) ? m.Tag__c : '';
            if (String.isNotBlank(metodologia) && String.isNotBlank(tag)) {
                this.tipoDeEquipo = metodologia + ' - ' + tag;
            } else if (String.isNotBlank(metodologia)) {
                this.tipoDeEquipo = metodologia;
            } else if (String.isNotBlank(tag)) {
                this.tipoDeEquipo = tag;
            } else {
                this.tipoDeEquipo = 'No informado';
            }
            this.valorLista = m.Precio_de_Lista__c != null ? formatCLP(m.Precio_de_Lista__c) : 'No informado';
        }

        // Accesorios / consumibles / servicios asociados a la maquina.
        public LineaEquipo(Comodato__c c) {
            Decimal cant = (c.Tipo_de_Asociacion__c == 'Aporte de Marca')
                ? c.Cantidad_Aporte__c
                : c.Cantidad_Minima_Mensual__c;
            this.cantidad = cant != null ? String.valueOf(cant.setScale(0)) : '1';
            this.codigo = c.Producto_Asociado__r != null ? c.Producto_Asociado__r.Codigo__c : null;
            this.numeroSerie = '-';
            this.descripcion = c.Producto_Asociado__r != null ? c.Producto_Asociado__r.Name : '';
            this.tipoDeEquipo = c.Tipo_de_Asociacion__c;
            this.valorLista = c.Precio_Unitario_Neto__c != null ? formatCLP(c.Precio_Unitario_Neto__c) : 'No informado';
        }

        public LineaEquipo conDireccion(String direccion) {
            this.direccionDespacho = direccion;
            return this;
        }
    }

    // Fila de la tabla "Condiciones comerciales" (Bloque D) - solo
    // filas Comodato__c con Tipo_de_Asociacion__c = 'Insumo Mensual'.
    public class LineaCondicionComercial {
        public String productoAsociado { get; private set; }
        public String consumoMinimoMensual { get; private set; }
        public String precioAcordado { get; private set; }
        public String politicaDePrecios { get; private set; }

        public LineaCondicionComercial(Comodato__c c) {
            this.productoAsociado = c.Producto_Asociado__r != null ? c.Producto_Asociado__r.Name : '';
            Decimal cant = c.Cantidad_Minima_Mensual__c != null ? c.Cantidad_Minima_Mensual__c : 0;
            String uom = c.Unidad_de_Medida__c != null ? c.Unidad_de_Medida__c : '';
            this.consumoMinimoMensual = String.valueOf(cant.setScale(0)) + ' ' + uom;
            Decimal precio = c.Precio_Unitario_Neto__c != null ? c.Precio_Unitario_Neto__c : 0;
            this.precioAcordado = formatCLP(precio);
            // Pendiente de definicion de negocio (matriz de campos, punto D):
            // se deja "Revisión anual" como valor por defecto hasta contar con
            // un campo/regla propia.
            this.politicaDePrecios = 'Revisión anual';
        }
    }
}