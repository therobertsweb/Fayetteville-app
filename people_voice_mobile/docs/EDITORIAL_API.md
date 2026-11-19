# Contrato de integración editorial de la app

Estado: cliente Flutter y API web local implementados. Las rutas viven en
`../fayetteville-people-voice/blog-post/blogr/mobile_api.py`. El servidor publicado
todavía debe desplegarse y verificarse. El cliente activa las funciones remotas
por defecto para el servidor local; puede desactivarlas con
`--dart-define=EDITORIAL_API_ENABLED=false`. La clave del proveedor de IA pertenece al servidor.

Base: `/api/v1`. JSON UTF-8; autenticación Bearer en todas las rutas salvo rankings
públicos. Respuestas privadas: `Cache-Control: no-store`. El servidor debe validar
identidad, rol y permisos en cada solicitud; `can_publish` no equivale a admin.

## Imágenes y contenido multimedia

`POST /media/images`, autenticado y con permiso de publicación, recibe multipart
con el campo `image`. Acepta JPG, PNG, GIF y WebP hasta 5 MB y 20 millones de
píxeles; verifica y recodifica a WebP estático. Devuelve HTTP 201 con
`{"data":{"url":"/static/media/posts/editor/identificador.webp"}}`.
Límite: 30 subidas por cuenta por hora. Archivos inválidos producen HTTP 400;
solicitudes multipart mayores de 6 MB producen HTTP 413.

Los borradores guardan el documento del editor, HTML y bytes de imágenes locales
en SQLite. La publicación sube solo las imágenes referenciadas y reemplaza sus
rutas locales antes de enviar el HTML al servidor. Un reintento conserva los
recibos de subidas completadas. La selección de un archivo no publica el artículo.

El HTML admite formato básico, enlaces, imágenes, reproductores de YouTube,
Facebook, TikTok y Vimeo y etiquetas `video`/`source` con URLs HTTPS directas.
Se eliminan atributos ejecutables y marcos de dominios no permitidos.

## Featured Posts promocionales

El flujo de aprobación pagada descrito aquí requiere cambios en el servidor de
la API; **la API publicada el 20 de octubre de 2026 todavía no expone
`/admin/promotions` ni la capacidad `promotions:review`**. Las tres apps usan
el mismo cliente Flutter. No deben aceptar nuevos pagos hasta que el servidor
devuelva `review_enabled: true` en `GET /promotions/pricing`.

`POST /posts/{post_id}/featured/checkout` requiere Bearer y solo permite al
autor del artículo publicado iniciar Checkout. La sesión se vincula en el
servidor al `user_id`, `post_id`, `operation_id`, importe y moneda. El cliente
abre `checkout_url` en Stripe; nunca considera un retorno del navegador como
confirmación del pago.

El webhook de Stripe verifica la firma y procesa de forma idempotente
`checkout.session.completed` si `payment_status == paid` y
`checkout.session.async_payment_succeeded`. Comprueba sesión, importe, moneda,
usuario y artículo contra el registro del servidor. Una vez pagado, crea una
solicitud `pending` y una notificación para los administradores con
`kind: promotion_review`, `promotion_id`, `article_id`, título del artículo,
identidad del comprador y fecha de pago. El webhook **no** activa
`featured_until` ni publica el artículo en `/posts/featured`.

`GET /mobile/capabilities` añade `promotions:review` solo para administradores.
`GET /admin/promotions?status=pending&limit=100&cursor=…` requiere esa capacidad,
devuelve una lista paginada de solicitudes pagadas pendientes y sus versiones:

```json
{"data":[{"id":51,"version":1,"status":"pending","payment_status":"paid","paid_at":"2026-10-20T18:00:00Z","article":{"id":72,"title":"Community story"},"user":{"id":19,"username":"Author","email":"author@example.com"}}],"next_cursor":null}
```

`POST /admin/promotions/{id}/decision` recibe `decision: approve|reject`,
`version`, `operation_id` y, para rechazar, `reason`. Es exclusivo de admins,
idempotente y solo acepta una solicitud `pending` con pago confirmado. Repite
la comprobación de que el artículo sigue publicado y es apto. Al aprobar,
empieza la duración pagada de siete días y expone el artículo en
`GET /posts/featured`; al rechazar, no lo expone y registra la gestión del
pago o reembolso. El servidor notifica el resultado al comprador y devuelve
un conflicto si la versión cambió. `GET /me/posts` incluye
`promotion_status: pending|approved|rejected` para que el autor pueda verlo.
La app muestra el listado público de promociones tanto en la segunda sección
de noticias como al final de cada artículo, excluyendo el artículo actual de
las recomendaciones del lector.

## Capacidades

`GET /mobile/capabilities`:

```json
{"data":{"user_id":42,"role":"admin","permissions":["ai:write","drafts:manage","analytics:read","rankings:read","saves:write","notifications:read"]}}
```

Roles: `admin`, `editor`, `author`, `moderator`, `advertiser`, `commenter`.
La cuenta verificada y activa determina los permisos; no aceptar rol del cliente.

## Generación y edición con IA

`POST /ai/writing-assist` recibe `title` (hasta 100 caracteres), `content` (hasta
100000), `instruction` (tarea e instrucciones del usuario) y `format: plain_text`.
Título y contenido vacíos están permitidos para generar desde una idea.
Devuelve `{"data":{"title":"…","content":"…"}}`. Nunca publica ni guarda
por sí mismo. La app muestra la propuesta, permite aplicarla y conserva una
versión anterior para deshacer. Aplicar límites por usuario, tiempos máximos,
errores 429/503 y protección de credenciales en el servidor. La respuesta no debe
contener HTML ni instrucciones para ejecutar acciones administrativas.

