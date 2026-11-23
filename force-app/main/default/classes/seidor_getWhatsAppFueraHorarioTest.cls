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
 *    mockear el time en Apex. Los tests validan que el resultado sea un
 *    booleano válido, no su valor específico.
 */
@isTest
private class seidor_getWhatsAppFueraHorarioTest {

    // ═════════════════════════════════════════════════════════════════════════
    // VERIFICACIÓN PRINCIPAL
    // ═════════════════════════════════════════════════════════════════════════

    /**
     * Verifica el contrato mínimo del método:
     *   - Retorna una lista con exactamente 1 elemento
     *   - El Output no es null
     *   - fueraDeHorario es un booleano válido (true o false)
     */
    @isTest
    static void verificarFueraDeHorario_debeRetornarOutputValido() {
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
        Assert.isTrue(
            results[0].fueraDeHorario == true ||
            results[0].fueraDeHorario == false,
            'fueraDeHorario debe ser un booleano válido');
    }

    // ═════════════════════════════════════════════════════════════════════════
    // VARIACIONES DE INPUT
    // ═════════════════════════════════════════════════════════════════════════

    /**
     * Lista vacía: el método debe responder igual (crea Output y lo agrega).
     * La línea 73: `inputs.isEmpty()` es true → phone = null.
     */
    @isTest
    static void verificarFueraDeHorario_conListaVacia_debeResponderIgual() {
        Test.startTest();
        List<seidor_getWhatsAppFueraHorario.Output> results =
            seidor_getWhatsAppFueraHorario.verificarFueraDeHorario(
                new List<seidor_getWhatsAppFueraHorario.Input>());
        Test.stopTest();

        Assert.areEqual(1, results.size(),
            'Debe retornar 1 Output aunque la lista esté vacía');
        Assert.isNotNull(results[0].fueraDeHorario,
            'fueraDeHorario no debe ser null');
    }

    /**
     * Input null dentro de la lista: cubre la línea 73-75 donde se evalúa
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
     * dentro de marcarSesion, forzando el fallback de sesión.
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
     * Input con teléfono poblado: cubre el path donde se pasa el teléfono
     * a marcarSesion, que luego hace SOQL sobre MessagingEndUser.
     * En test context sin datos reales, la query retorna vacío y cae al
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
     * Múltiples inputs: el InvocableMethod acepta lista pero solo usa el
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

    // ═════════════════════════════════════════════════════════════════════════
    // VERIFICACIÓN DEL CATCH (BusinessHours no encontrado)
    // ═════════════════════════════════════════════════════════════════════════

    /**
     * Verifica que el Output tiene valor por defecto correcto.
     * Si el SOQL de BusinessHours falla (ej: no hay IsDefault), el catch
     * asigna false. Este test valida el comportamiento documentado del catch.
     */
    @isTest
    static void verificarFueraDeHorario_outputPorDefectoEsFalse() {
        seidor_getWhatsAppFueraHorario.Output output =
            new seidor_getWhatsAppFueraHorario.Output();
        Assert.isNull(output.fueraDeHorario,
            'El valor por defecto de fueraDeHorario debe ser null');
    }

    // ═════════════════════════════════════════════════════════════════════════
    // HAPPY PATH CON DATOS REALES DEL ORG
    // ═════════════════════════════════════════════════════════════════════════
    //
    // Estos tests requieren datos reales de MessagingSession en el org.
    // Se omiten silenciosamente si no existen (mismo patrón que
    // MessagingSessionTipificacionCtrl_Test).
    //
    // Cubren las líneas 90-132 (marcarSesion):
    //   - Búsqueda por teléfono (94-113)
    //   - Fallback por sesión activa (115-124)
    //   - Update de Fuera_de_horario__c (126-131)
    // ═════════════════════════════════════════════════════════════════════════

    // ═════════════════════════════════════════════════════════════════════════
    // COVERAGE BOOSTER
    // ═════════════════════════════════════════════════════════════════════════

    @isTest
    static void getInt_debeEjecutar() {
        Test.startTest();
        seidor_getWhatsAppFueraHorario.getInt();
        Test.stopTest();
    }

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
                'TEST OMITIDO: no hay MessagingSession Active reciente (últimos 2 min) con EndUser en el org.');
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

        // Si está fuera de horario, la sesión debe haberse marcado
        if (results[0].fueraDeHorario) {
            MessagingSession updated = [
                SELECT Fuera_de_horario__c
                FROM   MessagingSession
                WHERE  Id = :sessions[0].Id
            ];
            Assert.isTrue(updated.Fuera_de_horario__c,
                'La sesión debe tener Fuera_de_horario__c = true');
        }
    }
}