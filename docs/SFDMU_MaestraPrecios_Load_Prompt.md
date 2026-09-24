# Prompt para carga SFDMU – Maestra de Precios (MaestraPreciosController)

Usa este texto en el otro sistema para que genere y ejecute la carga de datos con el plugin SFDMU. Las conexiones de origen y destino ya están configuradas.

---

## Objetivo
Cargar en el org de destino todos los objetos necesarios para que la funcionalidad **Maestra de Precios** (`MaestraPreciosController`) funcione correctamente: la página/flow que usa un Account (cliente), sus facturas, detalles de factura, descuentos, costos, rappels, listas de precios y productos.

---

## Orden de carga (respetar dependencias)

Importar en este orden para no violar relaciones (lookup/master-detail) ni validaciones:

1. **Comuna__c**  
   - Objeto custom. Sin dependencias de otros objetos del set.

2. **Account**  
   - Campos relevantes: `Name`, `Sucursal__c`, `Centro_de_Abastecimiento__c`, `RUT__c` (único), `RecordTypeId` (Negocio), `Comuna_Facturaci_n__c`, `Comuna_Despacho__c`, `Region__c`, `Region_Despacho__c`, `Nombre_de_contacto__c`, `Email__c`, direcciones.  
   - La cuenta debe tener **Sucursal__c** poblada (ej: `S001 - Suc Santiago`). El controlador busca un Pricebook2 cuyo **Name** coincida con el prefijo de sucursal (ej: Pricebook “Precios S001” para Sucursal “S001 - Suc Santiago”).

3. **Categoria__c**, **Familia__c**, **Unidad_de_Medida__c**  
   - Objetos custom requeridos por Product2 (lookups).

4. **Product2**  
   - Incluir campos usados por el repositorio: `Name`, `Codigo__c`, `TextoUMV__c`, `Peso__c`, `Descuento_Autonomo_de_Asesor__c`, `Fecha_maxima_de_descuento__c`, `Categoria__c`, `Familia__c`, `UMV__c`, `IsActive`, y los demás necesarios para tus reglas/ layouts.

5. **Pricebook2**  
   - Custom pricebook. El **Name** debe ser consistente con `Account.Sucursal__c` (ej: si Sucursal = “S001 - Suc Santiago”, debe existir un Pricebook con Name = “Precios S001”).

6. **PricebookEntry**  
   - Relacionar `Pricebook2Id` (standard y/o custom) y `Product2Id`. Incluir `UnitPrice`, `IsActive`. Para la maestra se usan entries del pricebook cuyo nombre coincide con la sucursal del cliente.

7. **Domicilio_de_Cliente__c**  
   - Lookup a **Account** (`Cliente__c`). Requerido por validaciones de **Facturas__c**. Incluir campos obligatorios según tu org (ej. dirección, región, comuna).

8. **Facturas__c**  
   - Lookup a **Account** (`Cliente__c`), lookup a **Domicilio_de_Cliente__c** (`Domicilio_Cliente__c`). Incluir `Fecha_de_Documento__c` y demás campos obligatorios.  
   - Sin domicilio y cuenta correctos, la validación de dirección puede fallar.

9. **Detalle_Factura__c**  
   - Master-Detail a **Facturas__c** (`Factura__c`), lookup a **Product2** (`Product__c`). Incluir: `SKU__c`, `Unidad_de_Medida__c`, `Descripcion__c`, `Valor_Neto__c`, `Product__c`, `Factura__c`.  
   - Este objeto es la base de “compras” que usa la Maestra de Precios (en reemplazo de Detalle__c).

10. **Costo__c**  
    - Lookup a **Product2** (`Codigo_del_Producto__c`). Incluir `Centro_de_Abastecimiento__c` (debe coincidir con valores de Account, ej: “FS00 - Santiago Maulén” o el valor que usen), `CostoProducto__c`, y campos de texto/código si los usan.

11. **Rappel__c**  
    - Lookup a **Account** (`Cliente__c`) y a **Product2** (`Product__c`). Incluir `Rappel__c`, `Fecha_Vigencia_Desde__c`, `Fecha_Vigencia_Hasta__c`.

12. **Precios__c**  
    - Lookup a **Account** (`Cliente__c`) y a **Product2** (`Detalle_de_producto__c`). Incluir `Precio_de_lista__c`, `Fecha_Vigencia_Desde__c`, `Fecha_Vigencia_Hasta__c`.

