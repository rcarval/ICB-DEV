@isTest
private class seidor_CuentasSinContactosServiceTest {

    private static Integer secuencia = 0;

    // Datos únicos por ejecución (RUT con DV módulo 11 válido) para evitar
    // colisiones con duplicate rules / datos reales al desplegar a PRD.
    private static String rutUnico() {
        String base    = String.valueOf(Datetime.now().getTime());
        Integer cuerpo = Math.mod(Integer.valueOf(base.right(6)) * 100 + (++secuencia), 99999999);
        return String.valueOf(cuerpo).leftPad(8, '0') + '-' + calcularDv(cuerpo);
    }

    private static String calcularDv(Integer n) {
        Integer sum = 0;
        Integer mul = 2;
        while (n > 0) {
            sum += Math.mod(n, 10) * mul;
            mul = (mul == 7) ? 2 : mul + 1;
            n   = n / 10;
        }
        Integer res = 11 - Math.mod(sum, 11);
        if (res == 11) return '0';
        if (res == 10) return 'K';
        return String.valueOf(res);
    }

    @testSetup
    static void setup() {
        String sufijo = String.valueOf(Datetime.now().getTime()).right(8);
        List<RecordType> rts = [
            SELECT Id FROM RecordType
            WHERE SobjectType = 'Account' AND DeveloperName = 'Sucursal'
            LIMIT 1
        ];
        Id rtSucursal = rts[0].Id;

        Account padreA = new Account(
            Name                 = 'Padre Test ' + sufijo,
            RUT__c               = rutUnico(),
            C_digo_de_cliente__c = 'FS' + sufijo + '1'
        );
        insert padreA;

        Account padreB = new Account(
            Name                 = 'Padre Sin Contactos Test ' + sufijo,
            RUT__c               = rutUnico(),
            C_digo_de_cliente__c = 'FS' + sufijo + '9'
        );
        insert padreB;

        List<Account> hijos = new List<Account>{
            // Con contacto directo propio → NO debe aparecer en la vista
            new Account(
                Name                      = 'Hija Con Contacto Test ' + sufijo,
                ParentId                  = padreA.Id,
                RecordTypeId              = rtSucursal,
                RUT__c                    = rutUnico(),
                C_digo_de_cliente__c      = 'FS' + sufijo + '2',
                Nombre_de_Fantasia__c     = 'Fantasia Hija Con'
            ),
            // Sin contacto directo, padre CON contactos → aparece con detalle
            new Account(
                Name                      = 'Hija Sin Contacto Test ' + sufijo,
                ParentId                  = padreA.Id,
                RecordTypeId              = rtSucursal,
                RUT__c                    = rutUnico(),
                C_digo_de_cliente__c      = 'FS' + sufijo + '3',
                Nombre_de_Fantasia__c     = 'Fantasia Hija Sin'
            ),
            // Sin flag holding pero con ParentId y RT Sucursal → aparece
            new Account(
                Name                      = 'Hija Sin Flag Test ' + sufijo,
                ParentId                  = padreA.Id,
                RecordTypeId              = rtSucursal,
                RUT__c                    = rutUnico(),
                C_digo_de_cliente__c      = 'FS' + sufijo + '5'
            ),
            // Hija cuyo padre no tiene ningún contacto → "sin respaldo"
            new Account(
                Name                      = 'Hija De Padre Solo Test ' + sufijo,
                ParentId                  = padreB.Id,
                RecordTypeId              = rtSucursal,
                RUT__c                    = rutUnico(),
                C_digo_de_cliente__c      = 'FS' + sufijo + '7'
            ),
            // Sucursal SIN padre → excluida de la vista (no agrupable)
            new Account(
                Name                      = 'Raiz Sucursal Sin Padre Test ' + sufijo,
                RecordTypeId              = rtSucursal,
                RUT__c                    = rutUnico()
            )
        };
        insert hijos;

        Map<String, Account> porNombre = new Map<String, Account>();
        for (Account a : hijos) { porNombre.put(a.Name, a); }

        insert new List<Contact>{
            new Contact(
                LastName  = 'Contacto Uno Test',
                AccountId = porNombre.get('Hija Con Contacto Test ' + sufijo).Id,
                Email     = 'contacto1.' + sufijo + '@test.com'
            ),
            new Contact(
                LastName  = 'Contacto Dos Test',
                AccountId = porNombre.get('Hija Con Contacto Test ' + sufijo).Id
            ),
            new Contact(
                LastName  = 'Contacto Holding Test',
                AccountId = padreA.Id,
                Email     = 'holding.' + sufijo + '@test.com'
            )
        };
    }

