/**
 * @description DTOs para deserializar respuestas del endpoint:
 *   GET /services/data/v62.0/connect/conversation/{ConversationIdentifier}/entries
 *
 * ESTRUCTURA REAL DEL RESPONSE (validada en sandbox UAT):
 * {
 *   "conversationEntries": [{
 *     "identifier": "uuid",
 *     "messageText": "texto",
 *     "sender": { "role": "EndUser|Chatbot|System|Agent", "appType": "live_message|chatbot|conversation", "subject": "userId/phoneNumber" },
 *     "clientTimestamp": 1780537550156,      (epoch miliseconds)
 *     "serverReceivedTimestamp": 1780537550215,
 *     "clientDuration": 0,
 *     "relatedRecords": ["0MwOx..."]         (MessagingSession IDs relacionados)
 *   }]
 * }
 *
 * ROLES:
 *   EndUser  → cliente vía WhatsApp  (appType: live_message)
 *   Chatbot  → bot automatizado      (appType: chatbot)
 *   System   → mensajes del sistema  (appType: conversation)
 *   Agent    → agente humano         (appType: live_agent)
 */
public with sharing class seidor_ConversationEntryDTO {

    // ─── Response de la API ────────────────────────────────────────────────────

    public class ConversationEntriesResponse {
        @AuraEnabled public List<ConversationEntry> conversationEntries;
        @AuraEnabled public String  nextPageToken;
        @AuraEnabled public Boolean hasNextPage;
        @AuraEnabled public Boolean hasPreviousPage;
    }

    public class ConversationEntry {
        @AuraEnabled public String  identifier;
        @AuraEnabled public String  entryType;
        @AuraEnabled public String  messageText;
        @AuraEnabled public SenderInfo sender;
        @AuraEnabled public SenderInfo actor;
        @AuraEnabled public Long    clientTimestamp;
        @AuraEnabled public Long    serverReceivedTimestamp;
        @AuraEnabled public Integer clientDuration;
        @AuraEnabled public List<String> relatedRecords;
    }

    public class SenderInfo {
        @AuraEnabled public String role;      // EndUser | Chatbot | System | Agent
        @AuraEnabled public String appType;   // live_message | chatbot | conversation | live_agent
        @AuraEnabled public String subject;   // userId o número de teléfono del cliente
    }

    // ─── Wrapper simplificado para el LWC ─────────────────────────────────────

    public class MessageWrapper {
        @AuraEnabled public String   messageId;
        @AuraEnabled public String   conversationId;
        @AuraEnabled public String   sessionId;
        @AuraEnabled public String   senderRole;
        @AuraEnabled public String   senderName;
        @AuraEnabled public String   messageText;
        @AuraEnabled public DateTime messageTimestamp;
        @AuraEnabled public String   rawTimestamp;
    }

    public class SessionWithMessages {
        @AuraEnabled public String   sessionId;
        @AuraEnabled public String   conversationId;
        @AuraEnabled public String   conversationUUID;
        @AuraEnabled public String   status;
        @AuraEnabled public String   endUserId;
        @AuraEnabled public String   channelId;
        @AuraEnabled public DateTime startTime;
        @AuraEnabled public DateTime endTime;
        @AuraEnabled public List<MessageWrapper> messages;
        @AuraEnabled public Integer  totalMessages;
        @AuraEnabled public Integer  agentMessages;
        @AuraEnabled public Integer  userMessages;
        @AuraEnabled public Integer  botMessages;
    }
}