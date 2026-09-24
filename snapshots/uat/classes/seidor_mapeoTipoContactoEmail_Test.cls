@IsTest
private class seidor_mapeoTipoContactoEmail_Test {

    private static final String TIPO_USUARIO_PIA       = 'Usuario PIA';
    private static final String TIPO_COMPRADOR         = 'Comprador';
    private static final String TIPO_PAGADOR           = 'Pagador';
    private static final String TIPO_COMERCIAL         = 'Comercial';
    private static final String TIPO_DUENO             = 'Dueño';
    private static final String TIPO_CHEF              = 'Chef';
    private static final String TIPO_ADMINISTRADOR     = 'Administrador';
    private static final String TIPO_LOGISTICA         = 'Logística';
    private static final String TIPO_MARKETING         = 'Marketing';
    private static final String TIPO_FINANZAS          = 'Finanzas';
    private static final String TIPO_GESTION_CALIDAD   = 'Gestión calidad';
    private static final String TIPO_GERENTE_GENERAL   = 'Gerente General';
    private static final String TIPO_REP_LEGAL         = 'Representante Legal';
    private static final String TIPO_COMPRADOR_VOZ     = 'Comprador Pedido por Voz';

    private static Account crearAccount(String nombre) {
        Account acc = new Account(Name = nombre);
        insert acc;
        return acc;
    }

    private static Account crearAccountConEmail(String nombre, String email) {
        Account acc = new Account(Name = nombre, Email__c = email);
        insert acc;
        return acc;
    }

    private static Contact crearContacto(Id accountId, String nombre, String email, String tipoContacto) {
        Contact c = new Contact(
            AccountId           = accountId,
            LastName            = nombre,
            Email               = email,
            Tipo_de_contacto__c = tipoContacto
        );
        insert c;
        return c;
    }

    private static seidor_mapeoTipoContactoEmail.InputWrapper buildInput(Id accountId) {
        seidor_mapeoTipoContactoEmail.InputWrapper input =
            new seidor_mapeoTipoContactoEmail.InputWrapper();
        input.accountId = accountId;
        return input;
    }

    private static List<seidor_mapeoTipoContactoEmail.OutputWrapper> invocar(Id accountId) {
        return seidor_mapeoTipoContactoEmail.obtenerContactoPrioritario(
            new List<seidor_mapeoTipoContactoEmail.InputWrapper>{ buildInput(accountId) }
        );
    }

    // ─────────────────────────────────────────────
    // CONTACTO ÚNICO CON EMAIL
    // ─────────────────────────────────────────────

    @IsTest
    static void testContactoUnico_conEmail_retornaOutputCompleto() {
        Account acc     = crearAccount('Cuenta Test');
        Contact contacto = crearContacto(acc.Id, 'Juan Comprador', 'juan@test.com', TIPO_COMPRADOR);

        Test.startTest();
        List<seidor_mapeoTipoContactoEmail.OutputWrapper> resultados = invocar(acc.Id);
        Test.stopTest();

        Assert.areEqual(1, resultados.size(), 'Debe retornar 1 output para 1 contacto.');
        Assert.areEqual(contacto.Id, resultados[0].contactId);
        Assert.areEqual('Juan Comprador', resultados[0].contactName);
        Assert.areEqual('juan@test.com', resultados[0].contactEmail);
        Assert.areEqual(TIPO_COMPRADOR, resultados[0].tipoContactoEncontrado);
    }

    // ─────────────────────────────────────────────
    // MÚLTIPLES CONTACTOS CON EMAIL
    // ─────────────────────────────────────────────

    @IsTest
    static void testMultiplesContactos_retornaTodos() {
        Account acc = crearAccount('Cuenta Multi');
        crearContacto(acc.Id, 'Ana',     'ana@test.com',   TIPO_COMPRADOR);
        crearContacto(acc.Id, 'Luis',    'luis@test.com',  TIPO_USUARIO_PIA);
        crearContacto(acc.Id, 'Pedro',   'pedro@test.com', TIPO_COMERCIAL);

        Test.startTest();
        List<seidor_mapeoTipoContactoEmail.OutputWrapper> resultados = invocar(acc.Id);
        Test.stopTest();

        Assert.areEqual(3, resultados.size(), 'Deben retornarse todos los contactos con email.');
    }

    // ─────────────────────────────────────────────
    // MULTIPICKLIST
    // ─────────────────────────────────────────────

    @IsTest
    static void testMultipicklist_contactoConVariosTipos_seRetorna() {
        Account acc = crearAccount('Cuenta Multipicklist');
        crearContacto(acc.Id, 'Sofia Multi', 'sofia@test.com',
            TIPO_PAGADOR + ';' + TIPO_COMPRADOR);

        Test.startTest();
        List<seidor_mapeoTipoContactoEmail.OutputWrapper> resultados = invocar(acc.Id);
        Test.stopTest();

        Assert.areEqual(1, resultados.size());
        Assert.isNotNull(resultados[0].contactId);
        Assert.isNotNull(resultados[0].contactEmail);
    }

