/**
 * @description Genera archivos Excel (.xls) desde contenido HTML y los sirve
 * como ContentVersion para descarga. Los archivos se crean como versiones menores
 * y pueden limpiarse con un job programado si se acumulan.
 */
public with sharing class seidor_FileExportService {

    private static final Integer MAX_CONTENT_LENGTH = 5000000; // ~5MB, margen bajo el límite de heap síncrono (6MB)

    @AuraEnabled
    public static String createExcelFile(String htmlContent, String filename) {
        if (String.isBlank(htmlContent)) {
            throw new AuraHandledException('El contenido no puede estar vacío.');
        }
        if (htmlContent.length() > MAX_CONTENT_LENGTH) {
            throw new AuraHandledException('El reporte es demasiado grande para exportar. Reduce el rango de fechas o los filtros.');
        }

        // Excel abre este archivo como HTML sniffeado por la extensión .xls.
        // Sin un charset explícito, tildes y ñ pueden verse corruptos al abrir el archivo.
        String safeHtml = htmlContent.toLowerCase().contains('charset=')
            ? htmlContent
            : '<meta http-equiv="Content-Type" content="text/html; charset=UTF-8">' + htmlContent;

        ContentVersion cv = new ContentVersion(
            Title          = filename,
            PathOnClient   = filename + '.xls',
            VersionData    = Blob.valueOf(safeHtml),
            IsMajorVersion = false
        );

        try {
            insert cv;
        } catch (DmlException e) {
            throw new AuraHandledException('Error al generar el archivo: ' + e.getDmlMessage(0));
        }

        // cv.Id ya está poblado por la plataforma tras el insert; no se requiere un SOQL adicional.
        return cv.Id;
    }
}