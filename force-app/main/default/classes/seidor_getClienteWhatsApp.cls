/**
 * ICB Food Service
 * Desarrollado por : S.A
 * Fecha            : 2026-07-01
 * Descripción      : Controlador Apex para búsqueda de Account en el flujo WhatsApp.
 *                    Recibe un término libre y busca simultáneamente en:
 *                      - RUT__c            (RUT del cliente)
 *                      - C_digo_de_cliente__c  (Código alfanumérico, ej: FS21312)
 *                      - Name              (Nombre de la cuenta)
 *
 * Seguridad        : with sharing  → respeta sharing rules del usuario en sesión.
 *                    WITH USER_MODE → enforcea FLS/CRUD a nivel de query (API v57+).
 * Límites          : MAX_RESULTS = 50 registros para evitar timeouts y carga excesiva en UI.
 */
public with sharing class seidor_getClienteWhatsApp {

    private static final Integer MAX_RESULTS = 50;
    private static final Integer MIN_LENGTH  = 3;

    /**
     * Busca cuentas que coincidan con el término en cualquiera de los tres campos.
     *
     * @param  searchTerm  Texto libre: puede ser RUT, código de cliente o nombre parcial.
     * @return             Lista de Account con Id, Name, RUT__c y C_digo_de_cliente__c.
     * @throws AuraHandledException  Si el término es inválido o ocurre un error en SOQL.
     */
    @AuraEnabled
    public static List<Account> searchCliente(String searchTerm) {

        // ── Validaciones de entrada ──────────────────────────────────────────────
        if (String.isBlank(searchTerm)) {
            throw new AuraHandledException('El término de búsqueda no puede estar vacío.');
        }

        String term = searchTerm.trim();

        if (term.length() < MIN_LENGTH) {
            throw new AuraHandledException(
                'Ingresa al menos ' + MIN_LENGTH + ' caracteres para buscar.'
            );
        }

        // Previene SOQL injection antes de construir el LIKE
        // Nota: los bind variables con LIKE también requieren escapeSingleQuotes
        //       ya que el valor se interpola en tiempo de ejecución.
        String likeTerm = '%' + String.escapeSingleQuotes(term) + '%';

        // ── Consulta SOQL ────────────────────────────────────────────────────────
        try {
            List<Account> results = [
                SELECT
                    Id,
                    Name,
                    RUT__c,
                    C_digo_de_cliente__c,
                    Nombre_de_Fantasia__c
                FROM Account
                WHERE (
                    Name                  LIKE :likeTerm
                    OR RUT__c             LIKE :likeTerm
                    OR C_digo_de_cliente__c LIKE :likeTerm
                    OR Nombre_de_Fantasia__c LIKE :likeTerm
                )
                WITH USER_MODE
                ORDER BY Name ASC
                LIMIT :MAX_RESULTS
            ];

            return results;

        } catch (System.QueryException qe) {
            // Puede ocurrir si el usuario no tiene acceso al objeto/campos (FLS con USER_MODE)
            throw new AuraHandledException(
                'No tienes permisos para consultar cuentas o los campos requeridos. Detalle: '
                + qe.getMessage()
            );
        } catch (Exception e) {
            throw new AuraHandledException('Error inesperado al buscar clientes: ' + e.getMessage());
        }
    }
}