    @isTest
    static void getCuentasPaginadas_soloSucursalesSinContactoDirecto() {
        String sufijo = sufijoDeSetup();
        Test.startTest();
        seidor_CuentasSinContactosService.ResultadoPagina res =
            seidor_CuentasSinContactosService.getCuentasPaginadas(null, null, 500);
        Test.stopTest();

        Set<String> nombres = new Set<String>();
        for (seidor_CuentasSinContactosService.CuentaRow r : res.filas) {
            nombres.add(r.accountName);
        }

        Assert.areEqual(3, res.filas.size(), 'Universo: 3 sucursales sin contacto directo');
        Assert.isTrue(nombres.contains('Hija Sin Contacto Test ' + sufijo), 'Hija sin directo incluida');
        Assert.isTrue(nombres.contains('Hija Sin Flag Test ' + sufijo), 'Hija con ParentId incluida (RT manda)');
        Assert.isTrue(nombres.contains('Hija De Padre Solo Test ' + sufijo), 'Hija de padre sin contactos incluida');
        Assert.isFalse(nombres.contains('Hija Con Contacto Test ' + sufijo), 'Hija con contacto directo EXCLUIDA');
        Assert.isFalse(nombres.contains('Raiz Sucursal Sin Padre Test ' + sufijo), 'Sucursal sin padre EXCLUIDA');
        System.assertEquals(null, res.nextAnchor, 'Universo completo en una página');
    }

    @isTest
    static void getCuentasPaginadas_detalleHerenciaYRecordType() {
        String sufijo = sufijoDeSetup();
        Test.startTest();
        seidor_CuentasSinContactosService.ResultadoPagina res =
            seidor_CuentasSinContactosService.getCuentasPaginadas(null, null, 500);
        Test.stopTest();

        seidor_CuentasSinContactosService.CuentaRow hijaSin = null;
        seidor_CuentasSinContactosService.CuentaRow hijaSolo = null;
        for (seidor_CuentasSinContactosService.CuentaRow r : res.filas) {
            if (r.accountName == 'Hija Sin Contacto Test ' + sufijo) hijaSin = r;
            if (r.accountName == 'Hija De Padre Solo Test ' + sufijo) hijaSolo = r;
        }

        System.assertNotEquals(null, hijaSin, 'Fila presente');
        Assert.areEqual('Sucursal', hijaSin.recordTypeName, 'Nombre del tipo de registro expuesto');
        Assert.areEqual('Padre Test ' + sufijo, hijaSin.parentAccountName, 'Principal resuelta');
        Assert.isTrue(hijaSin.padreConContactos, 'El padre tiene contactos → detalle con herencia');
        Assert.areEqual(1, hijaSin.contactoCountPadre, 'Un contacto del padre expuesto');
        Assert.areEqual('Contacto Holding Test', hijaSin.contactosPadre[0].name);

        System.assertNotEquals(null, hijaSolo, 'Fila de padre sin contactos presente');
        Assert.isFalse(hijaSolo.padreConContactos, 'Padre sin contactos → sin respaldo');
        Assert.areEqual(0, hijaSolo.contactoCountPadre);
    }

