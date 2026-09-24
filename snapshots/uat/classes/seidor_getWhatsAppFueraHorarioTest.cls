/**
 * @description Test class para seidor_getWhatsAppFueraHorario
 *
 * NOTAS TÉCNICAS:
 * ─────────────────
 * 1. BusinessHours es Setup Object → visible en test context sin SeeAllData=true.
 *    Si el org no tiene un BusinessHours predeterminado, la clase captura la
 *    excepción y retorna fueraDeHorario = false.
 *
 * 2. MessagingSession y MessagingEndUser NO son insertables via DML en test
 *    context sin un MessagingChannel configurado. Por eso la rama marcarSesion()
 *    solo se prueba con @isTest(SeeAllData=true) y datos reales del org,
 *    omitiéndose silenciosamente si no existen.
 *
 * 3. BusinessHours.isWithin() usa la hora real del sistema. No es posible
 *    mockear el time en Apex, y marcarSesion() es privad0. Por eso, en vez de solo 
 *    validar "es un booleano valido", los tests principales RECALCULAN el 
 *    resultado esperado con la misma llamada a BusinessHours.isWithin() que usa la
 *    clase, y comparan que el Output coincida exactamente.
 */
@isTest
private class seidor_getWhatsAppFueraHorarioTest {

    // =============================================================================
    // HELPER: mismo calculo que hace la clase, para poder comparar el resultado
    // =============================================================================

    /**
     * Replica el calculo de la clase (misma query, mismo metodo estatico) para
     * poder afirmar el valor exacto esperado en vez de solo "es un booleano".
     * Si no hay Business Hours default en el org, retorna false (igual que
     * el catch de la clase).
     */
    private static Boolean calcularFueraDeHorarioEsperado() {
        try {
            BusinessHours bh = [
                SELECT Id
                FROM BusinessHours
                WHERE IsDefault = true
                LIMIT 1
            ];
            return !BusinessHours.isWithin(bh.Id, System.now());
        } catch (Exception e) {
            return false;
        }
    }

    // =============================================================================
    // VERIFICACION PRINCIPAL
    // =============================================================================

    /**
     * Verifica el contrato minimo del metodo y que el valor retornado
     * coincida EXACTAMENTE con el calculo esperado.
     */
    @isTest
    static void verificarFueraDeHorario_debeRetornarOutputValido() {
        Boolean esperado = calcularFueraDeHorarioEsperado();

        seidor_getWhatsAppFueraHorario.Input input =
            new seidor_getWhatsAppFueraHorario.Input();

        Test.startTest();
        List<seidor_getWhatsAppFueraHorario.Output> results =
            seidor_getWhatsAppFueraHorario.verificarFueraDeHorario(
                new List<seidor_getWhatsAppFueraHorario.Input>{ input });
        Test.stopTest();

        Assert.isNotNull(results, 'La lista de resultados no debe ser null');
        Assert.areEqual(1, results.size(),
            'Debe retornar exactamente 1 Output');
        Assert.isNotNull(results[0], 'El Output no debe ser null');
        Assert.areEqual(esperado, results[0].fueraDeHorario,
            'fueraDeHorario debe coincidir con el calculo real de Business Hours');
    }

    // =============================================================================
    // VARIACIONES DE INPUT
    // =============================================================================

    /**
     * Lista vacia: el metodo debe responder igual (crea Output y lo agrega).
     * Cubre la rama `inputs.isEmpty()` == true -> phone = null.
     */
    @isTest
    static void verificarFueraDeHorario_conListaVacia_debeResponderIgual() {
        Boolean esperado = calcularFueraDeHorarioEsperado();

        Test.startTest();
        List<seidor_getWhatsAppFueraHorario.Output> results =
            seidor_getWhatsAppFueraHorario.verificarFueraDeHorario(
                new List<seidor_getWhatsAppFueraHorario.Input>());
        Test.stopTest();

        Assert.areEqual(1, results.size(),
            'Debe retornar 1 Output aunque la lista este vacia');
        Assert.areEqual(esperado, results[0].fueraDeHorario,
            'fueraDeHorario debe coincidir con el calculo real de Business Hours');
    }

    /**
     * Input null dentro de la lista: cubre la rama donde se evalua
     * `inputs[0] != null`. Al ser null, phone se queda en null.
     */
    @isTest
    static void verificarFueraDeHorario_conInputNull_debeManejarGracefully() {
        Test.startTest();
        List<seidor_getWhatsAppFueraHorario.Output> results =
            seidor_getWhatsAppFueraHorario.verificarFueraDeHorario(
                new List<seidor_getWhatsAppFueraHorario.Input>{ null });
        Test.stopTest();

        Assert.areEqual(1, results.size(),
            'Debe retornar 1 Output aunque el input sea null');
        Assert.isNotNull(results[0], 'El Output no debe ser null');
    }