    // ─────────────────────────────────────────────
    // CONTACTO SIN EMAIL → FILTRADO POR WHERE
    // ─────────────────────────────────────────────

    @IsTest
    static void testContactoSinEmail_esFiltrado() {
        Account acc = crearAccount('Cuenta Sin Email');
        Contact sinEmail = new Contact(
            AccountId           = acc.Id,
            LastName            = 'Sin Email VIP',
            Tipo_de_contacto__c = TIPO_USUARIO_PIA
        );
        insert sinEmail;

        Contact conEmail = crearContacto(acc.Id, 'Con Email', 'conemail@test.com', TIPO_COMPRADOR);

        Test.startTest();
        List<seidor_mapeoTipoContactoEmail.OutputWrapper> resultados = invocar(acc.Id);
        Test.stopTest();

        Assert.areEqual(1, resultados.size(),
            'Solo el contacto con email debe ser retornado.');
        Assert.areEqual(conEmail.Id, resultados[0].contactId);
        Assert.areEqual('conemail@test.com', resultados[0].contactEmail);
    }

    @IsTest
    static void testSoloContactosSinEmailYSinAccountEmail_listaVacia() {
        Account acc = crearAccount('Cuenta Solo Sin Email');
        insert new Contact(
            AccountId           = acc.Id,
            LastName            = 'Sin Email',
            Tipo_de_contacto__c = TIPO_USUARIO_PIA
        );

        Test.startTest();
        List<seidor_mapeoTipoContactoEmail.OutputWrapper> resultados = invocar(acc.Id);
        Test.stopTest();

        Assert.isTrue(resultados.isEmpty(),
            'Sin contactos con email ni Account.Email__c, la lista debe estar vacía.');
    }

    // ─────────────────────────────────────────────
    // CONTACTOS SIN EMAIL + FALLBACK A ACCOUNT.EMAIL__C
    // ─────────────────────────────────────────────

    @IsTest
    static void testSoloContactosSinEmail_conAccountEmail_usaFallback() {
        Account acc = crearAccountConEmail('Cuenta Fallback', 'fallback@test.com');
        insert new Contact(
            AccountId           = acc.Id,
            LastName            = 'Sin Email',
            Tipo_de_contacto__c = TIPO_USUARIO_PIA
        );

        Test.startTest();
        List<seidor_mapeoTipoContactoEmail.OutputWrapper> resultados = invocar(acc.Id);
        Test.stopTest();

        Assert.areEqual(1, resultados.size());
        Assert.areEqual('fallback@test.com', resultados[0].contactEmail);
        Assert.areEqual('Email de cuenta', resultados[0].tipoContactoEncontrado);
        Assert.isNull(resultados[0].contactId);
    }

    // ─────────────────────────────────────────────
    // SIN CONTACTOS
    // ─────────────────────────────────────────────

    @IsTest
    static void testSinContactos_conAccountEmail_usaEmailCuenta() {
        Account acc = crearAccountConEmail('Cuenta Email', 'cuenta@test.com');

        Test.startTest();
        List<seidor_mapeoTipoContactoEmail.OutputWrapper> resultados = invocar(acc.Id);
        Test.stopTest();

        Assert.areEqual(1, resultados.size(), 'Debe retornar el email de la cuenta como fallback.');
        Assert.areEqual('cuenta@test.com', resultados[0].contactEmail);
        Assert.areEqual(acc.Name, resultados[0].contactName);
        Assert.areEqual('Email de cuenta', resultados[0].tipoContactoEncontrado);
        Assert.isNull(resultados[0].contactId);
    }

    @IsTest
    static void testSinContactosYsinAccountEmail_listaVacia() {
        Account acc = crearAccount('Cuenta Vacía');

        Test.startTest();
        List<seidor_mapeoTipoContactoEmail.OutputWrapper> resultados = invocar(acc.Id);
        Test.stopTest();

        Assert.isTrue(resultados.isEmpty(),
            'Sin contactos ni Account.Email__c, la lista debe estar vacía.');
    }

    // ─────────────────────────────────────────────
    // CONTACTOS CON TIPO EN BLANCO/NULL — AHORA SE RETORNAN (TIENEN EMAIL)
    // ─────────────────────────────────────────────

    @IsTest
    static void testContactoConTipoEnBlanco_conEmail_seRetorna() {
        Account acc = crearAccount('Cuenta Tipo Blanco');
        crearContacto(acc.Id, 'Sin Tipo', 'sintipo@test.com', '');

        Test.startTest();
        List<seidor_mapeoTipoContactoEmail.OutputWrapper> resultados = invocar(acc.Id);
        Test.stopTest();

        Assert.areEqual(1, resultados.size(),
            'Contacto con tipo en blanco pero con email debe retornarse.');
        Assert.areEqual('sintipo@test.com', resultados[0].contactEmail);
    }