13. **Descuento_Cliente__c**  
    - Lookup a **Account** (`Cliente__c`) y a **Product2** (`Producto__c`). Incluir `Fecha_desde__c`, `Fecha_hasta__c`, `Descuento_gestionado__c`, `Es_recargo__c` y demás campos usados en tus vistas.

---

## Lista de objetos para SFDMU (en orden sugerido)

| Orden | Objeto (API Name)     | Tipo   | Nota breve |
|------|------------------------|--------|------------|
| 1    | Comuna__c              | Custom | Sin deps   |
| 2    | Account                | Standard | Sucursal__c y Centro_de_Abastecimiento__c obligatorios |
| 3    | Categoria__c           | Custom | Para Product2 |
| 4    | Familia__c             | Custom | Para Product2 |
| 5    | Unidad_de_Medida__c    | Custom | Para Product2 |
| 6    | Product2               | Standard | Codigo__c, Peso__c, etc. |
| 7    | Pricebook2             | Standard | Name = “Precios S001” (o según Sucursal) |
| 8    | PricebookEntry         | Standard | Pricebook2Id + Product2Id |
| 9    | Domicilio_de_Cliente__c| Custom | Cliente__c → Account; requerido para Facturas__c |
| 10   | Facturas__c            | Custom | Cliente__c, Domicilio_Cliente__c, Fecha_de_Documento__c |
| 11   | Detalle_Factura__c     | Custom | Factura__c → Facturas__c, Product__c → Product2 |
| 12   | Costo__c               | Custom | Codigo_del_Producto__c → Product2, Centro_de_Abastecimiento__c |
| 13   | Rappel__c              | Custom | Cliente__c, Product__c, fechas vigencia |
| 14   | Precios__c             | Custom | Cliente__c, Detalle_de_producto__c, fechas vigencia |
| 15   | Descuento_Cliente__c   | Custom | Cliente__c, Producto__c, fechas |

---

## Reglas importantes para el script SFDMU

- **Account**: Mantener coherencia entre `Sucursal__c` y el **Name** del **Pricebook2** (ej: Sucursal “S001 - Suc Santiago” → Pricebook “Precios S001”).  
- **Facturas__c**: Siempre asociar una **Domicilio_de_Cliente__c** válida para la misma cuenta para no fallar validaciones.  
- **Detalle_Factura__c**: Solo después de tener **Facturas__c** y **Product2**; el campo Master-Detail es **Factura__c** (apunta a Facturas__c).  
- **RUT__c** en Account: debe ser único en el org; si el script genera RUTs o usa mapeo de IDs, evitar duplicados.  
- Si hay **RecordType** en Account (“Negocio”), incluirlo en el export/import o asegurar que exista en destino con el mismo DeveloperName.

---

## Resumen para pegar en el otro sistema (prompt corto)

```
Necesito una configuración SFDMU para cargar datos que permitan usar la Maestra de Precios en Salesforce (MaestraPreciosController). Ya tengo las conexiones de org origen y destino.

Objetos a migrar, en este orden estricto:
1. Comuna__c
2. Account (con Sucursal__c y Centro_de_Abastecimiento__c; Sucursal debe coincidir con el nombre del Pricebook, ej. "Precios S001")
3. Categoria__c, Familia__c, Unidad_de_Medida__c
4. Product2
5. Pricebook2 (Name alineado con Sucursal, ej. "Precios S001")
6. PricebookEntry
7. Domicilio_de_Cliente__c (Cliente__c → Account)
8. Facturas__c (Cliente__c → Account, Domicilio_Cliente__c → Domicilio_de_Cliente__c)
9. Detalle_Factura__c (Factura__c → Facturas__c, Product__c → Product2)
10. Costo__c (Codigo_del_Producto__c → Product2)
11. Rappel__c (Cliente__c → Account, Product__c → Product2)
12. Precios__c (Cliente__c → Account, Detalle_de_producto__c → Product2)
13. Descuento_Cliente__c (Cliente__c → Account, Producto__c → Product2)

Requisitos: respetar el orden por dependencias; mapear correctamente lookups/master-detail; asegurar que cada Facturas__c tenga Domicilio_Cliente__c válido; que al menos un Account tenga Sucursal__c cuyo prefijo coincida con el Name de un Pricebook2 (ej. S001 → "Precios S001"). Generar el script/config de SFDMU para export desde origen e import a destino.
```

---

Puedes copiar la sección “Resumen para pegar en el otro sistema” y enviarla tal cual al sistema que vaya a armar la carga SFDMU.
