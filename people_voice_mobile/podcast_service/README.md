# Servicio independiente de podcasts

Este servicio guarda los episodios y archivos de audio de la app, sin modificar la
web. La lista y los archivos son públicos. Para publicar, valida el Bearer token de
la sesión existente mediante `GET /api/v1/mobile/capabilities` y, si se selecciona
un artículo, comprueba que aparece publicado en `GET /api/v1/me/posts` para ese
usuario. La imagen `photo_link` de ese artículo se convierte en la portada; si
falta, se exige una portada subida.

## Despliegue en Ubuntu con systemd

El servicio nuevo se ejecuta directamente con Python bajo el usuario
`peoplevoice-podcasts`. Escucha solo en `127.0.0.1:8001`; la ruta HTTPS actual
de Cloudflare Tunnel puede seguir apuntando a ese puerto. Su código vive en
`/opt/people-voice-podcasts`, los secretos en
`/etc/people-voice-podcasts.env` (solo root puede leerlos) y la base SQLite y
los MP3 en `/var/lib/people-voice-podcasts`. La unidad aplica restricciones de
escritura y reinicia el proceso si falla. Mantén una sola instancia mientras se
use SQLite y almacenamiento local. El proxy debe permitir solicitudes de hasta
100 MB y `Range` para el MP3.

Para migrar el servidor que actualmente usa Docker, descomprime el ZIP de este
servicio y entra en `podcast_service/`. Ejecuta primero:

```sh
sudo python3 install_systemd.py prepare
```

Esta fase **no detiene** el contenedor actual. Instala un entorno virtual con
las dependencias fijadas, crea la unidad y toma las dos claves de Stripe del
entorno del contenedor sin mostrarlas. Consulta Stripe con la clave instalada e
imprime únicamente el modo, el estado HTTP, la cuenta y el código de error. Si
falla la creación del entorno virtual, instala `python3-venv` en Ubuntu y
repite `prepare`. Si Stripe no responde `200`, conserva el servicio actual y
resuelve la clave o conexión antes de continuar. Comprueba que el ID de cuenta
y el modo impresos coinciden con los de tu Stripe Dashboard.

Cuando `prepare` termine y el diagnóstico sea correcto, cambia de servicio:

```sh
sudo python3 install_systemd.py cutover
```

El instalador detiene el contenedor antiguo para copiar una imagen consistente
del volumen, valida `episodes.sqlite3` con `PRAGMA integrity_check`, inicia la
unidad y comprueba `/promotions/pricing` y `/episodes` en el puerto local. Si
algo falla, intenta reiniciar el contenedor anterior y conserva su volumen
original. Si funciona, deja el contenedor anterior detenido, sin eliminarlo,
por si fuera necesario volver atrás. Si el contenedor usa `restart=always`,
el instalador detiene el cambio antes de apagarlo para evitar un conflicto de
puerto tras reiniciar Ubuntu. El servicio nuevo ya no
depende de Docker ni de `compose.yaml`.

Para revisar el servicio después de la migración:

```sh
sudo systemctl status people-voice-podcasts --no-pager
sudo journalctl -u people-voice-podcasts -n 50 --no-pager
sudo python3 install_systemd.py diagnose
```

Conserva copias de seguridad de `/var/lib/people-voice-podcasts`, que contiene
`episodes.sqlite3` y `media/`. `prepare` y `cutover` se usan para la migración
inicial desde el contenedor; las actualizaciones posteriores deben conservar
ese directorio y `/etc/people-voice-podcasts.env`.

La base SQLite contiene tres tablas compartidas: `episodes`, `comments` y
`reactions`. Cada voto se identifica por cuenta y episodio; los comentarios
se guardan con el ID verificado de la cuenta y el nombre que proporcione la API.
La respuesta pública incluye `author_id` para que la app reconozca la cuenta
actual y muestre su nombre aunque el servidor de noticias no entregue el nombre
en `mobile/capabilities`. Para mostrar el nombre real de todas las cuentas en
todos los dispositivos, esa API debe devolver también `username`.