    @isTest
    static void getTotales_universoSucursalesSinDirecto() {
        Test.startTest();
        seidor_CuentasSinContactosService.ResultadoTotales tot =
            seidor_CuentasSinContactosService.getTotales(null);
        Test.stopTest();

        Assert.areEqual(3, tot.totalCuentas, 'Total sucursales sin contacto directo');
        Assert.areEqual(2, tot.conRespaldoPadre, 'Dos hijas cuyos contactos viven en el padre');
        Assert.areEqual(1, tot.sinRespaldoPadre, 'Una hija sin ningún contacto disponible');
        Assert.areEqual(2, tot.cuentasPrincipales, 'Dos cuentas principales distintas');
        System.assertNotEquals(null, tot.topAsesores, 'Top asesores calculado');
        Assert.areEqual(1, tot.topAsesores.size(), 'Un solo asesor en el setup');
        Assert.areEqual(UserInfo.getName(), tot.topAsesores[0].nombre, 'Owner por defecto = running user');
        Assert.areEqual(3, tot.topAsesores[0].cantidad, 'Todas las sucursales del universo en el top');
    }

    @isTest
    static void getCuentasPaginadas_busquedaPorPropioNombreYPadre() {
        String sufijo = sufijoDeSetup();
        Test.startTest();
        seidor_CuentasSinContactosService.ResultadoPagina porHija =
            seidor_CuentasSinContactosService.getCuentasPaginadas('Hija De Padre Solo Test ' + sufijo, null, 200);
        seidor_CuentasSinContactosService.ResultadoPagina porPadre =
            seidor_CuentasSinContactosService.getCuentasPaginadas('Padre Sin Contactos Test', null, 200);
        Test.stopTest();

        Assert.areEqual(1, porHija.filas.size(), 'Match por nombre de la propia cuenta');
        Assert.areEqual(1, porPadre.filas.size(), 'Match por nombre de la cuenta principal');
        Assert.areEqual('Hija De Padre Solo Test ' + sufijo, porPadre.filas[0].accountName);
    }

    @isTest
    static void exportarExcel_generaArchivoConFormatoTabla() {
        String sufijo = sufijoDeSetup();
        Test.startTest();
        seidor_CuentasSinContactosService.ExcelResult res =
            seidor_CuentasSinContactosService.exportarExcel(null, 1000);
        Test.stopTest();

        Assert.isFalse(res.truncado, 'Export completo, sin truncar');
        Assert.areEqual(3, res.filas, 'Todas las sucursales del universo exportadas');
        System.assertNotEquals(null, res.versionId, 'ContentVersion creado para descarga');

        ContentVersion cv = [
            SELECT VersionData FROM ContentVersion WHERE Id = :res.versionId
        ];
        String html = cv.VersionData.toString();
        Assert.isTrue(html.contains('<table>'), 'Estructura de tabla');
        Assert.isTrue(html.contains('>Resumen</p>'), 'Sección Resumen');
        Assert.isTrue(html.contains('Sucursales sin contacto directo'), 'Métrica total del resumen');
        Assert.isTrue(html.contains('Con contactos en cliente principal'), 'Métrica con respaldo del resumen');
        Assert.isTrue(html.contains('Cuentas principales distintas'), 'Métrica de principales distintas');
        Assert.isTrue(html.contains('Top 5 asesores'), 'Tabla top asesores');
        Assert.isTrue(html.contains('Cuenta Principal'), 'Columna Cuenta Principal');
        Assert.isTrue(html.contains('<th>Asesor</th>'), 'Columna Asesor');
        Assert.isTrue(
            html.indexOf('<th>Asesor</th>') < html.indexOf('<th>Cuenta Principal</th>'),
            'Orden de columnas: Asesor antes de Cuenta Principal'
        );
        Assert.isTrue(html.contains(escLike(UserInfo.getName())), 'Asesor (Owner) del principal listado');
        Assert.isTrue(html.contains('<th>Sucursal</th>'), 'Columna Sucursal');
        Assert.isTrue(html.contains('>Detalle<'), 'Columna Detalle');
        Assert.isTrue(html.contains('rowspan="3"'), 'Celda combinada del asesor (grupo de 3 sucursales)');
        Assert.isTrue(html.contains('rowspan="2"'), 'Bloque combinado por cuenta principal (2 hijas de Padre Test)');
        Assert.isTrue(
            html.contains('no posee contactos directos'),
            'Mensaje del detalle presente'
        );
        Assert.isTrue(
            html.contains('«Padre Test ' + sufijo + '»'),
            'Detalle menciona la cuenta principal'
        );
        Assert.isTrue(html.contains('Contacto Holding Test'), 'Contacto heredado listado');
        Assert.isTrue(html.contains('Sin contactos asociados'), 'Caso sin ningún contacto cubierto');
    }

