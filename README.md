# Apolo's Loyalty

Sistema web de fidelización para Apolo's: una cuponera digital de 10 visitas, con una interfaz privada para el personal y una interfaz móvil de consulta para clientes.

## Qué hay ahora

- React + TypeScript + Vite funcionando como cliente web.
- Supabase local configurado en `supabase/config.toml`.
- Migraciones PostgreSQL ordenadas para esquema, operaciones, roles, permisos y consistencia de ciclos.
- RLS + grants de mínimo privilegio.
- RPC server-side para buscar clientes, registrar visitas, emitir/canjear recompensas, revertir visitas y consultar el dashboard del cliente.
- Idempotencia para evitar doble registro de visitas.
- Ventana mínima de 12 horas entre visitas, con override de manager/admin y auditoría.
- Recompensa automática en la visita 10.
- QR único por recompensa y canje de un solo uso.
- Login por enlace mágico de Supabase Auth.
- Tests pgTAP y CI de frontend.

## Documentación

- `docs/PRODUCT_SPEC.md` — reglas del producto.
- `docs/ARCHITECTURE.md` — arquitectura y límites de seguridad.
- `docs/SUPABASE_SETUP.md` — instalación local, pruebas, primer admin y despliegue.
- `CLAUDE.md` — instrucciones permanentes para Claude Code.

## Desarrollo local

Requisitos: Node.js 20+ y Docker Desktop (Windows/Linux) o runtime compatible.

```bash
npm install
npx supabase start
npx supabase status
```

Copia `.env.example` a `.env.local` y usa el Project URL + publishable key mostrados por `supabase status`.

Luego:

```bash
npm run dev
npm run supabase:test
```

Para recrear completamente la base local:

```bash
npm run supabase:reset
```

El reset aplica todas las migraciones y después `supabase/seed.sql`.

## Supabase hospedado

El repositorio contiene la configuración y las migraciones, pero crear el proyecto privado hospedado requiere hacerlo en la cuenta/organización del propietario de Supabase. Una vez creado:

```bash
npx supabase login
npx supabase link --project-ref <PROJECT-REF>
npx supabase db push
```

No hagas cambios estructurales directamente en producción desde SQL Editor una vez que las migraciones sean la fuente de verdad.

## Seguridad

- El QR público nunca registra una visita.
- El cliente no puede insertar/modificar visitas o recompensas directamente.
- `record_visit` y `redeem_reward` son funciones server-side con validación de rol.
- Las visitas son idempotentes.
- El canje es atómico y de un solo uso.
- No se usan huellas invasivas del dispositivo.
- Nunca poner `service_role`/secret keys en variables `VITE_` ni en Git.

## Roles

| Rol | Acceso |
|---|---|
| `admin` | Administración completa, personal y overrides |
| `manager` | Operación, overrides y reversión de visitas |
| `employee` | Buscar clientes, registrar visitas y canjear recompensas |
| cliente | Solo su propio progreso/recompensas |