## Promociones pagadas de la app

Este mismo servicio también almacena las promociones de la app. No limita las
compras por usuario ni utiliza el Checkout antiguo del sitio web. Antes de
abrir Stripe, comprueba con la API de noticias que el artículo está publicado
y pertenece a la cuenta autenticada. El servidor crea una sesión de Stripe por
intento, con un identificador idempotente; nunca considera la vuelta del
navegador como prueba de pago. Solo un webhook firmado de Stripe con
`payment_status=paid` crea una solicitud pendiente y un aviso persistente para
los administradores. El aviso contiene la cuenta, el título y el ID del
artículo. Un administrador puede aprobarlo para mostrarlo durante siete días
en las secciones promocionales **de la app**, o rechazarlo y gestionar el
reembolso. La web no cambia y las promociones de la web siguen independientes.
Al pasar de `sk_test_` a `sk_live_`, un Checkout de prueba pendiente no se
reutiliza: el servicio crea un nuevo enlace real para el mismo artículo.

El instalador coloca `STRIPE_SECRET_KEY` y `STRIPE_WEBHOOK_SECRET` del
contenedor actual en `/etc/people-voice-podcasts.env`; ambas deben ser de la
misma modalidad (test o live). No compartas esas claves por chat ni las
incluyas en el ZIP.
Configura en Stripe un endpoint webhook adicional:
`https://podcasts.fayettevillethepeoplevoice.com/promotions/stripe/webhook`
para `checkout.session.completed`, `checkout.session.async_payment_succeeded`,
`checkout.session.async_payment_failed` y `checkout.session.expired`. El secreto
de **ese** endpoint debe estar en `STRIPE_WEBHOOK_SECRET`. El servicio mantiene
Checkout desactivado hasta que ambas claves estén configuradas; así no acepta
pagos sin poder recibir la confirmación. El precio predeterminado es USD 5.00
por siete días; puede configurarse con `PROMOTION_PRICE_CENTS`,
`PROMOTION_CURRENCY` y `PROMOTION_DAYS` en el archivo de entorno. Después de
editarlo, ejecuta `sudo systemctl restart people-voice-podcasts` y comprueba
`GET /promotions/pricing`: `available` y `review_enabled` deben ser `true`.

Si Checkout devuelve un error, el servicio muestra un código seguro y el
`req_...` de Stripe en la app. Consulta el detalle con
`sudo journalctl -u people-voice-podcasts -n 100 --no-pager`.
La línea `Stripe Checkout rejected` incluye el estado HTTP, código,
parámetro, ID de solicitud y mensaje de Stripe, sin registrar la clave API.
Si falla la conexión antes de recibir una respuesta, la línea
`Stripe Checkout transport failed` indica el tipo de error de red.
`available=true` solo confirma que las variables tienen formato válido; no
comprueba que la clave siga activa ni que la cuenta tenga permiso para Checkout.
Para comprobar la clave **que usa systemd**, sin imprimirla ni iniciar ningún
cobro, ejecuta desde el directorio del paquete:

```sh
sudo python3 install_systemd.py diagnose
```

Compara `stripe_key_mode` y `stripe_account_id` con la modalidad y la cuenta
que estás mirando en Stripe Dashboard. Si el estado HTTP no es 200, el comando
solo muestra el código del error; nunca muestra el valor de la clave.
Tras corregir una clave o un parámetro, si Stripe indica un conflicto de
idempotencia, inicia un intento nuevo en la app con «Previous checkout expired
or completed?»; no completes otro pago si el anterior ya se cobró.

La confirmación llega dentro de la app al refrescar notificaciones o al volver
a abrirla; no hay notificación push del sistema con la app cerrada. El estado
de cada pago queda en `GET /promotions/mine`. Los avisos están disponibles
para todos los administradores en `GET /promotions/admin/notifications` y las
solicitudes en `GET /promotions/admin/pending`. La lista pública de artículos
aprobados está en `GET /promotions/featured`.

