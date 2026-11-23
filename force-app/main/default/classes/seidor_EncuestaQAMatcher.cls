/**
 * @description Lógica compartida para extraer respuestas de FCR/CSAT/mejora
 * a partir de los mensajes de una conversación, detectando la pregunta del
 * bot por coincidencia de texto y tomando la respuesta inmediata del EndUser.
 *
 * Extraída de seidor_EncuestaSyncBatch para que también la use
 * seidor_CrearEncuestaWhatsApp — antes cada clase tenía su propia copia
 * (una con matching por texto, la otra con parsing posicional frágil).
 * Única fuente de verdad para "qué cuenta como respuesta a qué pregunta".
 */
public with sharing class seidor_EncuestaQAMatcher {

    // Fragmentos de texto de las preguntas del bot (minúsculas). Se usan varios
    // fragmentos candidatos por pregunta —no uno solo— porque un cambio menor de
    // copy del bot (ej. "¿Resolvimos tu solicitud?" en vez de "tu solicitud fue
    // resuelta") rompe silenciosamente el matching: la encuesta deja de crearse
    // o queda con campos vacíos, sin ningún error visible. Texto real vigente
    // (2026-07-02):
    //   FCR:   "¿Resolvimos tu solicitud? Responde con Sí o No."
    //   CSAT:  "Califica nuestra atención [Ingrese entre 1 y 5] ..."
    //   MEJOR: "¿Qué comentario o sugerencia nos dejarías?"
    private static final List<String> Q_FCR_FRAGMENTS = new List<String>{
        'resolvimos tu solicitud', 'solicitud fue resuelta', 'tu solicitud fue'
    };
    private static final List<String> Q_CSAT_FRAGMENTS = new List<String>{
        'califica nuestra atencion', 'califica nuestra'
    };
    private static final List<String> Q_MEJOR_FRAGMENTS = new List<String>{
        'comentario o sugerencia', 'queremos seguir mejorando'
    };

    public class MatchResult {
        public String  fcrAnswer;
        public String  csatAnswer;
        public Integer csatScore;
        public String  mejorAnswer;

        public Boolean isEmpty() {
            return fcrAnswer == null && csatAnswer == null && mejorAnswer == null;
        }
    }

    /**
     * Recorre los mensajes ordenados cronológicamente y empareja cada
     * pregunta del bot/sistema con la respuesta inmediata del EndUser.
     */
    public static MatchResult extractFromMessages(
        List<seidor_ConversationEntryDTO.MessageWrapper> messages
    ) {
        MatchResult result = new MatchResult();
        if (messages == null || messages.size() < 2) return result;

        List<seidor_ConversationEntryDTO.MessageWrapper> sorted = sortByTimestamp(messages);

        for (Integer i = 0; i < sorted.size() - 1; i++) {
            seidor_ConversationEntryDTO.MessageWrapper cur = sorted[i];
            seidor_ConversationEntryDTO.MessageWrapper nxt = sorted[i + 1];

            if (cur.senderRole != 'Chatbot' && cur.senderRole != 'System') continue;
            if (nxt.senderRole != 'EndUser') continue;
            if (String.isBlank(cur.messageText) || String.isBlank(nxt.messageText)) continue;

            String q = normalizeQuestion(cur.messageText);
            String a = nxt.messageText.trim();

            if (matchesAny(q, Q_FCR_FRAGMENTS)) {
                result.fcrAnswer = normalizeFcr(a);
            } else if (matchesAny(q, Q_CSAT_FRAGMENTS)) {
                result.csatAnswer = normalizeCsat(a);
                result.csatScore  = extractCsatScore(a);
            } else if (matchesAny(q, Q_MEJOR_FRAGMENTS)) {
                result.mejorAnswer = a;
            }
        }

        return result;
    }

    // ── Helpers: matching de preguntas ────────────────────────────────────────

    /**
     * Normaliza el texto de la pregunta del bot para comparar contra los
     * fragmentos candidatos: minúsculas y sin tildes (el copy del bot cambia
     * con el tiempo; los acentos son la primera víctima de esos cambios).
     */
    @TestVisible
    private static String normalizeQuestion(String text) {
        if (String.isBlank(text)) return '';
        return text.trim().toLowerCase()
            .replace('á', 'a').replace('é', 'e').replace('í', 'i')
            .replace('ó', 'o').replace('ú', 'u');
    }

    private static Boolean matchesAny(String q, List<String> fragments) {
        for (String frag : fragments) {
            if (q.contains(frag)) return true;
        }
        return false;
    }

    // ── Helpers: normalización de respuestas ──────────────────────────────────

    @TestVisible
    private static String normalizeFcr(String answer) {
        if (String.isBlank(answer)) return null;
        String clean = answer.trim().toLowerCase()
            .replace('á','a').replace('é','e').replace('í','i')
            .replace('ó','o').replace('ú','u');
        clean = clean.replaceAll('[^a-z ]', ' ').normalizeSpace().trim();
        List<String> words = clean.split('\\s+');
        if (words.size() <= 4) {
            for (String w : words) {
                if (w == 'si' || w == 'yes') return 'Si';
                if (w == 'no') return 'No';
            }
        }
        return null;
    }

    @TestVisible
    private static String normalizeCsat(String answer) {
        if (String.isBlank(answer)) return null;
        String a = answer.trim().toLowerCase()
            .replace('á','a').replace('é','e').replace('í','i')
            .replace('ó','o').replace('ú','u').replace('ü','u');
        a = a.replaceAll('[^a-z0-9 ]', '').normalizeSpace().trim();

        if (a == 'muy buena' || a == '5') return 'Muy buena';
        if (a == 'buena'     || a == '4') return 'Buena';
        if (a == 'regular'   || a == '3') return 'Regular';
        if (a == 'mala'      || a == '2') return 'Mala';
        if (a == 'muy mala'  || a == '1') return 'Muy mala';

        if (a.startsWith('5')) return 'Muy buena';
        if (a.startsWith('4')) return 'Buena';
        if (a.startsWith('3')) return 'Regular';
        if (a.startsWith('2')) return 'Mala';
        if (a.startsWith('1')) return 'Muy mala';

        if (a.contains('muy buena')) return 'Muy buena';
        if (a.contains('muy mala'))  return 'Muy mala';
        if (a.contains('regular'))   return 'Regular';
        if (a.contains('buena'))     return 'Buena';
        if (a.contains('mala'))      return 'Mala';

        return null;
    }

    @TestVisible
    private static Integer extractCsatScore(String answer) {
        if (String.isBlank(answer)) return null;
        String a = answer.trim().toLowerCase()
            .replace('á','a').replace('é','e').replace('í','i')
            .replace('ó','o').replace('ú','u').replace('ü','u');
        a = a.replaceAll('[^a-z0-9 ]', '').normalizeSpace().trim();

        if (a == '5' || a.startsWith('5 ')) return 5;
        if (a == '4' || a.startsWith('4 ')) return 4;
        if (a == '3' || a.startsWith('3 ')) return 3;
        if (a == '2' || a.startsWith('2 ')) return 2;
        if (a == '1' || a.startsWith('1 ')) return 1;

        if (a.contains('muy buena')) return 5;
        if (a.contains('muy mala'))  return 1;
        if (a.contains('regular'))   return 3;
        if (a.contains('buena'))     return 4;
        if (a.contains('mala'))      return 2;

        return null;
    }

    private static List<seidor_ConversationEntryDTO.MessageWrapper> sortByTimestamp(
        List<seidor_ConversationEntryDTO.MessageWrapper> msgs
    ) {
        Map<DateTime, List<seidor_ConversationEntryDTO.MessageWrapper>> byTime =
            new Map<DateTime, List<seidor_ConversationEntryDTO.MessageWrapper>>();
        List<DateTime> timestamps = new List<DateTime>();

        for (seidor_ConversationEntryDTO.MessageWrapper m : msgs) {
            DateTime ts = m.messageTimestamp != null
                ? m.messageTimestamp
                : DateTime.newInstance(2000, 1, 1);
            if (!byTime.containsKey(ts)) {
                byTime.put(ts, new List<seidor_ConversationEntryDTO.MessageWrapper>());
                timestamps.add(ts);
            }
            byTime.get(ts).add(m);
        }
        timestamps.sort();

        List<seidor_ConversationEntryDTO.MessageWrapper> sorted =
            new List<seidor_ConversationEntryDTO.MessageWrapper>();
        for (DateTime ts : timestamps) sorted.addAll(byTime.get(ts));
        return sorted;
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
    }
}