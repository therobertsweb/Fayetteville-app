# App + backend: entrega para revisión local

Esta entrega sustituye los pendientes de implementación de Stripe y del backend
descritos en `DEBUG_REVIEW_2026-09-29.md`. No supone que el servidor ya esté actualizado.

## Implementado

- Seguimientos de categorías/autores, bloqueos, preferencias y eventos guardados
  por cuenta; cola local de cambios y sincronización con el servidor.
- “Para ti” con paginación y coincidencia real de categorías/autores. Catálogo y
  filtros de categorías en el backend; se excluye `Local Test Content`.
- Avisos dentro de la app para respuestas, publicaciones de autores seguidos y
  eventos guardados próximos. Comprobación al abrir/reanudar y cada minuto con
  la app activa; preferencias por tipo. Las respuestas desde la web también
  generan avisos. No hay entrega push cuando la app está cerrada.
- Eventos: filtros de fecha/gratuitos/familiares/búsqueda por ubicación,
  guardado por cuenta, mapa, organizador y exportación de calendario. Las fechas
  del servidor incluyen la zona de Fayetteville, America/New_York.
- Negocios: dirección, teléfono, web, horarios y búsqueda por actividad;
  solicitudes de corrección para revisión, sin modificar automáticamente fichas.
- Envíos de lectores autenticados: texto, ubicación opcional, foto privada,
  recibos de reintento y seguimiento recibido/en revisión/publicado/resuelto.
  Una foto enviada aquí NO se publica en `/static`. Solo autor y administradores
  pueden abrirla. Marcar “publicado” exige vincular un artículo público existente.
- Administración → Community & newsroom: revisar envíos/denuncias/correcciones,
  consultar fotos privadas, crear/editar/aprobar eventos y negocios.
- Mis artículos → My server articles: borradores/publicados/solicitudes de
  revisión, lecturas, comentarios, edición propia según permisos y promociones.
  Ediciones con versión y recibo de operación; recuperación local de texto y
  reintentos. Los borradores privados no se guardan en la caché pública.
- Lectura: tamaño de letra, modo oscuro, copiar enlace para compartir,
  denuncia de comentarios y ocultación de usuarios bloqueados. Bloquear aquí
  silencia contenido y avisos; no suspende la cuenta de otra persona.
- Featured Posts conserva su ubicación promocional y etiqueta Sponsored.
  El botón lleva a los artículos propios para iniciar Stripe Checkout.

## Stripe

Precio predeterminado: **USD 5 por 7 días**, pago único. La app consulta el precio
real del servidor antes de abrir Checkout. Solo admite promocionar artículos
publicados propios.

La clave secreta y el secreto del webhook permanecen en el backend. Checkout
alojado por Stripe no necesita incluir la clave pública en el cliente Flutter.

Cada intento conserva un identificador; servidor y Stripe reutilizan la sesión
en un reintento. El webhook verifica firma, antigüedad de la firma, propósito,
compra registrada, titular, artículo, moneda, importe y estado pagado. Un aviso
duplicado no activa dos semanas. Una renovación añade días a la fecha vigente.
La página de retorno no prueba un pago ni activa una promoción.

Endpoint:

`https://fayettevillethepeoplevoice.com/api/v1/stripe/webhook`

Eventos: `checkout.session.completed` y `checkout.session.async_payment_succeeded`.
Actualmente Checkout restringe los métodos a tarjeta. Los reembolsos/disputas y
pagos cuyo artículo se retiró antes de la confirmación requieren revisión manual
en Stripe y la redacción; no se ha implementado una política automática de reembolso.

Referencia utilizada para reintentos:
[Stripe: idempotent requests](https://docs.stripe.com/api/idempotent_requests).

## Pendiente para probar contra el dominio real

Comprobación de solo lectura del 29/09/2026:

| Ruta de producción | HTTP |
| --- | --- |
| `/api/v1/promotions/pricing` | 404 |
| `/api/v1/categories` | 404 |
| `/api/v1/me/preferences` | 404 |

Después del despliegue se espera 200 en las dos primeras y 401 sin sesión en la
tercera. Es necesario desplegar el backend local actualizado antes de probar
estas funciones desde Xcode contra producción. No se hizo ese despliegue.

1. Respaldar base de datos y archivos del servidor; conservar su `.env` privado.
2. Desplegar el código del backend en `fayetteville-people-voice/blog-post`.
   Su arranque existente con `db.create_all()` crea las tablas nuevas; la cuenta
   de base de datos necesita permisos de creación. No se borran tablas antiguas.
3. Verificar las variables de `.env.example`, incluidos `PUBLIC_SITE_URL`,
   `STRIPE_SECRET_KEY`, `STRIPE_WEBHOOK_SECRET`, importe, moneda y duración.
   No copiar claves secretas a Flutter, assets, capturas ni control de versiones.
4. Reiniciar el proceso Flask con el procedimiento habitual del servidor y
   comprobar las rutas indicadas. No se conoce aquí el nombre del servicio remoto.
5. Revisar la integración completa en un entorno Stripe de pruebas separado de
   live: checkout, cancelación, webhook repetido y activación. No se ejecutaron
   cobros reales ni se cambió el webhook de la cuenta Stripe.
6. Cargar datos reales de eventos/negocios y aprobarlos desde administración.
   El formulario requiere una ciudad activa ya configurada en el backend.

## Pruebas y límites

Comandos ejecutables sin generar una aplicación distribuible:

```sh
# people_voice_mobile
.tooling/flutter/bin/flutter analyze
.tooling/flutter/bin/flutter test

# fayetteville-people-voice/blog-post
.venv/bin/python -m pytest -q --disable-warnings
```

La cobertura incluye firmas/repeticiones/importes/monedas de Stripe con llamadas
simuladas; permisos, aislamiento de cuentas, fotos privadas, estados de revisión,
edición con conflictos, creación/aprobación de directorio, notificaciones,
preferencias offline, calendario y navegación hacia promociones.

El resultado actual es **152 pruebas de backend y 40 pruebas Flutter aprobadas**;
`flutter analyze --no-fatal-infos` termina correctamente y muestra 31 avisos de
estilo informativos, no errores. No se compiló macOS/iOS/Android ni se realizó
una nueva prueba manual en Xcode.
Quedan por verificar en dispositivo el selector de archivos, la importación de
calendarios, el navegador de Stripe, medios externos y los flujos autenticados
contra el backend desplegado. En móviles el calendario se abre como archivo ICS
desde el servidor; en escritorio se puede exportar desde los datos descargados.