La compra de una promoción mostrada dentro de la misma app se considera un
producto digital en las tiendas móviles. Antes de distribuir públicamente
esta interfaz de pago en iOS o Google Play, sustituye Stripe en esas plataformas
por StoreKit y Google Play Billing, respectivamente, y verifica sus recibos en
este servicio. La integración Stripe preparada aquí sirve para probar el flujo
del servidor y para canales donde esa compra externa esté permitida.

La app usa `https://podcasts.fayettevillethepeoplevoice.com` por defecto.
Para apuntarla a otro servidor al compilar Flutter, usa:

```sh
flutter build apk --dart-define=PODCAST_API_BASE_URL=https://podcasts.ejemplo.com
```

Usa el mismo `--dart-define` para iOS y macOS. Si no se especifica ese
parámetro, utiliza el dominio de producción.

Los MP3 subidos tienen límite de 85 MiB y las portadas de 5 MiB, dejando margen
para el formulario bajo el límite de 100 MB del proxy de Cloudflare. Como alternativa,
se permite un enlace HTTPS **directo a un archivo `.mp3`**; la reproducción se hace
en la app. Los enlaces de YouTube no se convierten ni se reproducen como audio
oculto porque las políticas de YouTube lo prohíben.

## API

- `GET /episodes?page=1`: público, 20 episodios por página.
- `DELETE /episodes/{id}`: Bearer de administrador verificado por la API de
  noticias. Elimina el episodio, sus comentarios, reacciones y medios locales.
- `POST /episodes`: Bearer, `multipart/form-data` con `title`, `audio` MP3,
  `article_id` opcional y `cover` cuando el artículo no tiene imagen.
- `POST /episodes/links`: Bearer, igual pero con `audio_url` HTTPS `.mp3`.
- `GET /media/{file_name}`: portadas y MP3 locales públicos.
- `GET /episodes/{id}/comments?page=1`: comentarios públicos.
- `POST /episodes/{id}/comments`: Bearer, JSON `{"body":"..."}`, máximo 1000 caracteres.
- `GET /episodes/{id}/reaction`: Bearer, voto actual de la cuenta.
- `PUT /episodes/{id}/reaction`: Bearer, JSON `{"value":"like"}`,
  `{"value":"dislike"}` o `{"value":"none"}`. Un voto por cuenta.

Para verificar localmente:

```sh
python -m pip install -r podcast_service/requirements.txt
python -m unittest podcast_service.test_app -v
```

## Payment Links (flujo simplificado, pendiente de activar en el servidor)

El código admite un enlace reutilizable de Stripe. En el archivo privado de entorno del servicio
configura `STRIPE_PAYMENT_LINK_URL` (URL https://buy.stripe.com/...) y
`STRIPE_PAYMENT_LINK_ID` (ID plink_...). Deben pertenecer a la misma cuenta y modo
que las claves existentes. Conserva `STRIPE_WEBHOOK_SECRET` y el endpoint
`/promotions/stripe/webhook`. El precio y moneda del enlace deben coincidir con
`PROMOTION_PRICE_CENTS` y `PROMOTION_CURRENCY`; usa cantidad fija 1, sin descuentos,
impuestos adicionales ni cantidades ajustables. Configura un pago único.

La app guarda el usuario y artículo autenticados y añade una referencia aleatoria al enlace.
No llama a la API de Stripe para crear Checkout. Solo una confirmación firmada con importe,
moneda, modo y enlace coincidentes genera la solicitud pagada y el aviso del administrador.
Los avisos incluyen usuario, importe y título; aparecen en la bandeja de la app, no son correo
ni notificaciones push. Los reenvíos no duplican solicitudes. Un segundo pago con el mismo
enlace y referencia se conserva como otra solicitud para revisión.

Sin esas dos variables continúa el flujo anterior para permitir una actualización gradual.
Primero instalar la app que acepta buy.stripe.com; las versiones anteriores rechazan ese dominio.
Probar en modo test antes de activar cobros reales. Esta preparación local no configura el
Dashboard de Stripe ni modifica el servidor remoto.
