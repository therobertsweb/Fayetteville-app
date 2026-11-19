# Firebase: avisos exclusivamente dentro de la app

Revisión del 19 de noviembre de 2026. Proyecto: `fayetteville-the-people-voice`
(número `422174023287`). Se recuperó la configuración anterior de Firebase;
esta copia de la app no contenía los archivos ni las dependencias.

## Aplicaciones registradas

| Plataforma | Identificador |
| --- | --- |
| iOS | `com.fayettevillepeoplevoice.peopleVoice` |
| Android | `com.fayettevillepeoplevoice.people_voice` |
| macOS | `com.fayettevillepeoplevoice.mac.a9x2dv8x8l` |

macOS tiene un registro propio, creado durante esta revisión. No se cambió su
bundle ID para reutilizar el de iOS. Los archivos `GoogleService-Info.plist`,
`google-services.json` y `lib/firebase_options.dart` corresponden a estos registros.
Son configuración de cliente; ninguna clave privada de servidor está en la app.

## Comportamiento

En Preferences → Live updates in the app se activan noticias y podcasts.
La elección se guarda en el dispositivo y está desactivada inicialmente.
La app recibe `FirebaseMessaging.onMessage`, guarda un único aviso por contenido
y cuenta en SQLite, y actualiza la bandeja y el contador de la campana.
Los avisos repetidos no vuelven a marcar como no leído un contenido ya leído.

Los mensajes recibidos cuando la app no está activa se descartan. No se registra
un manejador Dart de segundo plano ni se presentan banners, sonidos o badges del
sistema. Los mensajes de alertas de versiones anteriores y los tipos privados
no se añaden a esta bandeja pública. Las respuestas a comentarios y otras
actividades privadas continúan usando la API autenticada existente.

Los temas nuevos son `people_voice_news_in_app_v1` y
`people_voice_podcasts_in_app_v1`. No reutilizar los antiguos temas que podían
contener alertas del sistema. La app elimina las suscripciones antiguas cuando
sincroniza; al desactivar la opción elimina el registro de mensajería.

## Requisito del emisor

El servidor debe enviar **solo datos**, sin `notification`, `aps.alert`,
`aps.sound` ni `aps.badge`. Desactivar la presentación de primer plano en el
cliente no evita que iOS muestre una alerta enviada por un servidor cuando la
app está cerrada. Por eso el formato y los temas separados son necesarios.

Generar un ejemplo sin enviar nada:

```sh
python3 scripts/firebase_in_app_payload.py \
  --kind news --content-id 42 \
  --title 'Community update' --body 'A new story is available.'
```

El ejemplo de [payload](notifications-2026-11-19/fcm-data-only-example.json)
incluye datos de destino, TTL cero en Android y expiración cero en APNs: no se
pretende guardar avisos para mostrarlos cuando se vuelva a abrir la app. La
entrega silenciosa sigue dependiendo del sistema operativo y de la conexión.
El historial privado se recupera por la API de la bandeja, no por estos temas.

Firebase HTTP v1 aceptó este formato con `validate_only: true` (HTTP 200).
**Esta validación no envía mensajes y no confirma entrega al dispositivo.**
El emisor de producción aún debe comprobarse/adaptarse a este contrato; no se
ha desplegado un worker ni una campaña de Firebase desde esta revisión.

## Apple

FCM usa APNs también para mensajes de datos en Apple. La app declara el permiso
APNs, incluye los archivos Firebase en los targets y habilita el modo de registro
que requiere Firebase Messaging 17.0.1. iOS referencia `Runner.entitlements`
en Debug, Profile y Release: tener ese archivo sin referenciarlo no basta.

macOS requiere firma de desarrollo y un perfil con APNs; una firma ad hoc ya
no basta para esta integración. Se ajustó `CODE_SIGN_IDENTITY` en Runner y se
obtuvo el perfil mediante Xcode con actualizaciones de aprovisionamiento.
Para distribuir, exportar con el método y la firma de distribución adecuados.

La clave APNs de Apple debe estar configurada en Firebase para cada aplicación
Apple. Que el registro Firebase exista o que un payload pase `validate_only`
no permite confirmar que esa clave esté operativa. Una clave de la API de
App Store Connect tampoco sustituye las credenciales APNs.

## Prueba de entrega antes de TestFlight

1. Instalar una compilación firmada con el permiso APNs en un iPhone de prueba.
2. Activar Live updates in the app y comprobar que no aparece un error de conexión.
3. Dirigir un mensaje de datos únicamente al registro de ese dispositivo; no usar
   un tema público para la prueba. Confirmar aviso en la bandeja y aumento del contador.
4. Repetir el mismo contenido para confirmar que no duplica el aviso.
5. Comprobar que no aparecen alertas del sistema con la app en segundo plano.
6. Verificar preferencias, lectura offline y cambio de cuenta.

Las pruebas automatizadas verifican el manejo de datos, deduplicación, lectura,
aislamiento entre cuentas, exclusión de mensajes de sistema y reintentos.
No reemplazan la prueba del transporte Firebase → APNs → dispositivo.

## Referencias

- [Firebase: configuración de FCM para Flutter](https://firebase.google.com/docs/cloud-messaging/flutter/get-started).
- [Firebase: recepción de mensajes](https://firebase.google.com/docs/cloud-messaging/flutter/receive-messages).
- [Apple: registro con APNs](https://developer.apple.com/documentation/usernotifications/registering-your-app-with-apns).
- [Apple: subida de compilaciones](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds).
