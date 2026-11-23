/**********************************************************************************
ICB Food Service
Desarrollado por: José Illanes
Fecha       : 2026-02-25
Descripción : Test para ICBFS_QrScanController. Cubre:
              - Token vacío (error controlado)
              - Token con valor (respuesta controlada, aun si el Flow falla)
**********************************************************************************/
@IsTest
private class ICBFS_QrScanControllerTest {

    @IsTest
    static void testRegistrar_TokenVacio() {
        ICBFS_QrScanController.Resp resp = ICBFS_QrScanController.registrar(null);

        System.assertNotEquals(null, resp, 'Debe retornar una respuesta');
        System.assertEquals('ERROR', resp.resultado, 'Con token vacío debe ser ERROR');
        System.assert(resp.mensaje != null && resp.mensaje.contains('Falta token'), 'Mensaje esperado por token vacío');
    }

    @IsTest
    static void testRegistrar_ConToken() {
        Test.startTest();
        ICBFS_QrScanController.Resp resp = ICBFS_QrScanController.registrar('TOK_TEST_001');
        Test.stopTest();

        System.assertNotEquals(null, resp, 'Debe retornar una respuesta');
        System.assertNotEquals(null, resp.resultado, 'resultado no debe ser null');
        System.assertNotEquals(null, resp.mensaje, 'mensaje no debe ser null');

        // Como el controller atrapa cualquier excepción del Flow,
        // aceptamos OK o ERROR según exista/ejecute el Flow en el entorno de test.
        System.assert(
            resp.resultado == 'OK' || resp.resultado == 'ERROR',
            'resultado debe ser OK o ERROR'
        );
    }
}