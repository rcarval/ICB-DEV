/**
 * ICB Food Service
 * Desarrollado por: José Illanes
 * Fecha: 2026-02-04
 * Descripción: Asigna automáticamente Domicilio_Cliente__c en Facturas__c según Cliente__c + key de despacho
 */
trigger ICBFD_FacturasDomicilioCliente_TGR on Facturas__c (before insert, before update) {
    ICBFD_FacturasDomicilioClienteService.asignarDomicilio(Trigger.new, Trigger.oldMap);
}