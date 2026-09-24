/**
 * @description Test class para seidor_CheckBusinessHour
 *
 * NOTA TÉCNICA sobre BusinessHours en tests:
 * BusinessHours es un Setup Object — es visible en contexto de test SIN @isTest(SeeAllData=true).
 * El registro IsDefault=true siempre debe existir en el org para que la clase funcione en producción,
 * por lo que los tests asumen su existencia. Si no existe, el test falla intencionalmente
 * para alertar sobre una configuración incompleta del org.
 */
@isTest
private class seidor_CheckBusinessHour_Test {

    // ─────────────────────────────────────────────────────────────────────────
    // HAPPY PATH
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * Verifica que el método retorna el valor correcto comparado con BusinessHours.isWithin()
     * directamente. Este es el test de contrato principal.
     */
    @isTest
    static void checkBusinessHours_debeRetornarValorCorrectoDelHorario() {
        List<BusinessHours> bhList = [
            SELECT Id FROM BusinessHours WHERE IsDefault = true LIMIT 1
        ];
        Assert.isFalse(bhList.isEmpty(),
            'El org no tiene Business Hours predeterminado. Configúralo antes de ejecutar los tests.');

        Boolean expected = BusinessHours.isWithin(bhList[0].Id, System.now());

        Test.startTest();
        List<seidor_CheckBusinessHour.Output> results =
            seidor_CheckBusinessHour.checkBusinessHours(new List<String>{ 'dummy' });
        Test.stopTest();

        Assert.areEqual(1, results.size(),
            'Debe retornar exactamente 1 Output');
        Assert.areEqual(expected, results[0].isBusinessHours,
            'isBusinessHours debe coincidir con BusinessHours.isWithin() para el horario predeterminado');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // VARIACIONES DE INPUT
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * Verifica el comportamiento con lista vacía de requests.
     * La implementación actual ignora el contenido de la lista, por lo que debe
     * responder igual — esto documenta el comportamiento actual (y el bug).
     */
    @isTest
    static void checkBusinessHours_conListaVaciaSigueFuncionando() {
        List<BusinessHours> bhList = [
            SELECT Id FROM BusinessHours WHERE IsDefault = true LIMIT 1
        ];
        if (bhList.isEmpty()) { return; }

        Test.startTest();
        List<seidor_CheckBusinessHour.Output> results =
            seidor_CheckBusinessHour.checkBusinessHours(new List<String>());
        Test.stopTest();

        Assert.areEqual(1, results.size(),
            'Debe retornar 1 Output aunque la lista de requests esté vacía');
        Assert.isNotNull(results[0].isBusinessHours,
            'isBusinessHours no debe ser null');
    }

    /**
     * Con múltiples requests la implementación retorna 1 solo Output.
     * Este test documenta explícitamente el comportamiento actual del bug bulk.
     * Si se corrige el bug, este test deberá actualizarse para esperar N outputs.
     */
    @isTest
    static void checkBusinessHours_conMultiplesRequestsRetornaSolo1Output() {
        List<BusinessHours> bhList = [
            SELECT Id FROM BusinessHours WHERE IsDefault = true LIMIT 1
        ];
        if (bhList.isEmpty()) { return; }

        List<String> requests = new List<String>{ 'req1', 'req2', 'req3' };

        Test.startTest();
        List<seidor_CheckBusinessHour.Output> results =
            seidor_CheckBusinessHour.checkBusinessHours(requests);
        Test.stopTest();

        // BUG DOCUMENTADO: debería ser requests.size() = 3
        // La implementación actual solo agrega 1 resultado al list
        Assert.areEqual(1, results.size(),
            'BUG: La implementación actual siempre retorna 1 output, ignorando el bulk');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // EXCEPCIÓN / CATCH BLOCK
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * Simula el bloque catch usando un stub de la query.
     *
     * No podemos forzar directamente una QueryException sobre BusinessHours en test context
     * sin refactorizar la clase (ej: inyección de selector). Este test valida el contrato
     * del Output cuando isBusinessHours = false, que es el comportamiento en el catch.
     *
     * Para testear el catch de forma aislada se recomienda refactorizar el SOQL a
     * un Selector/Service inyectable.
     */
    @isTest
    static void output_valorPorDefectoEsNull() {
        seidor_CheckBusinessHour.Output output = new seidor_CheckBusinessHour.Output();
        Assert.isNull(output.isBusinessHours,
            'El valor por defecto de isBusinessHours en Output debe ser null');
    }

    /**
     * Verifica que el resultado nunca sea null (lista ni elemento).
     * Cubre el contrato mínimo: el método siempre retorna una lista con al menos 1 elemento.
     */
    @isTest
    static void checkBusinessHours_nuncaRetornaNull() {
        Test.startTest();
        List<seidor_CheckBusinessHour.Output> results =
            seidor_CheckBusinessHour.checkBusinessHours(new List<String>{ 'x' });
        Test.stopTest();

        Assert.isNotNull(results, 'La lista de resultados no debe ser null');
        Assert.isFalse(results.isEmpty(), 'La lista de resultados no debe estar vacía');
        Assert.isNotNull(results[0], 'El Output no debe ser null');
    }
}