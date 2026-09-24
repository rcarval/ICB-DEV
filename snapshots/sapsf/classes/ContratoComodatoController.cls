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

    // Multi-máquina: secciones por máquina
    public List<SeccionMaquina> seccionesMaquinas { get; private set; }
    public Boolean esMultiMaquina { get; private set; }

    private static final List<String> MESES = new List<String>{
        'enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio',
        'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre'
    };

    /**
     * Quote que define que ajustes aplican. La informa GenerarContratoComodatoAction, que es
     * la misma que se envia a firma digital y queda en Contrato_Digital__c.Presupuesto__c.
     * Si no viene, se cae al comportamiento anterior (la Quote mas reciente de la Opp).
     */
    @TestVisible
    private Id quoteIdParam;

    public ContratoComodatoController() {
        PageReference pg = ApexPages.currentPage();
        if (pg != null && pg.getParameters().containsKey('opportunityId')) {
            String oid = pg.getParameters().get('opportunityId');
            String qid = pg.getParameters().get('quoteId');
            if (String.isNotBlank(qid)) {
                quoteIdParam = Id.valueOf(qid);
            }
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
            SELECT QuoteId, Product2Id, Product2.Name, Product2.Codigo__c, Product2.Precio_de_Lista__c,
                   Product2.Metodologia__c, Product2.Tag__c, Product2.Capacidad_Sugerida__c,
                   Quantity
            FROM QuoteLineItem
            WHERE Quote.OpportunityId = :opportunityId
            ORDER BY Quote.CreatedDate DESC, Id ASC
        ];

        // Quote de contexto: la que informa la accion (la que se firma). Solo si no viene se
        // usa la mas reciente, que es el comportamiento anterior.
        Id quoteId = quoteIdParam != null
            ? quoteIdParam
            : (lineas.isEmpty() ? null : lineas[0].QuoteId);

        // Identificar TODAS las máquinas (tienen Metodologia o Capacidad o Tipo_Equipo)
        List<Product2> maquinas = new List<Product2>();
        Map<Id, Integer> maquinaQuantities = new Map<Id, Integer>();
        for (QuoteLineItem li : lineas) {
            if (li.Product2.Capacidad_Sugerida__c != null || li.Product2.Metodologia__c != null) {
                if (!maquinaQuantities.containsKey(li.Product2Id)) {
                    maquinas.add(li.Product2);
                    maquinaQuantities.put(li.Product2Id, Integer.valueOf(li.Quantity));
                } else {
                    maquinaQuantities.put(li.Product2Id, maquinaQuantities.get(li.Product2Id) + Integer.valueOf(li.Quantity));
                }
            }
        }

        esMultiMaquina = maquinas.size() > 1;

        if (maquinas.isEmpty()) {
            return;
        }

        // Para compatibilidad con el formato single, usar la primera
        maquina = maquinas[0];

        // Lineas YA RESUELTAS contra la Quote: el contrato que se firma muestra exactamente
        // los mismos valores que el PDF de la propuesta y que el payload enviado a SAP.
        Set<Id> maquinaIds = maquinaQuantities.keySet();
        List<ComodatoOverrideResolver.LineaResuelta> todosComodatos =
            ComodatoOverrideResolver.resolver(maquinaIds, quoteId);

        // Agrupar comodatos por máquina
        Map<Id, List<ComodatoOverrideResolver.LineaResuelta>> comodatosByMaquina =
            new Map<Id, List<ComodatoOverrideResolver.LineaResuelta>>();
        for (ComodatoOverrideResolver.LineaResuelta c : todosComodatos) {
            if (c.productoAsociadoId == null) {
                continue;
            }
            if (!comodatosByMaquina.containsKey(c.maquinaId)) {
                comodatosByMaquina.put(c.maquinaId, new List<ComodatoOverrideResolver.LineaResuelta>());
            }
            comodatosByMaquina.get(c.maquinaId).add(c);
        }

        // Construir secciones por máquina
        seccionesMaquinas = new List<SeccionMaquina>();
        for (Product2 m : maquinas) {
            Integer qty = maquinaQuantities.get(m.Id);
            List<ComodatoOverrideResolver.LineaResuelta> comodatos = comodatosByMaquina.containsKey(m.Id)
                ? comodatosByMaquina.get(m.Id)
                : new List<ComodatoOverrideResolver.LineaResuelta>();
            seccionesMaquinas.add(new SeccionMaquina(m, qty, comodatos, direccionDespacho));
        }

        // Mantener listas planas para compatibilidad con formato single
        LineaEquipo lineaMaquina = new LineaEquipo(maquina);
        lineasMaquina.add(lineaMaquina);
        lineasUbicacion.add(lineaMaquina.conDireccion(direccionDespacho));

        List<ComodatoOverrideResolver.LineaResuelta> comodatosPrimera = comodatosByMaquina.containsKey(maquina.Id)
            ? comodatosByMaquina.get(maquina.Id)
            : new List<ComodatoOverrideResolver.LineaResuelta>();

        for (ComodatoOverrideResolver.LineaResuelta c : comodatosPrimera) {
            LineaEquipo lineaAccesorio = new LineaEquipo(c);
            lineasAccesorios.add(lineaAccesorio);
            lineasUbicacion.add(lineaAccesorio.conDireccion(direccionDespacho));
            if (c.tipoDeAsociacion == 'Insumo Mensual') {
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
        public LineaEquipo(ComodatoOverrideResolver.LineaResuelta c) {
            Decimal cant = (c.tipoDeAsociacion == 'Aporte de Marca')
                ? c.cantidadAporte
                : c.cantidadMinimaMensual;
            this.cantidad = cant != null ? String.valueOf(cant.setScale(0)) : '1';
            this.codigo = c.productoAsociadoCodigo;
            this.numeroSerie = '-';
            this.descripcion = c.productoAsociadoNombre != null ? c.productoAsociadoNombre : '';
            this.tipoDeEquipo = c.tipoDeAsociacion;
            this.valorLista = c.precioUnitarioNeto != null ? formatCLP(c.precioUnitarioNeto) : 'No informado';
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

        public LineaCondicionComercial(ComodatoOverrideResolver.LineaResuelta c) {
            this.productoAsociado = c.productoAsociadoNombre != null ? c.productoAsociadoNombre : '';
            Decimal cant = c.cantidadMinimaMensual != null ? c.cantidadMinimaMensual : 0;
            String uom = c.unidadDeMedida != null ? c.unidadDeMedida : '';
            this.consumoMinimoMensual = String.valueOf(cant.setScale(0)) + ' ' + uom;
            Decimal precio = c.precioUnitarioNeto != null ? c.precioUnitarioNeto : 0;
            this.precioAcordado = formatCLP(precio);
            // Pendiente de definicion de negocio (matriz de campos, punto D):
            // se deja "Revisión anual" como valor por defecto hasta contar con
            // un campo/regla propia.
            this.politicaDePrecios = 'Revisión anual';
        }
    }

    // Sección multi-máquina: agrupa equipos, accesorios, ubicación y
    // condiciones comerciales por cada máquina distinta.
    public class SeccionMaquina {
        public String nombreMaquina { get; private set; }
        public Integer cantidad { get; private set; }
        public String cantidadLabel { get; private set; }
        public List<LineaEquipo> equipos { get; private set; }
        public List<LineaEquipo> accesorios { get; private set; }
        public List<LineaEquipo> ubicacion { get; private set; }
        public List<LineaCondicionComercial> condiciones { get; private set; }

        // Código y valor lista de la máquina principal de esta sección
        // (misma máquina que equipos[0]), para no indexar equipos[0] desde el markup VF.
        public String codigoMaquina { get; private set; }
        public String valorListaMaquina { get; private set; }

        public SeccionMaquina(Product2 m, Integer qty, List<ComodatoOverrideResolver.LineaResuelta> comodatos, String direccion) {
            this.nombreMaquina = m.Name;
            this.cantidad = qty;
            this.cantidadLabel = qty > 1 ? '(x' + qty + ' unidades)' : '';
            this.equipos = new List<LineaEquipo>();
            this.accesorios = new List<LineaEquipo>();
            this.ubicacion = new List<LineaEquipo>();
            this.condiciones = new List<LineaCondicionComercial>();

            // Línea de la máquina
            LineaEquipo lineaMaq = new LineaEquipo(m);
            lineaMaq.cantidad = String.valueOf(qty);
            this.equipos.add(lineaMaq);
            this.ubicacion.add(lineaMaq.conDireccion(direccion));
            this.codigoMaquina = lineaMaq.codigo;
            this.valorListaMaquina = lineaMaq.valorLista;

            // Líneas de accesorios/servicios
            for (ComodatoOverrideResolver.LineaResuelta c : comodatos) {
                LineaEquipo lineaAcc = new LineaEquipo(c);
                this.accesorios.add(lineaAcc);
                this.ubicacion.add(lineaAcc.conDireccion(direccion));
                if (c.tipoDeAsociacion == 'Insumo Mensual') {
                    this.condiciones.add(new LineaCondicionComercial(c));
                }
            }
        }
    }
}