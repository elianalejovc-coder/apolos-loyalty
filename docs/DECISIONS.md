# Apolo’s Loyalty — decisiones vigentes

## Confirmadas

1. **10 visitas = 1 recompensa.** La recompensa se emite de forma atómica al completar la décima visita del ciclo.
2. **`reward_pending` bloquea nuevas visitas.** El cliente debe canjear la recompensa antes de continuar con el siguiente ciclo.
3. **Ventana mínima de 12 horas** entre visitas. `admin` y `manager` pueden hacer override con motivo; queda auditado.
4. **Idempotencia obligatoria.** Cada registro de visita usa una clave única y los reintentos no generan una segunda visita.
5. **Canje único.** Una recompensa `available` pasa atómicamente a `redeemed`.
6. **QR público de fidelización es de solo lectura.** Escanear el QR general nunca registra una visita.
7. **Roles:** `admin`, `manager`, `employee`.
8. **Cliente:** solo puede consultar su propio progreso/recompensa; no puede escribir visitas, recompensas, reglas ni personal.
9. **Auditoría:** operaciones sensibles generan registros en `audit_log`.
10. **Persistencia del cliente:** cuenta Supabase Auth con enlace mágico por email en el MVP. No se usa fingerprinting invasivo.

## Reglas de roles

- `admin`: gestiona personal y operaciones; puede hacer overrides.
- `manager`: operación diaria, overrides y reversión de visitas.
- `employee`: búsqueda de clientes, registro de visitas y canje.

## Pendientes de producto

- Recuperación por teléfono OTP además de email.
- Fusión segura de perfiles cuando un cliente ya existente reclama su cuenta.
- Flujo visual de administración de personal desde el panel.
- Modal de override que obligue al empleado autorizado a escribir el motivo real.
- Historial detallado de cliente y reversión desde UI.
- QR público final con dominio de producción.
- SMTP de producción.
- Hosting y dominio final.
- Pruebas E2E en navegador y pruebas de concurrencia reales.
