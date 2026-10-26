# Apolo's Loyalty

Sistema web de fidelización para Apolo's: una cuponera digital de 10 visitas, con una interfaz privada para el personal y una interfaz móvil de consulta para clientes.

## Objetivo del MVP
- Cliente: abrir desde QR, consultar progreso y recompensas sin instalar una app.
- Personal: registrar visitas válidas y canjear recompensas desde un panel autenticado.
- Seguridad: los escaneos públicos nunca suman sellos; las operaciones se validan en el servidor.
- Recuperación: permitir vincular teléfono verificado o correo mediante OTP/enlace mágico para recuperar el perfil en otro dispositivo.

## Estado
Repositorio inicial de especificación y arquitectura, con una pequeña pantalla de inicio de React. La aplicación completa, la base de datos conectada y el despliegue aún deben configurarse; no se deben introducir credenciales reales en Git.

## Documentos
- [Especificación del producto](docs/PRODUCT_SPEC.md)
- [Arquitectura y seguridad](docs/ARCHITECTURE.md)
- [Instrucciones para Claude Code](CLAUDE.md)

## Stack propuesto
- React + TypeScript + Vite
- Supabase Auth + PostgreSQL + funciones RPC/Edge Functions
- GitHub para control de versiones
- Hosting web (por decidir, por ejemplo Vercel)

## Desarrollo local
1. Instalar Node.js LTS.
2. Instalar dependencias con `npm install`.
3. Copiar `.env.example` a `.env.local` y completar solo las claves públicas necesarias.
4. Ejecutar `npm run dev`.

No se debe publicar hasta implementar y probar autorización, RLS, registro de visitas idempotente y canje de recompensas de un solo uso.
