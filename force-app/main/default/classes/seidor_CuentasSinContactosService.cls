/**
 * ICB Food Service
 * Desarrollado por : S.A
 * Fecha            : 2026-08-23
 * Descripción      : Servicio que retorna las cuentas hijas de tipo registro
 *                    "Sucursal" SIN contacto asociado directamente, agrupadas
 *                    por su cuenta principal. Para cada fila expone el detalle
 *                    de si los contactos viven en la cuenta principal
 *                    (herencia hacia arriba) o si no hay ninguno disponible.
 *                    Consumido por el LWC cuentasSinContactos.
 *
 * Seguridad        : with sharing  → respeta sharing rules del usuario.
 *                    WITH USER_MODE / AccessLevel.USER_MODE → FLS/CRUD.
 * Escalabilidad    : keyset pagination (WHERE Id > :anchor), streaming por
 *                    chunks en totales (las agregadas GROUP BY no soportan
 *                    queryMore) y export CSV server-side vía ContentVersion.
 */
public with sharing class seidor_CuentasSinContactosService {

    private static final Integer PAGE_SIZE_DEFAULT = 200;
    private static final Integer PAGE_SIZE_MAX     = 500;
    private static final Integer BATCH_SIZE        = 2000;
    private static final Integer EXPORT_MAX_FILAS  = 50000;

    // Tope del HTML del reporte. Pico de heap ≈ 3x este valor (fragmentos +
    // String.join + Blob.valueOf) → 1,2MB mantiene el pico ~3,6MB < 6MB.
    private static final Long    EXPORT_MAX_CHARS  = 1200000;

    // Techo de grupos escaneados para "cuentas principales distintas" del
    // resumen. Si se alcanza, la métrica se reporta como N/D (-1).
    private static final Integer RESUMEN_MAX_PRINCIPALES_SCAN = 20001;

    // Dirección organizacional (Org-Wide Address verificada) desde la que se
    // envía el correo al asesor. Se resuelve por Address y NO por Id porque
    // el Id cambia entre sandboxes y producción.
    private static final String CORREO_REMITENTE        = 'comunicaciones@icbfs.cl';

    // Máximo de destinatarios en copia (CC) aceptado por la acción.
    private static final Integer MAX_CORREOS_CC         = 10;

    // Puntos de extensión para tests (@TestVisible)
    @TestVisible private static String direccionRemitenteOverride;
    @TestVisible private static Id  orgWideAddressIdTest;
    @TestVisible private static List<Messaging.SingleEmailMessage> correosCapturados;

    /**
     * DeveloperName del RecordType de cuentas Sucursal.
     * Se resuelve por DeveloperName y NO por Id porque el Id de RecordType
     * cambia entre sandboxes y producción.
     */
    private static final String SUCURSAL_RT_DEVNAME = 'Sucursal';

    private static String sucursalRtIdCache;

    /**
     * Fila plana por cuenta Sucursal sin contacto directo.
     */
    public class CuentaRow {
        @AuraEnabled public String  accountId;
        @AuraEnabled public String  accountName;
        @AuraEnabled public String  recordTypeName;
        @AuraEnabled public String  rut;
        @AuraEnabled public String  codigoCliente;
        @AuraEnabled public String  nombreFantasia;

        // Cuenta principal (agrupación)
        @AuraEnabled public String  parentAccountId;
        @AuraEnabled public String  parentAccountName;
        @AuraEnabled public String  parentRut;
        @AuraEnabled public String  parentCodigoCliente;
        @AuraEnabled public String  parentNombreFantasia;
        @AuraEnabled public String  parentOwnerId;
        @AuraEnabled public String  parentOwnerName;
        @AuraEnabled public String  parentOwnerEmail;

        // Detalle: contactos que viven en la cuenta principal
        @AuraEnabled public Boolean padreConContactos;
        @AuraEnabled public Integer contactoCountPadre;
        @AuraEnabled public List<ContactoDTO> contactosPadre;
    }

    public class ContactoDTO {
        @AuraEnabled public String id;
        @AuraEnabled public String name;
        @AuraEnabled public String email;
    }

    /** Sobre de una página: filas + cursor de continuación. */
    public class ResultadoPagina {
        @AuraEnabled public List<CuentaRow> filas;
        @AuraEnabled public String nextAnchor;
    }

    /**
     * Totales globales. Un valor -1 = métrica no disponible (límites de
     * plataforma); el LWC lo muestra como N/D.
     */
    public class ResultadoTotales {
        @AuraEnabled public Integer totalCuentas;
        @AuraEnabled public Integer conRespaldoPadre;
        @AuraEnabled public Integer sinRespaldoPadre;
        @AuraEnabled public Integer cuentasPrincipales;
        @AuraEnabled public List<ResumenAsesor> topAsesores;
    }

    /** Fila del top de asesores del resumen (Owner de la cuenta principal). */
    public class ResumenAsesor {
        @AuraEnabled public String  nombre;
        @AuraEnabled public Integer cantidad;
    }

    public class ExcelResult {
        @AuraEnabled public String  versionId;   // ContentVersion para descarga
        @AuraEnabled public Integer filas;
        @AuraEnabled public Boolean truncado;
    }

    /**
     * Constructor incremental del HTML del reporte. Acumula fragmentos y
     * corta en cuanto se supera el tope de caracteres, para que el heap
     * nunca supere ~3x el tope (fragmentos + join + Blob) bajo los 6MB.
     */
    private class ExcelBuilder {
        List<String> partes = new List<String>();
        Long chars   = 0;
        Boolean lleno = false;
        Integer conRespaldo = 0;

        void addGrupo(List<CuentaRow> grupo) {
            if (lleno || grupo.isEmpty()) { return; }

            // Celda Asesor combinada para TODO el grupo (el buffer llega
            // cerrado: todas las filas comparten Parent.OwnerId).
            String celdaAsesor =
                '<td rowspan="' + grupo.size() + '"><span class="asesor">'
                + esc(grupo[0].parentOwnerName) + '</span></td>';

            Boolean primeraFilaDelGrupo = true;

            // Bloques contiguos por cuenta principal dentro del asesor.
            Integer i = 0;
            while (i < grupo.size() && !lleno) {
                Integer j = i;
                while (j < grupo.size()
                       && grupo[j].parentAccountId == grupo[i].parentAccountId) {
                    j++;
                }
                Integer spanPrincipal = j - i;

                if (grupo[i].padreConContactos) { conRespaldo += spanPrincipal; }

                String padreCell =
                    '<td rowspan="' + spanPrincipal + '">'
                    + esc(grupo[i].parentAccountName) + '<br>';
                if (String.isNotBlank(grupo[i].parentRut)) {
                    padreCell += '<span class="meta">RUT: ' + esc(grupo[i].parentRut) + '</span><br>';
                }
                if (String.isNotBlank(grupo[i].parentCodigoCliente)) {
                    padreCell += '<span class="meta">Cód. cliente: ' + esc(grupo[i].parentCodigoCliente) + '</span><br>';
                }
                if (String.isNotBlank(grupo[i].parentNombreFantasia)) {
                    padreCell += '<span class="meta">Fantasía: ' + esc(grupo[i].parentNombreFantasia) + '</span>';
                }
                padreCell += '</td>';

                addFila(grupo[i], padreCell, (primeraFilaDelGrupo ? celdaAsesor : ''));
                primeraFilaDelGrupo = false;
                for (Integer k = i + 1; k < j && !lleno; k++) {
                    addFila(grupo[k], '', '');
                }
                i = j;
            }
        }

        private void addFila(CuentaRow r, String padreCell, String celdaAsesor) {
            String hijaCell = '<td>' + esc(r.accountName) + '<br>';
            if (String.isNotBlank(r.nombreFantasia)) {
                hijaCell += '<span class="meta">' + esc(r.nombreFantasia) + '</span><br>';
            }
            if (String.isNotBlank(r.codigoCliente)) {
                hijaCell += '<span class="meta">' + esc(r.codigoCliente) + '</span>';
            }
            hijaCell += '</td>';

            String detalleCell;
            if (r.padreConContactos) {
                detalleCell = '<td><p class="msg">Esta cuenta de tipo de registro '
                    + esc(r.recordTypeName) + ' no posee contactos directos</p>'
                    + '<p class="sub">Contactos asociados a la cuenta principal «'
                    + esc(r.parentAccountName) + '»: ' + r.contactoCountPadre + '</p>';
                for (ContactoDTO c : r.contactosPadre) {
                    detalleCell += '<div>' + esc(c.name)
                        + (String.isBlank(c.email) ? '' : ' (' + esc(c.email) + ')')
                        + '</div>';
                }
                detalleCell += '</td>';
            } else {
                detalleCell = '<td><span class="sin">Sin contactos asociados</span></td>';
            }

            String frag = '<tr>' + celdaAsesor + padreCell + hijaCell + detalleCell + '</tr>';
            partes.add(frag);
            chars += frag.length();
            if (chars > EXPORT_MAX_CHARS) { lleno = true; }
        }
    }

    /**
     * Retorna una página de sucursales sin contacto directo, ordenada por
     * asesor (Owner de la principal), cuenta principal e Id, con búsqueda
     * opcional sobre sus datos y los de su cuenta principal. Keyset por la
     * tupla (Parent.OwnerId, ParentId, Id) para que cada grupo de asesor y
     * cada bloque de principal queden contiguos entre páginas.
     */
    @AuraEnabled(cacheable=true)
    public static ResultadoPagina getCuentasPaginadas(String searchTerm,
                                                      String anchorId,
                                                      Integer pageSize) {
        Id rt = sucursalRecordTypeId();
        if (rt == null) {
            throw new AuraHandledException(
                'No existe un tipo de registro de Cuenta con nombre de desarrollador "' +
                SUCURSAL_RT_DEVNAME + '". Verifique la configuración de la org.');
        }

        String q        = null;
        Boolean filtrar = !String.isBlank(searchTerm);
        if (filtrar) { q = likeEscape(searchTerm); }

        Integer lim = (pageSize == null || pageSize < 1)
                      ? PAGE_SIZE_DEFAULT
                      : Math.min(pageSize, PAGE_SIZE_MAX);

        // Ancla compuesta "ownerId|parentId|id" (los Ids nunca contienen '|').
        Id anchorOid = null;
        Id anchorPid = null;
        Id anchorAid = null;
        if (!String.isBlank(anchorId)) {
            List<String> partesAncla = anchorId.split('\\|');
            if (partesAncla.size() == 3) {
                try {
                    anchorOid = Id.valueOf(partesAncla[0]);
                    anchorPid = Id.valueOf(partesAncla[1]);
                    anchorAid = Id.valueOf(partesAncla[2]);
                } catch (Exception e) {
                    anchorOid = null;   // ancla inválida → reinicia del inicio
                }
            }
        }
        Boolean conAncla = (anchorOid != null && anchorPid != null && anchorAid != null);

        String soql =
            'SELECT Id, Name, RecordType.Name, RUT__c, C_digo_de_cliente__c, ' +
            '       Nombre_de_Fantasia__c, ParentId, Parent.OwnerId, Parent.Owner.Name, ' +
            '       Parent.Owner.Email, ' +
            '       Parent.Name, Parent.RUT__c, ' +
            '       Parent.C_digo_de_cliente__c, Parent.Nombre_de_Fantasia__c ' +
            'FROM Account ' +
            'WHERE RecordTypeId = :rt AND ParentId != null ' +
            '  AND Id NOT IN (SELECT AccountId FROM Contact)' +
            (filtrar ? ' AND ' + filtroTexto() : '') +
            (conAncla
                ? ' AND (Parent.OwnerId > :anchorOid ' +
                  '   OR (Parent.OwnerId = :anchorOid AND (' +
                  '       ParentId > :anchorPid OR' +
                  '      (ParentId = :anchorPid AND Id > :anchorAid))))'
                : '') +
            ' ORDER BY Parent.OwnerId ASC, ParentId ASC, Id ASC LIMIT :lim';

        List<Account> cuentas = Database.query(soql, AccessLevel.USER_MODE);

        ResultadoPagina res = new ResultadoPagina();
        res.filas = construirFilas(cuentas);
        if (cuentas.size() == lim) {
            Account ultima = cuentas[cuentas.size() - 1];
            res.nextAnchor = String.valueOf(ultima.Parent?.OwnerId) + '|'
                             + String.valueOf(ultima.ParentId) + '|'
                             + String.valueOf(ultima.Id);
        } else {
            res.nextAnchor = null;
        }
        return res;
    }

    /**
     * Totales globales del universo filtrado, en transacción aparte para no
     * bloquear el render de la tabla. Solo COUNT(): escala a cualquier tamaño
     * de org sin consumir filas de query (límite 50k) ni CPU.
     */
    @AuraEnabled(cacheable=true)
    public static ResultadoTotales getTotales(String searchTerm) {
        return calcularResumen(searchTerm);
    }

    /**
     * Métricas del resumen sobre TODO el universo filtrado. Compartida entre
     * getTotales (badges/tabla resumen del LWC) y exportarExcel (sección
     * Resumen del archivo). Cada métrica degrada de forma independiente:
     * -1 = no disponible, topAsesores vacío = no disponible.
     */
    private static ResultadoTotales calcularResumen(String searchTerm) {
        ResultadoTotales t   = new ResultadoTotales();
        t.totalCuentas       = -1;
        t.conRespaldoPadre   = -1;
        t.sinRespaldoPadre   = -1;
        t.cuentasPrincipales = -1;
        t.topAsesores        = new List<ResumenAsesor>();

        Id rt = sucursalRecordTypeId();
        if (rt == null) { return t; }   // degrada todo a N/D

        String q        = null;
        Boolean filtrar = !String.isBlank(searchTerm);
        if (filtrar) { q = likeEscape(searchTerm); }

        String filtroExtra = (filtrar ? ' AND ' + filtroTexto() : '');

        // ── Total ──
        try {
            t.totalCuentas = Database.countQuery(
                'SELECT COUNT() FROM Account ' +
                'WHERE RecordTypeId = :rt AND ParentId != null ' +
                'AND Id NOT IN (SELECT AccountId FROM Contact)' +
                filtroExtra,
                AccessLevel.USER_MODE);
        } catch (Exception e) { /* degrada a -1 */ }

        // ── Con respaldo: hijas cuyo padre tiene contactos ──
        // Semi-join Account→Contact sobre ParentId (objetos distintos,
        // condición única ANDed → permitido por SOQL).
        try {
            t.conRespaldoPadre = Database.countQuery(
                'SELECT COUNT() FROM Account ' +
                'WHERE RecordTypeId = :rt AND ParentId != null ' +
                'AND Id NOT IN (SELECT AccountId FROM Contact) ' +
                'AND ParentId IN (SELECT AccountId FROM Contact)' +
                filtroExtra,
                AccessLevel.USER_MODE);
            t.sinRespaldoPadre = (t.totalCuentas >= 0)
                                 ? Math.max(0, t.totalCuentas - t.conRespaldoPadre)
                                 : -1;
        } catch (Exception e) {
            t.conRespaldoPadre = -1;
            t.sinRespaldoPadre = -1;
        }

        // ── Cuentas principales distintas ──
        // COUNT(DISTINCT) no admite campos relación (ParentId), así que se
        // agrupa por ParentId y se cuentan grupos en memoria con techo duro
        // (System.LimitException no es capturable: mejor degradar a N/D que
        // reventar la transacción en orgs enormes).
        try {
            Integer contadas = 0;
            for (AggregateResult ar : Database.query(
                    'SELECT ParentId FROM Account ' +
                    'WHERE RecordTypeId = :rt AND ParentId != null ' +
                    'AND Id NOT IN (SELECT AccountId FROM Contact)' +
                    filtroExtra +
                    ' GROUP BY ParentId LIMIT ' + RESUMEN_MAX_PRINCIPALES_SCAN,
                    AccessLevel.USER_MODE)) {
                contadas++;
            }
            t.cuentasPrincipales = (contadas >= RESUMEN_MAX_PRINCIPALES_SCAN)
                                   ? -1 : contadas;
        } catch (Exception e) { /* degrada a -1 */ }

        // ── Top 5 asesores por sucursales sin contacto directo ──
        // GROUP BY relación + ORDER BY agregado: 5 filas como máximo.
        try {
            for (AggregateResult ar : Database.query(
                    'SELECT Parent.Owner.Name nombre, COUNT(Id) cantidad ' +
                    'FROM Account ' +
                    'WHERE RecordTypeId = :rt AND ParentId != null ' +
                    'AND Id NOT IN (SELECT AccountId FROM Contact)' +
                    filtroExtra +
                    ' GROUP BY Parent.Owner.Name ORDER BY COUNT(Id) DESC LIMIT 5',
                    AccessLevel.USER_MODE)) {
                ResumenAsesor ra  = new ResumenAsesor();
                Object nom        = ar.get('nombre');
                ra.nombre         = (nom == null) ? '(sin asesor asignado)'
                                                  : String.valueOf(nom);
                ra.cantidad       = ((Decimal) ar.get('cantidad')).intValue();
                t.topAsesores.add(ra);
            }
        } catch (Exception e) {
            t.topAsesores = new List<ResumenAsesor>();   // degrada a vacío
        }

        return t;
    }

    /**
     * Exporta TODO el universo filtrado (todas las páginas, keyset por lotes)
     * replicando el formato de la tabla del LWC, agrupado por asesor (Owner
     * de la cuenta principal): celda combinada por asesor, bloques combinados
     * por cuenta principal, columna Sucursal y columna Detalle con el mensaje
     * de contactos heredados.
     *
     * Genera un archivo .xls a partir de HTML (mismo mecanismo de
     * seidor_FileExportService) guardado como ContentVersion. El cliente
     * descarga vía URL de Salesforce porque Lightning Web Security bloquea
     * Blobs con MIME text/csv.
     */
    @AuraEnabled
    public static ExcelResult exportarExcel(String searchTerm, Integer maxFilas) {
        ExcelResult out = new ExcelResult();
        out.versionId = null;
        out.filas     = 0;
        out.truncado  = false;

        Id rt = sucursalRecordTypeId();
        if (rt == null) {
            throw new AuraHandledException(
                'No existe un tipo de registro de Cuenta con nombre de desarrollador "' +
                SUCURSAL_RT_DEVNAME + '". Verifique la configuración de la org.');
        }

        String q        = null;
        Boolean filtrar = !String.isBlank(searchTerm);
        if (filtrar) { q = likeEscape(searchTerm); }

        Integer techo = (maxFilas == null || maxFilas < 1)
                        ? 30000 : Math.min(maxFilas, EXPORT_MAX_FILAS);

        // Keyset por (ParentId, Id): los hijos de una misma principal quedan
        // CONTIGUOS entre lotes → se puede emitir grupo a grupo sin acumular
        // todo el universo en memoria (fix heap en PRD con ~90k cuentas).
        String soqlBase =
            'SELECT Id, Name, RecordType.Name, RUT__c, C_digo_de_cliente__c, ' +
            '       Nombre_de_Fantasia__c, ParentId, Parent.OwnerId, Parent.Owner.Name, ' +
            '       Parent.Owner.Email, ' +
            '       Parent.Name, Parent.RUT__c, ' +
            '       Parent.C_digo_de_cliente__c, Parent.Nombre_de_Fantasia__c ' +
            'FROM Account ' +
            'WHERE RecordTypeId = :rt AND ParentId != null ' +
            'AND Id NOT IN (SELECT AccountId FROM Contact)' +
            (filtrar ? ' AND ' + filtroTexto() : '');

        ExcelBuilder b          = new ExcelBuilder();
        Id oidActual            = null;
        List<CuentaRow> actual  = new List<CuentaRow>();
        Id anchorOid            = null;
        Id anchorPid            = null;
        Id anchorAid            = null;
        Boolean truncado        = false;
        Integer batchLim        = BATCH_SIZE;

        while (true) {
            String soql = soqlBase +
                (anchorOid == null ? '' :
                    ' AND (Parent.OwnerId > :anchorOid ' +
                    '   OR (Parent.OwnerId = :anchorOid AND (' +
                    '       ParentId > :anchorPid OR' +
                    '      (ParentId = :anchorPid AND Id > :anchorAid))))') +
                ' ORDER BY Parent.OwnerId ASC, ParentId ASC, Id ASC LIMIT :batchLim';
            List<Account> lote = Database.query(soql, AccessLevel.USER_MODE);
            if (lote.isEmpty()) break;

            for (CuentaRow r : construirFilas(lote)) {
                // Grupo = asesor (Owner de la principal). El buffer acumula
                // el grupo COMPLETO antes de emitirlo para conocer su rowspan.
                if (oidActual != null && r.parentOwnerId != oidActual) {
                    b.addGrupo(actual);
                    actual = new List<CuentaRow>();
                    oidActual = r.parentOwnerId;
                }
                if (oidActual == null) { oidActual = r.parentOwnerId; }
                actual.add(r);

                out.filas++;
                if (out.filas >= techo || b.lleno) { truncado = true; break; }
            }
            if (truncado) break;

            anchorOid = lote[lote.size() - 1].Parent?.OwnerId;
            anchorPid = lote[lote.size() - 1].ParentId;
            anchorAid = lote[lote.size() - 1].Id;
        }
        if (!actual.isEmpty()) { b.addGrupo(actual); }   // último grupo

        List<String> h = new List<String>{
            '<!DOCTYPE html><html><head><meta http-equiv="Content-Type" content="text/html; charset=UTF-8"><style>',
            'table{border-collapse:collapse;font-family:Arial,sans-serif;font-size:11pt;}',
            'th{background:#2b6cb0;color:#fff;padding:6px 10px;border:1px solid #1a4a7a;font-weight:bold;text-align:left;}',
            'td{padding:4px 8px;border:1px solid #ccc;vertical-align:top;}',
            '.meta{color:#5c5c5c;font-size:9pt;}',
            '.asesor{font-weight:bold;}',
            '.titulo-seccion{font-weight:bold;font-size:12pt;margin:12px 0 4px 0;}',
            '.resumen td{font-size:11pt;}',
            '.valor{text-align:right;font-weight:bold;white-space:nowrap;}',
            '.nota{color:#5c5c5c;font-size:9pt;font-style:italic;margin:6px 0 10px 0;}',
            '.msg{color:#ba0517;font-size:10pt;margin:0 0 2px 0;}',
            '.sub{color:#5c5c5c;font-size:9pt;margin:0 0 4px 0;}',
            '.sin{color:#ba0517;font-style:italic;}',
            '</style></head><body>'
        };

        // Tabla resumen (misma información que el panel Resumen del LWC),
        // calculada sobre TODO el universo filtrado con COUNT puros.
        ResultadoTotales resumen = calcularResumen(searchTerm);

        h.add('<p class="titulo-seccion">Resumen</p>');
        h.add('<table class="resumen"><tbody>'
              + filaResumen('Sucursales sin contacto directo',    num(resumen.totalCuentas))
              + filaResumen('Con contactos en cliente principal', num(resumen.conRespaldoPadre))
              + filaResumen('Sin ningún contacto disponible',     num(resumen.sinRespaldoPadre))
              + filaResumen('Cuentas principales distintas',      num(resumen.cuentasPrincipales))
              + '</tbody></table>');

        if (!resumen.topAsesores.isEmpty()) {
            h.add('<p class="titulo-seccion">Top 5 asesores con sucursales sin contacto directo</p>');
            h.add('<table class="resumen"><thead><tr>'
                  + '<th>Asesor</th><th>Sucursales sin contacto directo</th>'
                  + '</tr></thead><tbody>');
            for (ResumenAsesor ta : resumen.topAsesores) {
                h.add('<tr><td>' + esc(ta.nombre) + '</td>'
                      + '<td class="valor">' + ta.cantidad + '</td></tr>');
            }
            h.add('</tbody></table>');
        }

        if (truncado) {
            h.add('<p class="nota">El detalle exportado se truncó en '
                  + out.filas + ' filas por límites de tamaño.</p>');
        }

        h.add('<table><thead><tr>'
              + '<th>Asesor</th><th>Cuenta Principal</th><th>Sucursal</th><th>Detalle</th>'
              + '</tr></thead><tbody>');
        h.addAll(b.partes);
        h.add('</tbody></table></body></html>');

        String html = String.join(h, '');

        ContentVersion cv = new ContentVersion(
            Title          = 'sucursales_sin_contacto_directo',
            PathOnClient   = 'sucursales_sin_contacto_directo.xls',
            VersionData    = Blob.valueOf(html),
            IsMajorVersion = false
        );
        insert cv;

        out.versionId = cv.Id;
        out.truncado  = truncado;
        return out;
    }

    // ── Correo al asesor ─────────────────────────────────────────────────────

    /** Contexto del modal: remitente visible para el usuario conectado. */
    public class CorreoPreview {
        @AuraEnabled public String de;
        @AuraEnabled public String nombreUsuario;
    }

    /**
     * Contexto para abrir el modal de correo. Valida que haya sucursales
     * visibles y expone el correo del usuario conectado (campo "De").
     * El cliente envía SOLO los Ids de las filas visibles: los datos completos
     * se re-consultan en el servidor al enviar (evita roundtrip de DTOs).
     */
    @AuraEnabled
    public static CorreoPreview prepararCorreoAsesor(List<String> sucursalIds) {
        validarIdsCorreo(sucursalIds);

        CorreoPreview p = new CorreoPreview();
        p.de            = UserInfo.getUserEmail();
        p.nombreUsuario = UserInfo.getName();
        return p;
    }

    /**
     * Envía el correo al asesor vía Messaging.SingleEmailMessage usando la
     * Org-Wide Address verificada CORREO_REMITENTE como remitente y el correo
     * del usuario conectado como Reply-To. Las sucursales (filas visibles)
     * se RE-CONSULTAN por Id en el servidor y el cuerpo HTML se construye
     * siempre aquí, nunca desde objetos serializados por el cliente.
     * En tests NO se envía nada: el mensaje queda capturado en
     * correosCapturados para sus asserts.
     */
    @AuraEnabled
    public static String enviarCorreoAsesor(List<String> sucursalIds,
                                            String para,
                                            List<String> cc,
                                            String asunto) {
        validarIdsCorreo(sucursalIds);
        if (!esEmailValido(para)) {
            throw err('El destinatario "' + (para == null ? '' : para) + '" no es un correo válido.');
        }
        List<String> ccLimpios = new List<String>();
        if (cc != null) {
            for (String c : cc) {
                if (String.isBlank(c)) { continue; }
                if (!esEmailValido(c.trim())) {
                    throw err('El correo en copia "' + c.trim() + '" no es válido.');
                }
                ccLimpios.add(c.trim());
            }
        }
        if (ccLimpios.size() > MAX_CORREOS_CC) {
            throw err('Máximo ' + MAX_CORREOS_CC + ' correos en copia.');
        }

        // Re-consulta de las filas visibles (mismo universo que la pantalla:
        // RT Sucursal, con principal y sin contacto directo). El orden replica
        // la paginación para que los bloques por principal queden contiguos.
        List<Id> ids = new List<Id>();
        for (String sid : sucursalIds) { ids.add(Id.valueOf(sid)); }

        Id rt = sucursalRecordTypeId();
        if (rt == null) {
            throw err('No existe un tipo de registro de Cuenta "' +
                      SUCURSAL_RT_DEVNAME + '". Verifique la configuración de la org.');
        }

        List<Account> cuentas = [
            SELECT Id, Name, RecordType.Name, RUT__c, C_digo_de_cliente__c,
                   Nombre_de_Fantasia__c, ParentId, Parent.OwnerId, Parent.Owner.Name,
                   Parent.Owner.Email, Parent.Name, Parent.RUT__c,
                   Parent.C_digo_de_cliente__c, Parent.Nombre_de_Fantasia__c
            FROM Account
            WHERE Id IN :ids
              AND RecordTypeId = :rt AND ParentId != null
              AND Id NOT IN (SELECT AccountId FROM Contact)
            WITH USER_MODE
            ORDER BY Parent.OwnerId ASC, ParentId ASC, Id ASC
        ];
        if (cuentas.isEmpty()) {
            throw err('Las sucursales ya no son visibles. Recargue los datos e intente nuevamente.');
        }

        String htmlBody = construirTablaCorreo(construirFilas(cuentas));

        // Dirección organizacional resuelta por Address (portable entre orgs).
        // El Id puede inyectarse en tests para no depender de datos de la org.
        String remitente = (direccionRemitenteOverride != null)
                           ? direccionRemitenteOverride : CORREO_REMITENTE;
        Id owaId;
        if (orgWideAddressIdTest != null) {
            owaId = orgWideAddressIdTest;
        } else {
            List<OrgWideEmailAddress> owas = [
                SELECT Id FROM OrgWideEmailAddress
                WHERE Address = :remitente
                LIMIT 1
            ];
            if (owas.isEmpty()) {
                throw err(
                    'No existe una dirección organizacional verificada "' + remitente +
                    '". Configúrela en Setup → Organization-Wide Addresses.');
            }
            owaId = owas[0].Id;
        }

        // reserveSingleEmailCapacity es void y lanza excepción sin cupo
        try {
            Messaging.reserveSingleEmailCapacity(1);
        } catch (Exception e) {
            throw err('Se alcanzó el límite diario de correos de la org. Intente más tarde.');
        }

        Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
        mail.setToAddresses(new List<String>{ para.trim() });
        if (!ccLimpios.isEmpty()) { mail.setCcAddresses(ccLimpios); }
        mail.setSubject(String.isBlank(asunto)
                        ? 'Sucursales sin contacto directo'
                        : asunto);
        mail.setHtmlBody(htmlBody);
        mail.setOrgWideEmailAddressId(owaId);
        mail.setReplyTo(UserInfo.getUserEmail());

        if (Test.isRunningTest()) {
            if (correosCapturados == null) { correosCapturados = new List<Messaging.SingleEmailMessage>(); }
            correosCapturados.add(mail);
            return 'Correo registrado (test).';
        }

        try {
            Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ mail });
        } catch (Exception e) {
            throw err('No se pudo enviar el correo: ' + e.getMessage());
        }
        return 'Correo enviado a ' + para.trim() + '.';
    }

    /**
     * Cuerpo HTML del correo con formato corporativo. Los estilos van INLINE
     * en cada elemento porque los clientes de correo (Gmail, Outlook)
     * descartan los bloques <style>. Incluye encabezado institucional, texto
     * introductorio genérico y tabla con filas alternadas; bloques combinados
     * por cuenta principal contigua (misma lógica de spans que el Excel) y
     * sin columna Asesor — el destinatario ES el asesor. Todo pasa por esc().
     */
    private static String construirTablaCorreo(List<CuentaRow> filas) {
        String azul      = '#1f4e79';
        String bordeTd   = 'border:1px solid #d9d9d9;padding:8px 10px;vertical-align:top;';
        String metaStyle = 'color:#666666;font-size:8.5pt;margin-top:2px;';
        String thStyle   = 'background:' + azul + ';color:#ffffff;padding:8px 10px;'
                           + 'border:1px solid #17395a;text-align:left;font-size:10pt;';

        String asesorNombre = (filas[0].parentOwnerName == null)
                              ? '' : filas[0].parentOwnerName;

        List<String> h = new List<String>{
            '<div style="font-family:Arial,Helvetica,sans-serif;color:#333333;font-size:11pt;max-width:720px;">',

            // Encabezado institucional
            '<div style="background:' + azul + ';padding:14px 18px;border-radius:6px 6px 0 0;">'
                + '<span style="color:#ffffff;font-size:14pt;font-weight:bold;">ICB Food Service</span><br>'
                + '<span style="color:#cfe2f3;font-size:10pt;">Notificación de cuentas con contactos faltantes</span>'
            + '</div>',

            // Contenedor del cuerpo
            '<div style="border:1px solid #d9d9d9;border-top:none;padding:18px;background:#ffffff;">',
            '<p style="margin:0 0 10px 0;">Estimado(a) <b>' + esc(asesorNombre) + '</b>:</p>',
            '<p style="margin:0 0 14px 0;line-height:1.45;">'
                + 'Junto con saludar, informamos a usted que las siguientes sucursales asociadas '
                + 'a sus cuentas principales <b>no poseen contactos asignados directamente</b>. '
                + 'Agradeceremos gestionar el registro o actualización de los contactos correspondientes, '
                + 'con el fin de asegurar una comunicación oportuna con nuestros clientes.'
            + '</p>',
            '<p style="margin:0 0 8px 0;font-weight:bold;color:' + azul + ';font-size:10.5pt;">'
                + 'Sucursales sin contacto directo</p>',
            '<table style="border-collapse:collapse;width:100%;font-size:10pt;">',
            '<thead><tr>'
                + '<th style="' + thStyle + '">Cuenta Principal</th>'
                + '<th style="' + thStyle + '">Sucursal</th>'
                + '<th style="' + thStyle + '">Detalle</th>'
            + '</tr></thead>',
            '<tbody>'
        };

        Integer filaNum = 0;
        Integer i = 0;
        while (i < filas.size()) {
            Integer j = i;
            while (j < filas.size()
                   && filas[j].parentAccountId == filas[i].parentAccountId) {
                j++;
            }
            Integer spanPrincipal = j - i;

            // Zebra por fila visible; las celdas combinadas usan el fondo de
            // la primera fila del bloque.
            String bg = (Math.mod(filaNum, 2) == 0) ? '#ffffff' : '#f2f7fc';

            String padreCell =
                '<td rowspan="' + spanPrincipal + '" style="' + bordeTd + 'background:' + bg + ';">'
                + '<b>' + esc(filas[i].parentAccountName) + '</b>';
            if (String.isNotBlank(filas[i].parentRut)) {
                padreCell += '<div style="' + metaStyle + '">RUT: ' + esc(filas[i].parentRut) + '</div>';
            }
            if (String.isNotBlank(filas[i].parentCodigoCliente)) {
                padreCell += '<div style="' + metaStyle + '">Cód. cliente: ' + esc(filas[i].parentCodigoCliente) + '</div>';
            }
            if (String.isNotBlank(filas[i].parentNombreFantasia)) {
                padreCell += '<div style="' + metaStyle + '">Fantasía: ' + esc(filas[i].parentNombreFantasia) + '</div>';
            }
            padreCell += '</td>';

            for (Integer k = i; k < j; k++) {
                CuentaRow r = filas[k];
                if (r == null) { continue; }

                String hijaCell =
                    '<td style="' + bordeTd + 'background:' + bg + ';">' + esc(r.accountName);
                if (String.isNotBlank(r.nombreFantasia)) {
                    hijaCell += '<div style="' + metaStyle + '">' + esc(r.nombreFantasia) + '</div>';
                }
                if (String.isNotBlank(r.codigoCliente)) {
                    hijaCell += '<div style="' + metaStyle + '">' + esc(r.codigoCliente) + '</div>';
                }
                hijaCell += '</td>';

                String detalleCell;
                if (r.padreConContactos == true) {
                    detalleCell =
                        '<td style="' + bordeTd + 'background:' + bg + ';">'
                        + '<p style="margin:0 0 4px 0;color:#ba0517;font-size:9.5pt;">Esta cuenta de tipo de registro '
                            + esc(r.recordTypeName) + ' no posee contactos directos</p>'
                        + '<p style="margin:0 0 4px 0;color:#666666;font-size:9pt;">Contactos asociados a la cuenta principal «'
                            + esc(r.parentAccountName) + '»: ' + r.contactoCountPadre + '</p>';
                    if (r.contactosPadre != null) {
                        for (ContactoDTO c : r.contactosPadre) {
                            detalleCell += '<div style="font-size:9.5pt;">• ' + esc(c.name)
                                + (String.isBlank(c.email) ? '' : ' (' + esc(c.email) + ')')
                                + '</div>';
                        }
                    }
                    detalleCell += '</td>';
                } else {
                    detalleCell =
                        '<td style="' + bordeTd + 'background:' + bg + ';">'
                        + '<span style="color:#ba0517;font-style:italic;">Sin contactos asociados</span></td>';
                }

                h.add('<tr>' + padreCell + hijaCell + detalleCell + '</tr>');
                filaNum++;
            }
            i = j;
        }

        h.add('</tbody></table>');

        // Pie corporativo
        h.add('<p style="margin:16px 0 0 0;color:#888888;font-size:9pt;font-style:italic;">'
              + 'Este mensaje fue generado automáticamente desde el panel «Sucursales sin contacto directo» '
              + 'de Salesforce. Si requiere antecedentes adicionales, responda directamente a este correo.</p>');
        h.add('</div></div>');

        return String.join(h, '');
    }

    /** Validación común de los Ids de sucursales visibles que alimentan el correo. */
    private static void validarIdsCorreo(List<String> sucursalIds) {
        if (sucursalIds == null || sucursalIds.isEmpty()) {
            throw err('No hay sucursales visibles para incluir en el correo.');
        }
    }

    /** Validación simple de formato RFC-ligero para Para/CC. */
    private static Boolean esEmailValido(String email) {
        if (String.isBlank(email)) { return false; }
        return Pattern.compile('[a-zA-Z0-9._%+\\-]+@[a-zA-Z0-9.\\-]+\\.[a-zA-Z]{2,}')
                      .matcher(email.trim())
                      .matches();
    }

    // ── Helpers privados ──────────────────────────────────────────────────────

    /**
     * AuraHandledException con mensaje legible: el constructor NO fija el
     * mensaje consultable vía getMessage() (retorna "Script-thrown
     * exception"), por eso se aplica setMessage() explícito.
     */
    private static AuraHandledException err(String msg) {
        AuraHandledException e = new AuraHandledException(msg);
        e.setMessage(msg);
        return e;
    }

    /** Id del RecordType Sucursal (cacheado por transacción). */
    private static String sucursalRecordTypeId() {
        if (sucursalRtIdCache == null) {
            String devName = SUCURSAL_RT_DEVNAME;
            List<RecordType> rts = [
                SELECT Id FROM RecordType
                WHERE SobjectType = 'Account' AND DeveloperName = :devName
                LIMIT 1
            ];
            sucursalRtIdCache = rts.isEmpty() ? null : rts[0].Id;
        }
        return sucursalRtIdCache;
    }

    /**
     * Mapea sucursales a filas planas y adjunta los contactos de su cuenta
     * principal (en este universo las filas NO tienen contactos propios).
     */
    private static List<CuentaRow> construirFilas(List<Account> cuentas) {

        Map<Id, CuentaRow> rowsByAccountId = new Map<Id, CuentaRow>();
        List<CuentaRow> ordenadas = new List<CuentaRow>();

        for (Account acc : cuentas) {
            CuentaRow row                  = new CuentaRow();
            row.accountId                  = acc.Id;
            row.accountName                = acc.Name;
            row.recordTypeName             = acc.RecordType?.Name;
            row.rut                        = acc.RUT__c;
            row.codigoCliente              = acc.C_digo_de_cliente__c;
            row.nombreFantasia             = acc.Nombre_de_Fantasia__c;
            row.parentAccountId            = acc.ParentId;
            row.parentAccountName          = acc.Parent?.Name;
            row.parentRut                  = acc.Parent?.RUT__c;
            row.parentCodigoCliente        = acc.Parent?.C_digo_de_cliente__c;
            row.parentNombreFantasia       = acc.Parent?.Nombre_de_Fantasia__c;
            row.parentOwnerId              = acc.Parent?.OwnerId;
            row.parentOwnerName            = acc.Parent?.Owner?.Name;
            row.parentOwnerEmail           = acc.Parent?.Owner?.Email;
            row.padreConContactos          = false;
            row.contactoCountPadre         = 0;
            row.contactosPadre             = new List<ContactoDTO>();
            rowsByAccountId.put(acc.Id, row);
            ordenadas.add(row);
        }

        Set<Id> parentIds = new Set<Id>();
        for (CuentaRow r : ordenadas) {
            if (r.parentAccountId != null) parentIds.add(r.parentAccountId);
        }

        Map<Id, List<ContactoDTO>> contactsByParentId = new Map<Id, List<ContactoDTO>>();
        if (!parentIds.isEmpty()) {
            for (Contact con : [
                SELECT Id, Name, Email, AccountId
                FROM Contact
                WHERE AccountId IN :parentIds
                WITH USER_MODE
                ORDER BY Name ASC
            ]) {
                ContactoDTO dto = new ContactoDTO();
                dto.id    = con.Id;
                dto.name  = con.Name;
                dto.email = con.Email;
                if (!contactsByParentId.containsKey(con.AccountId)) {
                    contactsByParentId.put(con.AccountId, new List<ContactoDTO>());
                }
                contactsByParentId.get(con.AccountId).add(dto);
            }
        }

        // Recorre en el mismo orden del SOQL para salida determinista.
        for (CuentaRow r : ordenadas) {
            List<ContactoDTO> delPadre =
                (r.parentAccountId != null) ? contactsByParentId.get(r.parentAccountId) : null;
            if (delPadre == null) delPadre = new List<ContactoDTO>();
            r.contactosPadre     = delPadre;
            r.contactoCountPadre = delPadre.size();
            r.padreConContactos  = !delPadre.isEmpty();
        }

        return ordenadas;
    }

    /** Formatea una métrica del resumen (-1/null = N/D). */
    private static String num(Integer v) {
        return (v == null || v < 0) ? 'N/D' : String.valueOf(v);
    }

    /** Fila métrica|valor de la tabla resumen exportada. */
    private static String filaResumen(String etiqueta, String valor) {
        return '<tr><td>' + esc(etiqueta) + '</td>'
               + '<td class="valor">' + valor + '</td></tr>';
    }

    /** Escape mínimo de HTML para celdas del archivo exportado. */
    private static String esc(Object valor) {
        String s = valor == null ? '' : String.valueOf(valor);
        s = s.replace('&', '&amp;');
        s = s.replace('<', '&lt;');
        s = s.replace('>', '&gt;');
        return s;
    }

    /** Búsqueda opcional: datos propios o de la cuenta principal. Bind :q */
    private static String filtroTexto() {
        return '((Name LIKE :q OR Nombre_de_Fantasia__c LIKE :q OR RUT__c LIKE :q ' +
               'OR C_digo_de_cliente__c LIKE :q OR Parent.Name LIKE :q ' +
               'OR Parent.RUT__c LIKE :q OR Parent.C_digo_de_cliente__c LIKE :q))';
    }

    /** Sanitiza el término de búsqueda para LIKE y envuelve con %..%. */
    private static String likeEscape(String raw) {
        String s = String.isBlank(raw) ? '' : raw.trim();
        s = s.replace('\\', '\\\\');
        s = s.replace('%', '\\%');
        s = s.replace('_', '\\_');
        return '%' + s + '%';
    }
}