    @isTest
    static void exportarExcel_respetaTechoFilas() {
        Test.startTest();
        seidor_CuentasSinContactosService.ExcelResult res =
            seidor_CuentasSinContactosService.exportarExcel(null, 2);
        Test.stopTest();

        Assert.isTrue(res.truncado, 'Se marca truncado al superar el techo');
        Assert.areEqual(2, res.filas, 'Exporta solo hasta el techo solicitado');
        System.assertNotEquals(null, res.versionId, 'ContentVersion creado aun truncado');
    }

    @isTest
    static void prepararYEnviarCorreoAsesor_generaTablaYCapturaEnvio() {
        String sufijo = sufijoDeSetup();
        // OWA inyectada para no depender de la config de direcciones de la org
        seidor_CuentasSinContactosService.orgWideAddressIdTest = UserInfo.getUserId();

        Test.startTest();
        seidor_CuentasSinContactosService.ResultadoPagina pagina =
            seidor_CuentasSinContactosService.getCuentasPaginadas(null, null, 500);
        List<String> ids = idsDe(pagina.filas);

        seidor_CuentasSinContactosService.CorreoPreview preview =
            seidor_CuentasSinContactosService.prepararCorreoAsesor(ids);

        seidor_CuentasSinContactosService.enviarCorreoAsesor(
            ids,
            'asesor.' + sufijo + '@test.com',
            new List<String>{ 'copia.' + sufijo + '@test.com' },
            'Sucursales sin contacto directo - ' + UserInfo.getName());
        Test.stopTest();

        // Preview: solo contexto del modal
        Assert.areEqual(UserInfo.getUserEmail(), preview.de, '"De" = usuario conectado');
        Assert.areEqual(UserInfo.getName(), preview.nombreUsuario, 'Nombre del usuario expuesto');

        // Envío capturado (no real en tests)
        System.assertNotEquals(null,
            seidor_CuentasSinContactosService.correosCapturados, 'Envío capturado');
        Assert.areEqual(1, seidor_CuentasSinContactosService.correosCapturados.size());
        Messaging.SingleEmailMessage mail =
            seidor_CuentasSinContactosService.correosCapturados[0];
        Assert.areEqual('asesor.' + sufijo + '@test.com',
            mail.getToAddresses()[0], 'Destinatario = asesor');
        Assert.areEqual('copia.' + sufijo + '@test.com',
            mail.getCcAddresses()[0], 'CC incluido');
        Assert.areEqual(UserInfo.getUserEmail(),
            mail.getReplyTo(), 'Reply-To = correo del usuario conectado');
        Assert.isTrue(mail.getSubject().contains(UserInfo.getName()), 'Asunto con nombre del asesor');

        String html = mail.getHtmlBody();
        Assert.isTrue(html.contains('<table '), 'Body HTML con tabla');
        Assert.isTrue(
            html.contains('Cuenta Principal') && html.contains('Sucursal') &&
            html.contains('Detalle'),
            'Columnas de la tabla del correo'
        );
        Assert.isFalse(html.contains('<th>Asesor</th>'), 'Sin columna Asesor (el destinatario lo es)');
        Assert.isTrue(
            html.contains(escLike('Padre Test ' + sufijo)),
            'Cuenta principal incluida en la tabla'
        );
        Assert.isTrue(
            html.contains(escLike('Hija De Padre Solo Test ' + sufijo)),
            'Sucursal sin respaldo incluida'
        );
        Assert.isTrue(html.contains('rowspan="2"'), 'Bloque combinado por principal');
        Assert.isTrue(html.contains('Contacto Holding Test'), 'Contacto heredado listado');

        // Formato corporativo: encabezado, saludo, intro y estilos inline
        Assert.isTrue(html.contains('ICB Food Service'), 'Encabezado institucional');
        Assert.isTrue(html.contains('Estimado(a)'), 'Saludo al asesor');
        Assert.isTrue(
            html.contains('no poseen contactos asignados directamente'),
            'Texto introductorio genérico'
        );
        Assert.isTrue(
            html.contains('background:#1f4e79') && html.contains('border-collapse:collapse'),
            'Estilos inline de la tabla corporativa'
        );
    }

