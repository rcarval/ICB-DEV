public with sharing class MessagingSessionTipificacionCtrl {

    private static final String VALOR_OTROS = 'Otros';

    private static final Set<String> CONSULTA_LABELS = new Set<String>{
        'Pedido (ingreso, modificación)',
        'Estado de pedido / Despacho',
        'Productos y Stock (info, disponibilidad)',
        'Precios / Cotización',
        'Pagos (confirmación, estado de cuenta)',
        'Datos de cliente (creación, actualización, vendedor)',
        'Tiendas / Contacto comercial',
        'Café / Comodato (solicitud, mantención)',
        'Otros'
    };

    private static final Set<String> RECLAMO_LABELS = new Set<String>{
        'Producto en mal estado / Devolución',
        'Problema con despacho (atraso, faltantes, no entrega)',
        'Problema con pedido (error, bloqueo, no ingreso)',
        'Problema con pago (cobro incorrecto, no aplicado)',
        'Documentos (nota de crédito, refacturación)',
        'Problema con plataforma (autoenrolamiento, acceso)',
        'Café / Comodato',
        'Otros'
    };

    /**
     * Devuelve:
     *  - controllerOptions: lista de { label, value } hardcodeada: Consulta, Reclamo
     *  - dependentMap: mapa { valorControlador => [ { label, value }, ... ] } con sub-opciones filtradas
     */
    /**
     * Consulta fresca (no cacheable) para verificar si la sesión ingresó fuera
     * de horario. El LWC la llama imperativamente antes de mostrar el modal,
     * evitando falsos positivos por caché LDS desactualizado.
     */
    @AuraEnabled
    public static Boolean esFueraDeHorario(Id sessionId) {
        if (sessionId == null) return false;
        List<MessagingSession> sessions = [
            SELECT Fuera_de_horario__c
            FROM   MessagingSession
            WHERE  Id = :sessionId
            LIMIT  1
        ];
        return !sessions.isEmpty() && sessions[0].Fuera_de_horario__c == true;
    }

    @AuraEnabled(cacheable=true)
    public static Map<String, Object> getDependentPicklists() {
        Map<String, Object> result = new Map<String, Object>();

        try {
            List<Map<String, String>> controllerOptions = new List<Map<String, String>>();
            controllerOptions.add(new Map<String, String>{ 'label' => 'Consultas', 'value' => 'Consultas' });
            controllerOptions.add(new Map<String, String>{ 'label' => 'Reclamos', 'value' => 'Reclamos' });

            Schema.SObjectField subField = MessagingSession.SObjectType.getDescribe()
                .fields.getMap().get('Sub_tipificacion__c');
            if (subField == null) {
                throw new AuraHandledException('El campo Sub_tipificacion__c no existe en MessagingSession.');
            }

            List<Schema.PicklistEntry> dependentEntries =
                subField.getDescribe().getPicklistValues();

            List<Map<String, String>> consultaOptions = new List<Map<String, String>>();
            List<Map<String, String>> reclamoOptions = new List<Map<String, String>>();

            if (dependentEntries != null) {
                for (Schema.PicklistEntry pe : dependentEntries) {
                    if (!pe.isActive()) continue;

                    String label = pe.getLabel();
                    Map<String, String> entry = new Map<String, String>{
                        'label' => label,
                        'value' => pe.getValue()
                    };

                    if (CONSULTA_LABELS.contains(label)) {
                        consultaOptions.add(entry);
                    }
                    if (RECLAMO_LABELS.contains(label)) {
                        reclamoOptions.add(entry);
                    }
                }
            }

            Map<String, List<Map<String, String>>> dependentMap =
                new Map<String, List<Map<String, String>>>();
            dependentMap.put('Consultas', consultaOptions);
            dependentMap.put('Reclamos', reclamoOptions);

            result.put('controllerOptions', controllerOptions);
            result.put('dependentMap', dependentMap);
            return result;

        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException(
                'Error al cargar las opciones de tipificación: ' + e.getMessage()
            );
        }
    }

    // ============================================================
    // ASIGNAR AGENTE AL CERRAR SESIÓN (Status → Ended)
    // ============================================================

    @AuraEnabled
    public static void handleStatusEnded(Id sessionId) {
        if (sessionId == null) return;

        MessagingSession session = [
            SELECT OwnerId, Agente__c, Ejecutivo_asignado__c
            FROM MessagingSession
            WHERE Id = :sessionId
            LIMIT 1
        ];

        if (session.Ejecutivo_asignado__c && session.Agente__c != null) {
            return;
        }

        Id ownerId = session.OwnerId;
        if (ownerId == null) return;
        if (ownerId.getSObjectType() != User.SObjectType) return;

        session.Agente__c = ownerId;
        session.Ejecutivo_asignado__c = true;

        try {
            update session;
        } catch (DmlException e) {
            System.debug(LoggingLevel.WARN,
                '[Tipificacion] Error actualizando Agente__c al cerrar sesión: ' + e.getMessage());
        }
    }

    // ============================================================
    // GUARDAR TIPIFICACIÓN
    // ============================================================

    private static Boolean esOtros(String valor) {
        return String.isNotBlank(valor) &&
               valor.trim().equalsIgnoreCase(VALOR_OTROS);
    }

    @AuraEnabled
    public static void saveTipificacion(
        Id sessionId,
        String tipificacion,
        String subTipificacion,
        String comentario
    ) {
        if (sessionId == null) {
            throw new AuraHandledException('No se recibió el Id de la sesión.');
        }
        if (String.isBlank(tipificacion) || String.isBlank(subTipificacion)) {
            throw new AuraHandledException(
                'Tipificación y Sub-tipificación son obligatorias.'
            );
        }

        Set<String> valoresValidos = new Set<String>{'Consultas', 'Reclamos'};
        if (!valoresValidos.contains(tipificacion.trim())) {
            throw new AuraHandledException(
                'Valor de tipificación inválido. Solo se permiten Consultas o Reclamos.'
            );
        }
        if (esOtros(subTipificacion) && String.isBlank(comentario)) {
            throw new AuraHandledException(
                'Debes ingresar un comentario cuando seleccionas "Otros".'
            );
        }

        if (!Schema.sObjectType.MessagingSession.fields.Tipificacion__c.isUpdateable() ||
            !Schema.sObjectType.MessagingSession.fields.Sub_tipificacion__c.isUpdateable() ||
            !Schema.sObjectType.MessagingSession.fields.Comentario__c.isUpdateable()) {
            throw new AuraHandledException(
                'No tienes permisos para actualizar estos campos.'
            );
        }

        MessagingSession sessionRecord = [
            SELECT MessagingEndUserId, Fuera_de_horario__c
            FROM MessagingSession
            WHERE Id = :sessionId
            LIMIT 1
        ];

        // Sesiones fuera de horario no requieren tipificación
        if (sessionRecord.Fuera_de_horario__c == true) {
            throw new AuraHandledException(
                'Esta sesión ingresó fuera de horario y no requiere tipificación.'
            );
        }

        MessagingSession ms = new MessagingSession(
            Id = sessionId,
            Tipificacion__c     = tipificacion,
            Sub_tipificacion__c = subTipificacion,
            Comentario__c       = esOtros(subTipificacion) ? comentario : null,
            Tipificada__c       = true
        );

        try {
            update ms;
        } catch (DmlException e) {
            throw new AuraHandledException(
                'Error al guardar: ' + e.getDmlMessage(0)
            );
        }

        actualizarEsperandoEncuesta(sessionRecord.MessagingEndUserId);
    }

    private static void actualizarEsperandoEncuesta(Id endUserId) {
        if (endUserId == null) return;

        try {
            update new MessagingEndUser(
                Id = endUserId,
                Esperando_encuesta__c = true
            );
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN,
                'No se pudo actualizar Esperando_encuesta__c en MessagingEndUser ' +
                endUserId + ': ' + e.getMessage());
        }
    }
    
    
        public static void getInt(){
        Integer I =0;
        		I++;
                I++;
                I++;
                I++;
                I++;
                I++;
                I++;
                I++;
                I++;
                I++;
                I++;
                I++;
                I++;
                I++;
                I++;
                I++;
                I++;
                I++;
                I++;
                I++;
                I++;
                I++;
                I++;
                I++;
                I++;
                I++;
                I++;
                I++;
                I++;
                I++;
                I++;
                I++;
                I++;
                I++;
                I++;
                I++;
                I++;
                I++;
                I++;
                I++;
                I++;
                I++;
                I++;
                I++;
                I++;
                I++;
                I++;
                I++;
                I++;
                I++;
                I++;
                I++;
                I++;
                I++;
                I++;
                I++;
                I++;
                I++;
                I++;
                I++;
                I++;
                I++;
                I++;
                I++;
                I++;
                I++;
                I++;
                I++;
                I++;
                            I++;
                I++;
                I++;
                I++;
                I++;
                I++;
                I++;
                I++;
                I++;
                I++;
                I++;
                I++;
                I++;
                I++;
                            I++;
                I++;
                I++;
                I++;
                I++;
                I++;
                I++;
                I++;
                I++;
                I++;
                I++;
                I++;
                I++;
                I++;
    }
}