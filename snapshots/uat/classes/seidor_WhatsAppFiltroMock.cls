@isTest
public class seidor_WhatsAppFiltroMock implements HttpCalloutMock {
    
    private Boolean isError;
    private Boolean hasNextPage;

    public seidor_WhatsAppFiltroMock(Boolean isError, Boolean hasNextPage) {
        this.isError = isError;
        this.hasNextPage = hasNextPage;
    }

    public HttpResponse respond(HttpRequest request) {
        HttpResponse response = new HttpResponse();
        response.setHeader('Content-Type', 'application/json');

        if (this.isError) {
            response.setStatusCode(400);
            response.setBody('{"error": "Bad Request"}');
        } else {
            response.setStatusCode(200);
            
            // Si tiene página siguiente, envía nextPageToken
            Boolean isSecondPage = request.getEndpoint().contains('pageParam');
            String nextPageJson = (this.hasNextPage && !isSecondPage) 
                ? ',"nextPageToken": "token2", "hasNextPage": true' 
                : ',"hasNextPage": false';

            String jsonBody = '{' +
                '"conversationEntries": [' +
                    '{' +
                        '"identifier": "msg-001",' +
                        '"messageText": "Hola, necesito ayuda con mi pedido",' +
                        '"sender": {"role": "EndUser", "subject": "Cliente Test"},' +
                        '"serverReceivedTimestamp": 1782855294043' +
                    '}' +
                ']' +
                nextPageJson +
            '}';

            response.setBody(jsonBody);
        }
        return response;
    }
}