# Estrategia de corte - LEAD_TRG_AfterUpdate a Apex

## Objetivo

Evitar duplicidad de lógica de mapeo post-conversión al moverla desde Flow hacia Apex.

## Implementado

- El Flow `LEAD_TRG_AfterUpdate` ahora invoca `ICB_LeadConversionFlowAction`.
- El mapeo de `Lead -> Account/Contact/Lead` quedó centralizado en `ICB_LeadConversionService`.
- El email a Finanzas se mantiene en el mismo Flow mediante `Account.Alerta_finanzas`.

## Secuencia operativa

1. `Lead` cumple criterio en `LEAD_TRG_AfterUpdate`.
2. Flow ejecuta `ICB_LeadConversionFlowAction` (convierte si corresponde y aplica mapeo).
3. Flow evalúa `RecordType.Name == 'Empresa'`.
4. Si cumple, ejecuta `Account.Alerta_finanzas`.

## Validación funcional sugerida

- Caso 1: Lead de tipo Empresa.
  - Verificar mapeo en `Account`, `Contact` y `Lead.Account__c`.
  - Verificar envío de alerta a Finanzas.
- Caso 2: Lead no Empresa.
  - Verificar mapeo correcto.
  - Verificar que no se envía alerta.

## Riesgo de duplicidad y mitigación

- Riesgo: mantener lógica declarativa de updates en Flow y en Apex al mismo tiempo.
- Mitigación aplicada: se removió la ruta declarativa de updates y quedó una única fuente de verdad en Apex.