    @IsTest
    static void testContactoConTipoNull_conEmail_seRetorna() {
        Account acc = crearAccount('Cuenta Tipo Null');
        Contact sinTipo = new Contact(
            AccountId = acc.Id,
            LastName  = 'Tipo Null',
            Email     = 'tiponull@test.com'
        );
        insert sinTipo;

        Test.startTest();
        List<seidor_mapeoTipoContactoEmail.OutputWrapper> resultados = invocar(acc.Id);
        Test.stopTest();

        Assert.areEqual(1, resultados.size(),
            'Contacto con tipo null pero con email debe retornarse.');
        Assert.areEqual('tiponull@test.com', resultados[0].contactEmail);
    }

    // ─────────────────────────────────────────────
    // CONTACTOS CON TIPO FUERA DE LISTA — AHORA SE RETORNAN
    // ─────────────────────────────────────────────

    @IsTest
    static void testContactoConTipoFueraDeLista_conEmail_seRetorna() {
        Account acc = crearAccount('Cuenta Tipo Invalido');
        crearContacto(acc.Id, 'Tipo X', 'tipox@test.com', 'TipoQueNoExiste');

        Test.startTest();
        List<seidor_mapeoTipoContactoEmail.OutputWrapper> resultados = invocar(acc.Id);
        Test.stopTest();

        Assert.areEqual(1, resultados.size(),
            'Contacto con tipo fuera de lista pero con email debe retornarse.');
        Assert.areEqual('tipox@test.com', resultados[0].contactEmail);
    }

    // ─────────────────────────────────────────────
    // BULKIFICATION
    // ─────────────────────────────────────────────

    @IsTest
    static void testBulkification_multiplesCuentas_retornaTodos() {
        Account acc1 = crearAccount('Bulk 1');
        Account acc2 = crearAccount('Bulk 2');
        Account acc3 = crearAccountConEmail('Bulk 3', 'bulk3@test.com');
        Account acc4 = crearAccount('Bulk 4');

        crearContacto(acc1.Id, 'C1',  'c1@test.com',  TIPO_USUARIO_PIA);
        crearContacto(acc1.Id, 'C1b', 'c1b@test.com', TIPO_CHEF);
        crearContacto(acc2.Id, 'C2',  'c2@test.com',  TIPO_COMERCIAL);
        // acc3: sin contactos → fallback Email__c
        // acc4: sin contactos, sin Email__c → 0 outputs

        List<seidor_mapeoTipoContactoEmail.InputWrapper> inputs = new List<seidor_mapeoTipoContactoEmail.InputWrapper>{
            buildInput(acc1.Id),
            buildInput(acc2.Id),
            buildInput(acc3.Id),
            buildInput(acc4.Id)
        };

        Test.startTest();
        List<seidor_mapeoTipoContactoEmail.OutputWrapper> resultados =
            seidor_mapeoTipoContactoEmail.obtenerContactoPrioritario(inputs);
        Test.stopTest();

        // acc1: 2 contactos + acc2: 1 contacto + acc3: 1 fallback + acc4: 0 = 4
        Assert.areEqual(4, resultados.size(), 'Debe retornar todos los outputs combinados.');

        Assert.areEqual('c1@test.com',  resultados[0].contactEmail);
        Assert.areEqual('c1b@test.com', resultados[1].contactEmail);
        Assert.areEqual('c2@test.com',  resultados[2].contactEmail);
        Assert.areEqual('bulk3@test.com', resultados[3].contactEmail);
        Assert.isNull(resultados[3].contactId);
    }

    @IsTest
    static void testBulkification_mismaCuentaDosVeces_retornaContactosPorInput() {
        Account acc = crearAccount('Cuenta Dup');
        crearContacto(acc.Id, 'Unico', 'unico@test.com', TIPO_ADMINISTRADOR);

        List<seidor_mapeoTipoContactoEmail.InputWrapper> inputs = new List<seidor_mapeoTipoContactoEmail.InputWrapper>{
            buildInput(acc.Id),
            buildInput(acc.Id)
        };

        Test.startTest();
        List<seidor_mapeoTipoContactoEmail.OutputWrapper> resultados =
            seidor_mapeoTipoContactoEmail.obtenerContactoPrioritario(inputs);
        Test.stopTest();

        Assert.areEqual(2, resultados.size(),
            'Debe retornar 1 output por cada contacto, por cada input (2).');
        Assert.areEqual('unico@test.com', resultados[0].contactEmail);
        Assert.areEqual('unico@test.com', resultados[1].contactEmail);
    }
}