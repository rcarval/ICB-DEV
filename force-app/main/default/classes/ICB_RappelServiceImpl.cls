/**********************************************************************************
Desarrollado por: SEIDOR
Autor: Rodrigo Carvallo (RCG)
Proyecto: Maestra de Precios - Perfomance
Descripción: Clase de servicio para gestión de rappels en Maestra de Precios
Test: ICB_RappelService_Test

---------------------------------------------------------------------------------
No. Fecha                Autor                     Descripción
------ ---------- ---------------------------------------------------------------
1.0 08-10-2025            RCG                Creación de la clase.
**********************************************************************************/
public class ICB_RappelServiceImpl{

    /**
    * Método para calcular precio cliente neto con aplicación de rappels en compras
    * @author Rodrigo Carvallo
    * @param Id accountId - ID del cliente para buscar rappels
    * @param List<Detalle__c> comprasMaestradePrecios - Lista de compras a procesar
    * @param Map<Id, Decimal> preciosClienteNeto - Mapa para almacenar precios netos calculados
    **/
    public static void calcularPrecioClienteNetoConRappelCompras(Id accountId, List<Detalle__c> comprasMaestradePrecios, Map<Id, Decimal> preciosClienteNeto) {
        Date today = Date.today(); // Obtener la fecha actual
        
        // Crear un mapa de rappels por cliente y producto
        Map<Id, Map<Id, Rappel__c>> rappelsPorClienteYProducto = new Map<Id, Map<Id, Rappel__c>>();
        
        // Consulta de rappels
        List<Rappel__c> rappelList = ICB_MaestraPreciosRepository.getRappelsVigentesByCliente(accountId, today);
        
        // Organizar los rappels en un mapa por cliente y producto
        for (Rappel__c rappel : rappelList) {
            if (!rappelsPorClienteYProducto.containsKey(rappel.Cliente__c)) {
                rappelsPorClienteYProducto.put(rappel.Cliente__c, new Map<Id, Rappel__c>());
            }
            rappelsPorClienteYProducto.get(rappel.Cliente__c).put(rappel.Product__c, rappel);
        }
        
        // Procesar cada detalle de comprasMaestradePrecios
        for (Detalle__c detalle : comprasMaestradePrecios) {
            Decimal precioFinal = Integer.valueOf(detalle.Precio_Final__c);
            Decimal descuento = detalle.Descuento_Cliente__r.Descuento_gestionado__c;
            
            // Calcular el precio después del descuento
            Decimal precioDespuesDescuento = (descuento != null)
                ? Integer.valueOf(precioFinal - (precioFinal * descuento / 100))
                : precioFinal;
            
            // Inicializa el porcentaje de rappel
            Decimal porcentajeRappel = 0;
            Boolean rappelVigenteEncontrado = false;
            
            // Verificar si hay un rappel para el cliente y producto en el mapa
            if (rappelsPorClienteYProducto.containsKey(accountId) &&
                rappelsPorClienteYProducto.get(accountId).containsKey(detalle.Producto__c)) {
                    Rappel__c rappel = rappelsPorClienteYProducto.get(accountId).get(detalle.Producto__c);
                    porcentajeRappel = rappel.Rappel__c;
                    rappelVigenteEncontrado = true;
                }
            
            // Si se encontró un rappel vigente, se aplica al precio después del descuento
            if (rappelVigenteEncontrado) {
                System.debug('Rappel vigente encontrado: ' + porcentajeRappel + '% para el producto: ' + detalle.Producto__c);
                precioDespuesDescuento += Integer.valueOf(precioDespuesDescuento * (porcentajeRappel / 100));
                detalle.Porcentaje_de_Rappel__c = porcentajeRappel; // Guardar el porcentaje en el detalle
            } else {
                System.debug('No se encontró rappel vigente para el producto: ' + detalle.Producto__c);
            }
            
            // Asignar el precio cliente neto final
            detalle.Precio_Cliente_Neto__c = precioDespuesDescuento;
            preciosClienteNeto.put(detalle.Id, detalle.Precio_Cliente_Neto__c); // Guardar el valor en el mapa
        }
    }


}