    @isTest
    static void enviarCorreoAsesor_destinatarioInvalidoLanzaExcepcion() {
        seidor_CuentasSinContactosService.ResultadoPagina pagina =
            seidor_CuentasSinContactosService.getCuentasPaginadas(null, null, 500);
        List<String> ids = idsDe(pagina.filas);

        try {
            Test.startTest();
            seidor_CuentasSinContactosService.enviarCorreoAsesor(
                ids, 'sin-arroba', null, 'Asunto');
            Test.stopTest();
            Assert.fail('Debe rechazar destinatario inválido');
        } catch (Exception e) {
            Assert.isTrue(e.getMessage().contains('válido'),
                'Mensaje clara para destinatario inválido: ' + e.getMessage());
        }

        // CC inválido también rechaza
        try {
            seidor_CuentasSinContactosService.enviarCorreoAsesor(
                ids, 'asesor@test.com', new List<String>{ 'mal @correo' }, 'Asunto');
            Assert.fail('Debe rechazar CC inválido');
        } catch (Exception e) {
            Assert.isTrue(e.getMessage().contains('copia'),
                'Mensaje claro para CC inválido: ' + e.getMessage());
        }
        Assert.areEqual(0,
            (seidor_CuentasSinContactosService.correosCapturados == null)
                ? 0 : seidor_CuentasSinContactosService.correosCapturados.size(),
            'Nada enviado cuando la validación falla');
    }

    @isTest
    static void enviarCorreoAsesor_sinDireccionOrganicionalLanzaExcepcion() {
        seidor_CuentasSinContactosService.orgWideAddressIdTest   = null;
        seidor_CuentasSinContactosService.direccionRemitenteOverride = 'inexistente@icbfs.cl';
        seidor_CuentasSinContactosService.ResultadoPagina pagina =
            seidor_CuentasSinContactosService.getCuentasPaginadas(null, null, 500);
        try {
            Test.startTest();
            seidor_CuentasSinContactosService.enviarCorreoAsesor(
                idsDe(pagina.filas), 'asesor@test.com', null, 'Asunto');
            Test.stopTest();
            Assert.fail('Debe fallar si no existe la Org-Wide Address');
        } catch (Exception e) {
            Assert.isTrue(
                e.getMessage().contains('dirección organizacional'),
                'Error explica la dirección faltante: ' + e.getMessage());
        }
    }

    // Extrae los Ids de las filas para simular el payload del cliente.
    private static List<String> idsDe(List<seidor_CuentasSinContactosService.CuentaRow> filas) {
        List<String> ids = new List<String>();
        for (seidor_CuentasSinContactosService.CuentaRow r : filas) {
            ids.add(r.accountId);
        }
        return ids;
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    // Aplica el mismo escape mínimo que el export para comparar texto plano.
    private static String escLike(String s) {
        if (s == null) return '';
        return s.replace('&', '&amp;').replace('<', '&lt;').replace('>', '&gt;');
    }

    // Recupera el sufijo único generado en el setup a partir de la cuenta padre.
    private static String sufijoDeSetup() {
        Account padre = [
            SELECT Name FROM Account WHERE Name LIKE 'Padre Test %' LIMIT 1
        ];
        return padre.Name.substringAfter('Padre Test ');
    }
}