## Favoritos y rankings

`POST /posts/{id}/saved`: `{"saved":true,"mutation_id":"identificador único"}`.
Un favorito activo por usuario/artículo. Las mutaciones se reintentan con el mismo
ID; deduplicarlas para que no incrementen contadores al reintentar. Favoritos de
invitado quedan locales. Leer sin conexión no cuenta como favorito.

`GET /rankings?metric=saves|comments&days=7|30|90`:

```json
{"data":[{"article":{"id":123,"title":"Una historia","created":"2026-09-28T12:00:00Z"},"count":18}]}
```

Contadores enteros no negativos; solo artículos públicos. Comentarios: comentarios
publicados creados en el periodo. Favoritos: usuarios distintos cuyo favorito
sigue activo y se añadió en el periodo. Orden descendente, desempate estable por
ID. Devolver top 20; el gráfico muestra top 10. Sin actividad: lista vacía.

## Borradores y operaciones administrativas

`GET /admin/drafts?limit=100&cursor=…` devuelve solo borradores remotos privados:

```json
{"data":[{"id":123,"version":"opaque-revision","title":"Historia","content":"<p>Texto</p>","created":"2026-09-28T12:00:00Z","author":{"id":7,"username":"ana","role":"author"}}],"next_cursor":null}
```

Paginar con cursores estables. `version` debe cambiar ante cualquier edición de
contenido/autor/estado. Borradores que solo existen en otro dispositivo no pueden
verse aquí hasta enviarse al servidor. La app agrupa por rol y usuario y permite
filtrar, seleccionar individualmente, por usuario o todos los resultados.

`POST /admin/drafts/bulk`:

```json
{"operation_id":"ID único","action":"publish","items":[{"id":123,"version":"opaque-revision"}]}
```

`action`: `publish` o `delete`. El alcance es **exclusivamente** la lista explícita
de IDs; nunca una orden global sin límites. Comprobar permisos de admin y versión
actual de cada artículo. No tocar artículos ya publicados ni contenido cambiado.
Publicar conserva el autor original; eliminar debe resolver dependencias de forma
transaccional. Auditar administrador, acción, IDs, versiones y resultado. Un ID de
operación repetido por el mismo administrador devuelve el mismo recibo; si cambia
el contenido de la petición devolver 409. Debe sobrevivir a reinicios del servidor.

```json
{"operation_id":"ID único","status":"completed","results":[{"id":123,"success":true},{"id":124,"success":false,"message":"El borrador cambió. Actualiza para revisarlo."}]}
```

Un resultado por cada ID solicitado, sin duplicados. Soportar éxito parcial.
`GET /admin/operations/{operation_id}` devuelve el recibo, solo al administrador
propietario. Si sigue trabajando devolver `status: pending`. La app persiste el
ID antes del envío y bloquea nuevos lotes mientras el resultado sea incierto.
No reenviar automáticamente publicaciones o eliminaciones sin confirmar.

`GET /admin/statistics?days=7|30|90`:

```json
{"data":{"published":20,"drafts":8,"active_authors":3,"by_author":[{"username":"ana","role":"author","published":12}],"most_saved":[{"article":{"id":123,"title":"Historia"},"count":18}],"most_commented":[{"article":{"id":123,"title":"Historia"},"count":9}]}}
```

Publicados/autores activos se cuentan en el periodo; drafts es el total pendiente
actual. Los rankings usan las mismas definiciones que el endpoint público.

## Notificaciones dentro de la app

`GET /notifications?limit=100&cursor=…`: solo notificaciones del usuario autenticado.

```json
{"data":[{"id":"501","title":"Nuevo comentario","message":"Hay una respuesta en tu artículo.","created":"2026-09-28T12:00:00Z","read":false,"article_id":123}],"next_cursor":null}
```

IDs string estables, fecha ISO 8601 UTC, `article_id` opcional y solo para artículos
públicos accesibles. `POST /notifications/read` recibe `{"ids":["501"]}`; operación
idempotente, comprobar propiedad de cada ID, devolver `{}` o HTTP 204. No aceptar
IDs de otra cuenta. Crear eventos al comentar, publicar/revisar artículos y otras
acciones relevantes para su destinatario. Evitar avisos duplicados del mismo evento.

La app guarda la bandeja y marcas de lectura en SQLite por cuenta, conserva las
lecturas offline para sincronizar, muestra contador de no leídas y actualiza al
abrir, volver al primer plano y cada minuto mientras está activa. También registra
localmente los cambios de estado de sus propios envíos. Las noticias y podcasts
públicos pueden recibirse además mediante Firebase, solo dentro de la app; véase
[PUSH_SETUP.md](PUSH_SETUP.md). No se muestran avisos de sistema con la app cerrada.
La bandeja privada por API no necesita permiso de notificaciones.

## Validación antes de activar

Probar 401/403 por rol y cuenta, paginación, listas vacías, contadores cero,
versiones desactualizadas, deduplicación de favoritos, borrados y publicaciones
parciales, respuestas perdidas, reconciliación tras reinicio, bandejas aisladas
por usuario y proveedor IA indisponible. No activar usando datos ficticios en
producción. Las pruebas Flutter usan SQLite real y HTTP simulado.
