# Auditoría PRD — 00028198 + 00028201 (solo lectura)

Fecha: 2026-11-26 · Orgs: ICB-DEVSERVICE / ICB-UAT (metadata desplegada); PRD pendiente de pase

## Modelo de permisos (CTA Crear Caso)

| Capacidad | Artefacto | Quién |
|-----------|-----------|--------|
| Ver checklist (fantasía + contacto) | PS `Checklist_Datos_FDR` (Apex + campos) | CCC + Wendy (Gerencia Superior) + operadores asignados |
| CTA **Crear Caso** | Custom Permission `Crear_Caso_FDR` vía PS homónimo | Solo CCC / operadores de servicio (**no** Wendy) |
| Gate en flow | `Caso_Ingreso` | Misma lógica de negocio |

Apex: `FeatureManagement.checkPermission('Crear_Caso_FDR')` (ya no hardcode de perfil). PSG `Ejecutivo_de_Servicio` incluye ambos PS.

## Perfiles operadores (lista cerrada)

| Perfil | Rol típico | Crea Caso | UX Sucursal |
|--------|------------|-----------|-------------|
| **CCC** | Ejecutivo de Servicio | Sí (PS `Crear_Caso_FDR`) | Sí |
| **Administrador del sistema** | Admin | Sí (si tiene el PS) | Sí |
| **Gerencia Superior** | Wendy Elgueta (En retiro) | No (sin `Crear_Caso_FDR`) | Sí (checklist vía `Checklist_Datos_FDR`) |
| Asesor comercial | Fuera de alcance CTA | No | N/A |

Asignaciones DEVSERVICE/UAT: ~21–22 usuarios con `Crear_Caso_FDR` (CCC + logística/crédito); Wendy solo checklist.

## Permission Sets (paquete CCC estándar)

Núcleo servicio (sin Delete de Case): `Gestion_service`, `Caso_Lectura_Escritura_Modificacion`, `Objeto_Caso_Lectura_Escritura`, `Acceso_a_Cuentas`, `Crear_Sucursal`, `Acceso_a_Sesiones_de_msj`, `Manage_Omni_Channel`, `Cuentas_PE`.

Wendy (Gerencia Superior): tiene `Caso_Lectura_Escritura_Modificacion` / cuentas, **sin** `Gestion_service` ni `Objeto_Caso_Lectura_Escritura`. Fuera del CTA Crear Caso por diseño (transcript: En retiro / misma bolsa UX).

## ProfileLayout Account

| Perfil | Holding | Negocio | Sucursal |
|--------|---------|---------|----------|
| CCC | Asesor comercial Holding | Asesor comercial | **vacío → asignar Account Layout** |
| Gerencia Superior | Asesor comercial Holding | Asesor comercial | Account Layout |
| Admin | Asesor comercial Holding | Asesor comercial | Account Layout |
| Asesor comercial | Asesor comercial Holding | Asesor comercial | Account Layout |

## FlexiPage / apps

- **Paneles**: CCC y Gerencia Superior → `LRP_Pagina_de_Registro_de_Sucursal` para `Account.Sucursal` (OK).
- **Service Console** (`standard__LightningService`): CCC/Gerencia **sin** override Sucursal → caen a `Account_Record_Page` (NO-RT). Hay que agregar override Sucursal → LRP.
