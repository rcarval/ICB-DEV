/**
 * Cabecera de la propuesta de comodato para las vistas previas en pantalla.
 *
 * Existe porque el mismo bloque estaba copiado en ComodatoPropuestaController y en
 * ComodatoPropuestaMultiController: al agregar las marcas representadas se actualizo el PDF
 * y las vistas previas quedaron atras, mostrando una cabecera distinta a la del documento.
 * Con un solo punto de armado eso no se puede volver a desalinear.
 *
 * Las paginas Visualforce mantienen su propio markup porque renderizan a PDF, donde las
 * imagenes se referencian con $Resource y no por URL.
 */
public with sharing class ComodatoCabecera {

    /**
     * Marcas que representa ICB Food Service, en el orden en que van junto a Lavazza, con la
     * altura en px de cada una.
     *
     * No van todas a la misma altura a proposito. Los archivos ya vienen recortados a su
     * contenido, asi que la altura es la del logo real; pero un emblema macizo --el ovalo de
     * Kraft, el escudo de Don Juan-- pesa mas que una palabra a igual altura, asi que se les
     * da menos. El wordmark de Kraft Heinz es el mas horizontal y necesita algo menos de alto
     * para no comerse la linea.
     */
    private static final List<String> MARCAS = new List<String>{
        'LogoKraft', 'LogoKraftHeinz', 'LogoNutella', 'LogoDonJuan'
    };
    private static final Map<String, Integer> ALTO = new Map<String, Integer>{
        'LogoKraft' => 20, 'LogoKraftHeinz' => 18, 'LogoNutella' => 20, 'LogoDonJuan' => 31
    };

    /**
     * Bloque de cabecera: ICB a la izquierda y, a la derecha, Lavazza seguido de las marcas
     * representadas en la misma linea.
     *
     * Lavazza va a 70px y manda; las marcas quedan entre 18 y 26px para leerse como marcas
     * representadas sin competir con ella ni desbordar el ancho de la hoja.
     */
    public static String html() {
        String derecha = '<img src="/resource/LavazzaLogo" style="height:70px;vertical-align:middle;" alt="Lavazza"/>';
        for (String marca : MARCAS) {
            derecha += '<img src="/resource/' + marca
                + '" style="height:' + ALTO.get(marca) + 'px;margin-left:16px;vertical-align:middle;" alt="'
                + marca.removeStart('Logo') + '"/>';
        }
        return '<table style="width:100%;border-collapse:collapse;margin-bottom:20px;"><tr>'
            + '<td style="text-align:left;vertical-align:middle;">'
            + '<img src="/resource/ICBLogo" style="height:70px;" alt="ICB Food Service"/></td>'
            + '<td style="text-align:right;vertical-align:middle;">' + derecha + '</td>'
            + '</tr></table>';
    }

    /** Banda azul con el titulo del documento. */
    public static String banner() {
        return '<div style="background-color:#0000A0;color:white;text-align:center;padding:8px 0;'
            + 'font-size:14pt;font-weight:bold;letter-spacing:3px;margin-bottom:20px;">PROPUESTA</div>';
    }
}