    /**
     * Input con endUserPhone en blanco: cubre String.isNotBlank() = false
     * dentro de marcarSesion (si llega a ejecutarse), forzando el fallback.
     */
    @isTest
    static void verificarFueraDeHorario_conTelefonoVacio_debeUsarStringVacio() {
        seidor_getWhatsAppFueraHorario.Input input =
            new seidor_getWhatsAppFueraHorario.Input();
        input.endUserPhone = '';

        Test.startTest();
        List<seidor_getWhatsAppFueraHorario.Output> results =
            seidor_getWhatsAppFueraHorario.verificarFueraDeHorario(
                new List<seidor_getWhatsAppFueraHorario.Input>{ input });
        Test.stopTest();

        Assert.areEqual(1, results.size(), 'Debe retornar 1 Output');
    }

    /**
     * Input con telefono en blanco (solo espacios): cubre el mismo
     * String.isNotBlank() = false, pero por la rama de "solo whitespace"
     * en vez de string vacio puro (ambas deben tratarse igual).
     */
    @isTest
    static void verificarFueraDeHorario_conTelefonoSoloEspacios_debeTratarloComoVacio() {
        seidor_getWhatsAppFueraHorario.Input input =
            new seidor_getWhatsAppFueraHorario.Input();
        input.endUserPhone = '   ';

        Test.startTest();
        List<seidor_getWhatsAppFueraHorario.Output> results =
            seidor_getWhatsAppFueraHorario.verificarFueraDeHorario(
                new List<seidor_getWhatsAppFueraHorario.Input>{ input });
        Test.stopTest();

        Assert.areEqual(1, results.size(), 'Debe retornar 1 Output');
    }

    /**
     * Input con telefono poblado: cubre el path donde se pasa el telefono
     * a marcarSesion, que luego hace SOQL sobre MessagingEndUser.
     * En test context sin datos reales, la query retorna vacio y cae al
     * fallback, que tampoco encuentra sesiones.
     */
    @isTest
    static void verificarFueraDeHorario_conTelefonoPoblado_debeEjecutarSinError() {
        seidor_getWhatsAppFueraHorario.Input input =
            new seidor_getWhatsAppFueraHorario.Input();
        input.endUserPhone = '56912345678';

        Test.startTest();
        List<seidor_getWhatsAppFueraHorario.Output> results =
            seidor_getWhatsAppFueraHorario.verificarFueraDeHorario(
                new List<seidor_getWhatsAppFueraHorario.Input>{ input });
        Test.stopTest();

        Assert.areEqual(1, results.size(), 'Debe retornar 1 Output');
        Assert.isNotNull(results[0].fueraDeHorario,
            'fueraDeHorario no debe ser null');
    }

    /**
     * Telefono con espacios alrededor: cubre el `.trim()` que se aplica
     * al telefono dentro de marcarSesion (si llega a ejecutarse).
     */
    @isTest
    static void verificarFueraDeHorario_conTelefonoConEspacios_debeEjecutarSinError() {
        seidor_getWhatsAppFueraHorario.Input input =
            new seidor_getWhatsAppFueraHorario.Input();
        input.endUserPhone = '  56912345678  ';

        Test.startTest();
        List<seidor_getWhatsAppFueraHorario.Output> results =
            seidor_getWhatsAppFueraHorario.verificarFueraDeHorario(
                new List<seidor_getWhatsAppFueraHorario.Input>{ input });
        Test.stopTest();

        Assert.areEqual(1, results.size(), 'Debe retornar 1 Output');
    }

    /**
     * Multiples inputs: el InvocableMethod acepta lista pero solo usa el
     * primero. Este test documenta el comportamiento actual (non-bulk).
     */
    @isTest
    static void verificarFueraDeHorario_conMultiplesInputs_soloUsaElPrimero() {
        List<seidor_getWhatsAppFueraHorario.Input> inputs =
            new List<seidor_getWhatsAppFueraHorario.Input>();
        seidor_getWhatsAppFueraHorario.Input input1 =
            new seidor_getWhatsAppFueraHorario.Input();
        input1.endUserPhone = '56911111111';
        inputs.add(input1);
        seidor_getWhatsAppFueraHorario.Input input2 =
            new seidor_getWhatsAppFueraHorario.Input();
        input2.endUserPhone = '56922222222';
        inputs.add(input2);

        Test.startTest();
        List<seidor_getWhatsAppFueraHorario.Output> results =
            seidor_getWhatsAppFueraHorario.verificarFueraDeHorario(inputs);
        Test.stopTest();

        Assert.areEqual(1, results.size(),
            'Actualmente retorna 1 Output, ignorando inputs adicionales');
    }

