/**********************************************************************************
Desarrollado por: SEIDOR
Autor: Rodrigo Carvallo (RCG)
Proyecto: Maestra de Precios - Perfomance
Descripción: Clase de utilitarios para Maestra de Precios
Test: ICB_UtilsService_Test

---------------------------------------------------------------------------------
No. Fecha                Autor                     Descripción
------ ---------- ---------------------------------------------------------------
1.0 11-09-2025            RCG                Creación de la clase.
**********************************************************************************/
public class ICB_UtilsServiceImpl{

    /**
    * Método que retorna el nombre en formato texto del mes en curso
    * @author Rodrigo Carvallo
    * @return String
    **/
    public static String generarEncabezado(){
        Date today = System.today();
        List<String> meses = new List<String>{
            'Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio',
                'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre'
                };
        String mesTexto = meses[today.month() - 1];
        String anio = String.valueOf(today.year());
        return mesTexto.toUpperCase() + ' ' + anio;
    }

    /**
    * Método para formatear fechas de componente
    * @author Rodrigo Carvallo
    * @param List<Detalle__c> comprasMaestradePrecios
    **/
    public static void formatearFechas(List<Detalle__c> comprasMaestradePrecios){
        system.debug('formatear fecha ');
        for (Detalle__c detalle : comprasMaestradePrecios) {
            Date fecha = detalle.Descuento_Cliente__r.Fecha_hasta__c;
            system.debug('fecha ' + detalle.Descuento_Cliente__r.Fecha_hasta__c);
            if (fecha != null) {
                detalle.Fecha_Vencimiento_Formateada__c = fecha.day() + '/' + fecha.month() + '/' + fecha.year();
            } else {
                detalle.Fecha_Vencimiento_Formateada__c = '';
                system.debug('fecha else ' + detalle.Descuento_Cliente__r.Fecha_hasta__c);
            }
        }
    }

}