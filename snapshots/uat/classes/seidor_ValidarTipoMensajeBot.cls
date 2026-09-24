global class seidor_ValidarTipoMensajeBot {

    /**
     * Metodo invocable desde Einstein Bot como Accion Apex.
     * Detecta si el ultimo mensaje del cliente en la sesion
     * es texto, imagen o archivo adjunto.
     *
     * Logica de deteccion para WhatsApp (Salesforce Messaging):
     *   - EntryType = 'Message' con Message no vacio  -> TEXTO
     *   - EntryType = 'Message' con Message vacio/null -> IMAGEN (adjunto)
     *   - Cualquier otro EntryType                    -> VACIO
     */
    @InvocableMethod(label='Validar Tipo de Mensaje Entrante'
                     description='Detecta si el mensaje del cliente es texto, imagen o archivo')
    global static List<OutputVariables> validarMensaje(List<InputVariables> inputs) {

        List<OutputVariables> resultados = new List<OutputVariables>();

        for (InputVariables input : inputs) {
            OutputVariables output = new OutputVariables();

            try {
                MessagingSession session = [
                    SELECT ConversationId
                    FROM MessagingSession
                    WHERE Id = :input.routableId
                    LIMIT 1
                ];

                if (session.ConversationId == null) {
                    output.tipoMensaje = 'VACIO';
                    output.esImagen    = false;
                    output.esTexto     = false;
                    resultados.add(output);
                    continue;
                }

                List<ConversationEntry> entries = [
                    SELECT Id, EntryType, Message
                    FROM ConversationEntry
                    WHERE ConversationId = :session.ConversationId
                      AND ActorType = 'EndUser'
                    ORDER BY CreatedDate DESC
                    LIMIT 1
                ];

                if (entries.isEmpty()) {
                    output.tipoMensaje = 'VACIO';
                    output.esImagen    = false;
                    output.esTexto     = false;
                } else {
                    ConversationEntry entry = entries[0];
                    String msgContent = entry.Message;

                    if (entry.EntryType == 'Message' && String.isNotBlank(msgContent)) {
                        // Caso 1: Texto plano
                        output.tipoMensaje = 'TEXTO';
                        output.esImagen    = false;
                        output.esTexto     = true;

                    } else if (entry.EntryType == 'Message' && String.isBlank(msgContent)) {
                        // Caso 2: Adjunto (imagen o archivo)
                        // WhatsApp deja Message vacio cuando envia adjuntos
                        output.tipoMensaje = 'IMAGEN';
                        output.esImagen    = true;
                        output.esTexto     = false;

                    } else {
                        // Caso 3: Tipo desconocido
                        output.tipoMensaje = 'VACIO';
                        output.esImagen    = false;
                        output.esTexto     = false;
                    }
                }

            } catch (Exception e) {
                output.tipoMensaje = 'ERROR';
                output.esImagen    = false;
                output.esTexto     = false;
                System.debug('ValidarTipoMensajeBot ERROR: ' + e.getMessage());
            }

            resultados.add(output);
        }

        return resultados;
    }

    global class InputVariables {
        @InvocableVariable(label='ID de Sesion de Mensajeria'
                           description='Variable de contexto RoutableId que el bot rellena automaticamente'
                           required=true)
        global String routableId;  // ← cambiado de Id a String
    }

    global class OutputVariables {
        @InvocableVariable(label='Tipo de Mensaje'
                           description='TEXTO | IMAGEN | VACIO | ERROR')
        global String tipoMensaje;

        @InvocableVariable(label='Es Imagen'
                           description='True si el mensaje es una imagen o adjunto')
        global Boolean esImagen;

        @InvocableVariable(label='Es Texto'
                           description='True si el mensaje es texto plano')
        global Boolean esTexto;
    }
}