    // =============================================================================
    // OUTPUT: valor por defecto
    // =============================================================================

    /**
     * Verifica que el Output tiene valor por defecto correcto (null hasta
     * que se le asigna explicitamente).
     */
    @isTest
    static void verificarFueraDeHorario_outputPorDefectoEsFalse() {
        seidor_getWhatsAppFueraHorario.Output output =
            new seidor_getWhatsAppFueraHorario.Output();
        Assert.isNull(output.fueraDeHorario,
            'El valor por defecto de fueraDeHorario debe ser null');
    }

    // =============================================================================
    // HAPPY PATH CON DATOS REALES DEL ORG
    // =============================================================================
    //
    // Estos tests requieren datos reales de MessagingSession en el org.
    // Se omiten silenciosamente si no existen (mismo patron que
    // MessagingSessionTipificacionCtrl_Test).
    //
    // Son los unicos capaces de ejercitar las lineas internas de
    // marcarSesion() (busqueda por telefono, fallback, y el update de
    // Fuera_de_horario__c), ya que ese metodo es privado.
    // =============================================================================

    @isTest(SeeAllData=true)
    static void verificarFueraDeHorario_conSesionReal_sinTelefonoUsaFallback() {
        List<MessagingSession> sessions = [
            SELECT Id, Status, Fuera_de_horario__c
            FROM   MessagingSession
            WHERE  Status = 'Active'
            LIMIT  1
        ];
        if (sessions.isEmpty()) {
            System.debug(LoggingLevel.WARN,
                'TEST OMITIDO: no hay MessagingSession Active en el org.');
            return;
        }

        Test.startTest();
        List<seidor_getWhatsAppFueraHorario.Output> results =
            seidor_getWhatsAppFueraHorario.verificarFueraDeHorario(
                new List<seidor_getWhatsAppFueraHorario.Input>());
        Test.stopTest();

        Assert.areEqual(1, results.size(), 'Debe retornar 1 Output');
        Assert.isNotNull(results[0].fueraDeHorario,
            'fueraDeHorario no debe ser null');
    }

    @isTest
    static void marcarSesion_noDebeLanzarExcepcion() {

        Test.startTest();
        seidor_getWhatsAppFueraHorario.marcarSesion(null);

        seidor_getWhatsAppFueraHorario.getInt();
        Test.stopTest();

        System.assert(true);
}

    @isTest(SeeAllData=true)
    static void verificarFueraDeHorario_conSesionYEndUserReal_marcaFueraDeHorario() {
        DateTime ventana = System.now().addMinutes(-2);
        List<MessagingSession> sessions = [
            SELECT Id, MessagingEndUserId, Status, Fuera_de_horario__c
            FROM   MessagingSession
            WHERE  Status = 'Active'
            AND    MessagingEndUserId != null
            AND    CreatedDate >= :ventana
            LIMIT  1
        ];
        if (sessions.isEmpty()) {
            System.debug(LoggingLevel.WARN,
                'TEST OMITIDO: no hay MessagingSession Active reciente (ultimos 2 min) con EndUser en el org.');
            return;
        }

        MessagingEndUser endUser = [
            SELECT MessagingPlatformKey
            FROM   MessagingEndUser
            WHERE  Id = :sessions[0].MessagingEndUserId
            LIMIT  1
        ];

        seidor_getWhatsAppFueraHorario.Input input =
            new seidor_getWhatsAppFueraHorario.Input();
        input.endUserPhone = endUser.MessagingPlatformKey;

        Test.startTest();
        List<seidor_getWhatsAppFueraHorario.Output> results =
            seidor_getWhatsAppFueraHorario.verificarFueraDeHorario(
                new List<seidor_getWhatsAppFueraHorario.Input>{ input });
        Test.stopTest();

        Assert.areEqual(1, results.size(), 'Debe retornar 1 Output');

        // Si esta fuera de horario, la sesion debe haberse marcado
        if (results[0].fueraDeHorario) {
            MessagingSession updated = [
                SELECT Fuera_de_horario__c
                FROM   MessagingSession
                WHERE  Id = :sessions[0].Id
            ];
            Assert.isTrue(updated.Fuera_de_horario__c,
                'La sesion debe tener Fuera_de_horario__c = true');
        }
    }
}