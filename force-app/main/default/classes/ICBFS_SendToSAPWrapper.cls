public class ICBFS_SendToSAPWrapper {
    // Tipo de datos para ClienteFacturador
    public class ClienteFacturador {
        @InvocableVariable(label='Cliente')
        public String Cliente;
        @InvocableVariable(label='Grupo Cuentas')
        public String GrupoCuentas;
        @InvocableVariable(label='Sociedad')
        public String Sociedad;
        @InvocableVariable(label='OrgVentas')
        public String OrgVentas;
        @InvocableVariable(label='Canal')
        public String Canal;
        @InvocableVariable(label='Sector')
        public String Sector;
        @InvocableVariable(label='Identificador')
        public String Identificador;
        @InvocableVariable(label='Tratamiento')
        public String Tratamiento;
        @InvocableVariable(label='Nombre')
        public String Nombre;
        @InvocableVariable(label='NombreFantasia')
        public String NombreFantasia;
        @InvocableVariable(label='ConceptoBusqueda')
        public String ConceptoBusqueda;
        @InvocableVariable(label='Calle')
        public String Calle;
        @InvocableVariable(label='Distrito')
        public String Distrito;
        @InvocableVariable(label='Poblacion')
        public String Poblacion;
        @InvocableVariable(label='Pais')
        public String Pais;
        @InvocableVariable(label='Region')
        public String Region;
        @InvocableVariable(label='Idioma')
        public String Idioma;
        @InvocableVariable(label='Telefono')
        public String Telefono;
        @InvocableVariable(label='Celular')
        public String Celular;
        @InvocableVariable(label='Fax')
        public String Fax;
        @InvocableVariable(label='Email')
        public String Email;
        @InvocableVariable(label='RamoControl')
        public String RamoControl;
        @InvocableVariable(label='NumIdentFiscal')
        public String NumIdentFiscal;
        @InvocableVariable(label='PersonaFisica')
        public String PersonaFisica;
        @InvocableVariable(label='ImpVolNeg')
        public String ImpVolNeg;
        @InvocableVariable(label='RamoMkt')
        public String RamoMkt;
        @InvocableVariable(label='CodigoRamo')
        public String CodigoRamo;
        @InvocableVariable(label='StatusJuridico')
        public String StatusJuridico;
        @InvocableVariable(label='CuentaAsociada')
        public String CuentaAsociada;
        @InvocableVariable(label='ClaveClasific')
        public String ClaveClasific;
        @InvocableVariable(label='GrupoTesoreria')
        public String GrupoTesoreria;
        @InvocableVariable(label='CondicionPago')
        public String CondicionPago;
        @InvocableVariable(label='GrabaHistPago')
        public String GrabaHistPago;
        @InvocableVariable(label='ProcedReclamo')
        public String ProcedReclamo;
        @InvocableVariable(label='ZonaVentas')
        public String ZonaVentas;
        @InvocableVariable(label='OficinaVentas')
        public String OficinaVentas;
        @InvocableVariable(label='GrupoVendedores')
        public String GrupoVendedores;
        @InvocableVariable(label='Rappel')
        public String Rappel;
        @InvocableVariable(label='DetermPrecio')
        public String DetermPrecio;
        @InvocableVariable(label='CondPagoFact')
        public String CondPagoFact;
        @InvocableVariable(label='Impuesto')
        public String Impuesto;
        @InvocableVariable(label='AreaCtrlCred')
        public String AreaCtrlCred;
        @InvocableVariable(label='LimiteCredito')
        public String LimiteCredito;
        @InvocableVariable(label='ClaseRiesgo')
        public String ClaseRiesgo;
        @InvocableVariable(label='EquipoResponsable')
        public String EquipoResponsable;
        @InvocableVariable(label='GrupoCredCliente')
        public String GrupoCredCliente;
        @InvocableVariable(label='GrupoImputacion')
        public String GrupoImputacion;
        @InvocableVariable(label='FechaFacturacion')
        public String FechaFacturacion;
        @InvocableVariable(label='FechaListaFactura')
        public String FechaListaFactura;
    }

    // Tipo de datos para ClienteDespacho
    public class ClienteDespacho {
        @InvocableVariable(label='Cliente')
        public String Cliente;
        @InvocableVariable(label='ClienteFacturador')
        public String ClienteFacturador;
        @InvocableVariable(label='Grupo Cuentas')
        public String GrupoCuentas;
        @InvocableVariable(label='Sociedad')
        public String Sociedad;
        @InvocableVariable(label='OrgVentas')
        public String OrgVentas;
        @InvocableVariable(label='Canal')
        public String Canal;
        @InvocableVariable(label='Sector')
        public String Sector;
        @InvocableVariable(label='Identificador')
        public String Identificador;
        @InvocableVariable(label='Tratamiento')
        public String Tratamiento;
        @InvocableVariable(label='Nombre')
        public String Nombre;
        @InvocableVariable(label='ConceptoBusqueda')
        public String ConceptoBusqueda;
        @InvocableVariable(label='Calle')
        public String Calle;
        @InvocableVariable(label='Distrito')
        public String Distrito;
        @InvocableVariable(label='Poblacion')
        public String Poblacion;
        @InvocableVariable(label='Pais')
        public String Pais;
        @InvocableVariable(label='Region')
        public String Region;
        @InvocableVariable(label='ZonaTransporte')
        public String ZonaTransporte;
        @InvocableVariable(label='Idioma')
        public String Idioma;
        @InvocableVariable(label='RamoControl')
        public String RamoControl;
        @InvocableVariable(label='NumIdentFiscal')
        public String NumIdentFiscal;
        @InvocableVariable(label='PersonaFisica')
        public String PersonaFisica;
        @InvocableVariable(label='ImpVolNeg')
        public String ImpVolNeg;
        @InvocableVariable(label='RamoMkt')
        public String RamoMkt;
        @InvocableVariable(label='CodigoRamoMkt')
        public String CodigoRamoMkt;
        @InvocableVariable(label='StatusJuridico')
        public String StatusJuridico;
        @InvocableVariable(label='CondicionPago')
        public String CondicionPago;
        @InvocableVariable(label='ZonaVentas')
        public String ZonaVentas;
        @InvocableVariable(label='OficinaVentas')
        public String OficinaVentas;
        @InvocableVariable(label='GrupoVendedores')
        public String GrupoVendedores;
        @InvocableVariable(label='GrupoClientes')
        public String GrupoClientes;
        @InvocableVariable(label='ClaseAbc')
        public String ClaseAbc;
        @InvocableVariable(label='Moneda')
        public String Moneda;
        @InvocableVariable(label='ProbabPedido')
        public String ProbabPedido;
        @InvocableVariable(label='GrupoPrecios')
        public String GrupoPrecios;
        @InvocableVariable(label='EsquemaCliente')
        public String EsquemaCliente;
        @InvocableVariable(label='ListaPrecios')
        public String ListaPrecios;
        @InvocableVariable(label='GrpEstaClnt')
        public String GrpEstaClnt;
        @InvocableVariable(label='PrioridadEntrega')
        public String PrioridadEntrega;
        @InvocableVariable(label='CondExpedicion')
        public String CondExpedicion;
        @InvocableVariable(label='CentroSum')
        public String CentroSum;
        @InvocableVariable(label='EntParcial')
        public String EntParcial;
        @InvocableVariable(label='TolIlimitada')
        public String TolIlimitada;
        @InvocableVariable(label='Rappel')
        public String Rappel;
        @InvocableVariable(label='DetermPrecio')
        public String DetermPrecio;
        @InvocableVariable(label='Incoterms')
        public String Incoterms;
        @InvocableVariable(label='GrupoImputacion')
        public String GrupoImputacion;
        @InvocableVariable(label='Impuesto')
        public String Impuesto;
        @InvocableVariable(label='FechaFacturacion')
        public String FechaFacturacion;
        @InvocableVariable(label='FechaListaFactura')
        public String FechaListaFactura;
        @InvocableVariable(label='Latitud')
        public String Latitud;
        @InvocableVariable(label='Longitud')
        public String Longitud;
        @InvocableVariable(label='VentanaHoraria')
        public String VentanaHoraria;
        @InvocableVariable(label='TiempoServicio')
        public String TiempoServicio;
    }

    // Tipo de datos para Tax
    public class Tax {
        @InvocableVariable(label='Code')
        public String Code;
        @InvocableVariable(label='Rate')
        public String Rate;
        @InvocableVariable(label='Name')
        public String Name;
    }

    // Tipo de datos Request para Flow
    public class Request {
        @InvocableVariable(label='ClienteFacturador Set')
        public List<ClienteFacturador> clienteFacturadorSet;
        @InvocableVariable(label='ClienteDespacho Set')
        public List<ClienteDespacho> clienteDespachoSet;
        @InvocableVariable(label='Taxes Set')
        public List<Tax> taxesSet;
    }

    // Tipo de datos Response para Flow
    public class Response {
        @InvocableVariable(label='JSON Body')
        public String jsonBody;
    }

    @InvocableMethod(label='Construir JSON para SAP')
    public static List<Response> buildJson(List<Request> requests) {
        List<Response> results = new List<Response>();
        for (Request req : requests) {
            Response resp = new Response();
            resp.jsonBody = JSON.serialize(req);
            results.add(resp);
        }
        return results;
    }
}