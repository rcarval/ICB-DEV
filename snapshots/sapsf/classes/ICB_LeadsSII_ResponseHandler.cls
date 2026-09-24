/**********************************************************************************
Desarrollado por: SEIDOR
Autor: Rodrigo Carvallo (RCG)
Proyecto: Integracion SII Leads
Descripcion: Maneja evaluacion de respuesta SII y actualizacion de campos en Lead
Test: Pendiente

---------------------------------------------------------------------------------
No. Fecha                Autor                     Descripcion
------ ---------- ---------------------------------------------------------------
1.0 05-05-2026            RCG                Creacion de la clase.
**********************************************************************************/
public with sharing class ICB_LeadsSII_ResponseHandler {

    private static final String LOG_PREFIX = '[ICB_LeadsSII_ResponseHandler]';
    private static final Decimal MIN_SOCIAL_REASON_MATCH = 70;

    /**
    * Marca rechazo por validacion previa y persiste observacion en Lead.
    * @author Rodrigo Carvallo
    * @param Id leadId - ID de Lead afectado
    * @param ValidationResult vr - Resultado de validacion previa
    **/
    public static void applyValidationFailure(Id leadId, ICB_LeadsSII_IntegrationService.ValidationResult vr) {
        if (leadId == null) {
            return;
        }
        String msg = vr != null && vr.missingFields != null && !vr.missingFields.isEmpty()
            ? 'Faltan datos: ' + String.join(vr.missingFields, ', ')
            : 'Validacion fallida.';
        System.debug(LoggingLevel.WARN, LOG_PREFIX + ' leadId=' + leadId + ' | ' + msg);
        updateLeadResult(leadId, false, msg, null);
    }

    /**
    * Marca error tecnico de integracion y persiste observacion en Lead.
    * @author Rodrigo Carvallo
    * @param Id leadId - ID de Lead afectado
    * @param Exception ex - Excepcion capturada
    * @param String rut - RUT consultado
    **/
    public static void applyException(Id leadId, Exception ex, String rut) {
        if (leadId == null) {
            return;
        }
        String msg = ex == null ? 'Error desconocido en integracion SII.' : ex.getMessage();
        System.debug(LoggingLevel.ERROR, LOG_PREFIX + ' leadId=' + leadId + ' rut=' + rut + ' | ' + msg);
        updateLeadResult(leadId, false, 'Error consultando SII: ' + msg, null);
    }

    /**
    * Evalua respuesta SII, calcula aprobacion y actualiza campos en Lead.
    * @author Rodrigo Carvallo
    * @param Lead ld - Lead origen
    * @param SituacionTributariaDataDto data - Respuesta deserializada de SII
    * @param String rut - RUT consultado
    **/
    public static void applySIIResult(Lead ld, ICB_CalloutAPI_SII.SituacionTributariaDataDto data, String rut) {
        if (ld == null || ld.Id == null) {
            return;
        }

        List<String> observaciones = new List<String>();
        Boolean aprobado = true;

        if (data != null && data.inicio_actividades == false) {
            aprobado = false;
            String razonSii = data.razon_social;
            String razonSiiTexto = String.isBlank(razonSii) ? '(no informada por el servicio)' : razonSii.trim();
            observaciones.add(
                'Razon social en servicio SII: ' + razonSiiTexto + '. ' +
                'El contribuyente no tiene inicio de actividades ante el SII. No es posible crear el cliente.'
            );
        }

        Decimal matchPercent = similarityPercentage(ld.Company, data != null ? data.razon_social : null);
        if (matchPercent < MIN_SOCIAL_REASON_MATCH) {
            aprobado = false;
            String razonSii = data != null ? data.razon_social : null;
            String razonSiiTexto = String.isBlank(razonSii) ? '(no informada por el servicio)' : razonSii.trim();
            observaciones.add(
                'Razon social en servicio SII: ' + razonSiiTexto + '. ' +
                'Razon social con coincidencia insuficiente (' +
                String.valueOf(matchPercent.setScale(2)) +
                '%). Minimo requerido: ' + MIN_SOCIAL_REASON_MATCH + '%.'
            );
        }

        List<String> trueFlags = getTrueObservationFlags(data != null ? data.observaciones : null);
        if (!trueFlags.isEmpty()) {
            aprobado = false;
            observaciones.add('Observaciones SII activas: ' + String.join(trueFlags, ', '));
        }

        Decimal codigoActividad = extractFirstActivityCode(data);
        String observacionFinal = observaciones.isEmpty()
            ? 'Aprobado por validaciones SII.'
            : String.join(observaciones, ' | ');

        updateLeadResult(ld.Id, aprobado, observacionFinal, codigoActividad);
        System.debug(
            aprobado ? LoggingLevel.INFO : LoggingLevel.WARN,
            LOG_PREFIX + ' leadId=' + ld.Id + ' rut=' + rut + ' aprobado=' + aprobado +
            ' observacion=' + truncate(observacionFinal, 1000)
        );
    }

    /**
    * Extrae flags en true de observaciones SII con etiquetas legibles.
    * @author Rodrigo Carvallo
    **/
    private static List<String> getTrueObservationFlags(ICB_CalloutAPI_SII.ObservacionesDto obs) {
        List<String> trueFlags = new List<String>();
        if (obs == null) {
            return trueFlags;
        }

        JSONParser parser = JSON.createParser(JSON.serialize(obs));
        String currentField;
        while (parser.nextToken() != null) {
            if (parser.getCurrentToken() == JSONToken.FIELD_NAME) {
                currentField = parser.getText();
            } else if (
                currentField != null &&
                parser.getCurrentToken() == JSONToken.VALUE_TRUE
            ) {
                trueFlags.add(toReadableLabel(currentField));
            } else if (
                parser.getCurrentToken() != JSONToken.START_OBJECT &&
                parser.getCurrentToken() != JSONToken.END_OBJECT
            ) {
                currentField = null;
            }
        }
        return trueFlags;
    }

    /**
    * Convierte etiqueta tecnica con underscore a formato legible.
    * @author Rodrigo Carvallo
    **/
    private static String toReadableLabel(String apiName) {
        if (String.isBlank(apiName)) {
            return '';
        }
        List<String> words = apiName.replace('_', ' ').split('\\s+');
        List<String> normalizedWords = new List<String>();
        for (String word : words) {
            if (String.isBlank(word)) {
                continue;
            }
            String lower = word.toLowerCase();
            normalizedWords.add(lower.substring(0, 1).toUpperCase() + lower.substring(1));
        }
        return String.join(normalizedWords, ' ');
    }

    /**
    * Obtiene el primer codigo de actividad y lo convierte a numerico.
    * @author Rodrigo Carvallo
    **/
    private static Decimal extractFirstActivityCode(ICB_CalloutAPI_SII.SituacionTributariaDataDto data) {
        if (data == null || data.actividades == null || data.actividades.isEmpty()) {
            return null;
        }
        String code = data.actividades[0] != null ? data.actividades[0].codigo : null;
        if (String.isBlank(code)) {
            return null;
        }
        try {
            return Decimal.valueOf(code.trim());
        } catch (Exception ex) {
            return null;
        }
    }

    /**
    * Calcula porcentaje de similitud entre dos textos normalizados.
    * @author Rodrigo Carvallo
    **/
    private static Decimal similarityPercentage(String sourceA, String sourceB) {
        String a = normalizeText(sourceA);
        String b = normalizeText(sourceB);
        if (String.isBlank(a) && String.isBlank(b)) {
            return 100;
        }
        if (String.isBlank(a) || String.isBlank(b)) {
            return 0;
        }

        Integer distance = levenshteinDistance(a, b);
        Integer maxLen = Math.max(a.length(), b.length());
        if (maxLen == 0) {
            return 100;
        }
        Decimal score = (1 - ((Decimal) distance / maxLen)) * 100;
        if (score < 0) {
            return 0;
        }
        return score;
    }

    /**
    * Distancia de Levenshtein para comparar Company de Lead vs razon social SII.
    * @author Rodrigo Carvallo
    **/
    private static Integer levenshteinDistance(String a, String b) {
        Integer lenA = a.length();
        Integer lenB = b.length();
        List<Integer> prev = new List<Integer>();
        List<Integer> curr = new List<Integer>();
        for (Integer j = 0; j <= lenB; j++) {
            prev.add(j);
            curr.add(0);
        }

        for (Integer i = 1; i <= lenA; i++) {
            curr[0] = i;
            for (Integer j = 1; j <= lenB; j++) {
                Integer cost = a.substring(i - 1, i) == b.substring(j - 1, j) ? 0 : 1;
                Integer deletion = prev[j] + 1;
                Integer insertion = curr[j - 1] + 1;
                Integer substitution = prev[j - 1] + cost;
                curr[j] = Math.min(Math.min(deletion, insertion), substitution);
            }
            prev = curr.clone();
        }
        return prev[lenB];
    }

    /**
    * Normaliza texto (mayusculas, sin acentos y sin simbolos) para comparar.
    * @author Rodrigo Carvallo
    **/
    private static String normalizeText(String input) {
        if (String.isBlank(input)) {
            return '';
        }
        String s = input.toUpperCase();
        s = s.replace('Á', 'A').replace('É', 'E').replace('Í', 'I').replace('Ó', 'O').replace('Ú', 'U');
        s = s.replace('Ä', 'A').replace('Ë', 'E').replace('Ï', 'I').replace('Ö', 'O').replace('Ü', 'U');
        s = s.replace('Ñ', 'N');
        s = s.replaceAll('[^A-Z0-9 ]', ' ');
        s = s.replaceAll('\\s+', ' ').trim();
        return s;
    }

    /**
    * Actualiza campos de resultado SII sobre Lead.
    * Si está aprobado, persiste primero Aprobado_SII__c (y campos asociados) y luego convierte:
    * Database.convertLead relee el Lead en BD; la aprobación debe estar guardada para VR/triggers.
    * @author Rodrigo Carvallo
    **/
    private static void updateLeadResult(Id leadId, Boolean aprobado, String observacion, Decimal codigoActividad) {
        Lead upd = new Lead(Id = leadId);
        upd.Aprobado_SII__c = aprobado;
        upd.Observaciones_SII__c = observacion;
        if (codigoActividad != null) {
            upd.Codigo_Actividad_SII__c = codigoActividad;
        }

        if (aprobado == true) {
            update upd;

            ICB_LeadConversionService.ConversionResult convRes = convertLeadToAccount(leadId);
            Lead postUpd = new Lead(Id = leadId);
            if (convRes != null && convRes.success == true) {
                postUpd.Status = 'Prospecto';
                update postUpd;
            } else {
                String convMsg = convRes != null && !String.isBlank(convRes.message)
                    ? convRes.message
                    : 'Conversión no disponible.';
                postUpd.Observaciones_SII__c = observacion + ' | Conversión no realizada: ' + convMsg;
                System.debug(
                    LoggingLevel.WARN,
                    LOG_PREFIX + ' Lead aprobado por SII pero sin conversión. leadId=' + leadId + ' detalle=' + convMsg
                );
                update postUpd;
            }
        } else {
            update upd;
        }
    }

    /**
     * Intenta convertir el Lead y el mapeo post-conversión; no persiste cambios en el Lead llamador.
     * @return resultado de ICB_LeadConversionService o null si leadId es nulo
     */
    private static ICB_LeadConversionService.ConversionResult convertLeadToAccount(Id leadId) {
        if (leadId == null) {
            return null;
        }
        List<ICB_LeadConversionService.ConversionResult> conversionResults =
            ICB_LeadConversionService.convertAndMapLeads(new Set<Id>{ leadId });
        if (conversionResults.isEmpty()) {
            ICB_LeadConversionService.ConversionResult empty = new ICB_LeadConversionService.ConversionResult();
            empty.leadId = leadId;
            empty.success = false;
            empty.message = 'Sin resultado de conversión';
            return empty;
        }
        ICB_LeadConversionService.ConversionResult first = conversionResults[0];
        if (first.success != true) {
            System.debug(
                LoggingLevel.WARN,
                LOG_PREFIX + ' No se pudo convertir Lead ' + leadId + ': ' + first.message
            );
        }
        return first;
    }

    /**
    * Trunca texto largo para evitar logs excesivos.
    * @author Rodrigo Carvallo
    **/
    private static String truncate(String s, Integer maxLen) {
        if (String.isBlank(s) || maxLen == null || maxLen <= 0) {
            return s;
        }
        return s.length() > maxLen ? s.substring(0, maxLen) + '...' : s;
    }
}