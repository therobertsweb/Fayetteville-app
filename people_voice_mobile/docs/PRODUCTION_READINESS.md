# Preparación de producción · revisión del 2–3 de octubre de 2026

Esta revisión distingue el código verificable localmente de la distribución
firmada y del servicio desplegado. Los comandos de este documento no publican
en tiendas ni despliegan el backend.

## Configuración nativa

- Android exige una firma propia para `release`. Ya no utiliza la clave debug.
  La tarea `validateReleaseSigning` detecta configuración incompleta, un archivo
  ausente y el alias de depuración antes de preparar el paquete.
- Android conserva `allowBackup=false` para los datos locales de cuentas y
  `INTERNET` en el manifiesto principal. Release requiere HTTPS; debug/profile
  permiten la API HTTP de desarrollo.
- Android sustituye los iconos de plantilla Flutter por el logotipo de la
  aplicación, incluidos iconos adaptativos con fondo blanco. La configuración
  compartida `flutter_launcher_icons.yaml` permite regenerarlos desde el original.
- iOS conserva App Transport Security: no hay excepciones generales para HTTP.
  La única excepción permite red local de desarrollo. No solicita cámara,
  micrófono, ubicación ni acceso completo a fotografías: selecciona archivos
  mediante el selector del sistema. La exportación ICS tampoco pide acceso
  completo a calendarios.
- iOS incluye el entitlement de Keychain usado por `flutter_secure_storage`.
  macOS usa el Keychain clásico mediante `usesDataProtectionKeychain: false`,
  como permite la versión instalada del plugin; no requiere compartir llavero.
- macOS release activa hardened runtime y sandbox, permite conexiones salientes
  y archivos elegidos por el usuario. Desactiva la inyección de entitlements base
  de Xcode para que release no incluya `get-task-allow`; tampoco habilita JIT ni
  servidor de depuración. [Apple: notarización y entitlements de depuración](https://developer.apple.com/documentation/security/resolving-common-notarization-issues).
- Identificadores actuales: Android `com.fayettevillepeoplevoice.people_voice`;
  Apple `com.fayettevillepeoplevoice.peopleVoice`. La versión parte de
  `pubspec.yaml`; cada entrega a tiendas requiere un número de compilación nuevo.

Referencia para la firma: [Flutter: publicar Android](https://docs.flutter.dev/deployment/android).

## Verificación reproducible

Desde `people_voice_mobile`:

```sh
python3 scripts/release_preflight.py
.tooling/flutter/bin/flutter analyze
.tooling/flutter/bin/flutter test

# Inspección de herramientas y configuración privada antes de distribuir.
python3 scripts/release_preflight.py --distribution --target android
python3 scripts/release_preflight.py --distribution --target ios
python3 scripts/release_preflight.py --distribution --target macos

# Solo GET anónimos; exige JSON, HTTPS y estados HTTP del contrato.
python3 scripts/release_preflight.py --api-url https://fayettevillethepeoplevoice.com
```

El preflight no imprime credenciales ni cuerpos del servidor, y no modifica
datos remotos. Un resultado correcto no verifica pagos, firma del paquete,
perfiles Apple ni flujos autenticados.

Resultado local de esta revisión: **16 comprobaciones de configuración pasan**;
el modo `--distribution` identifica tres requisitos ausentes: SDK Android,
configuración de firma Android y equipo Apple en iOS. Los plist, entitlements
y el proyecto macOS modificados pasan `plutil -lint`.

## Crear artefactos

Android: copiar `android/key.properties.example` a `android/key.properties` y
completar las cuatro propiedades con la clave de carga real del titular. El
archivo privado y las claves están excluidos por `android/.gitignore`. También
pueden inyectarse secretos del sistema CI:

| Propiedad | Variable de entorno |
| --- | --- |
| `storeFile` | `ANDROID_KEYSTORE_PATH` |
| `storePassword` | `ANDROID_KEYSTORE_PASSWORD` |
| `keyAlias` | `ANDROID_KEY_ALIAS` |
| `keyPassword` | `ANDROID_KEY_PASSWORD` |

Las variables tienen prioridad. Usar una ruta absoluta de keystore; las rutas
relativas se resuelven desde `android/`. La validación real de contraseñas y
certificado ocurre al firmar con Gradle.

```sh
.tooling/flutter/bin/flutter build appbundle --release
```

iOS: seleccionar en Xcode el equipo Apple del titular para Runner, confirmar el
Bundle ID registrado y el perfil de distribución, después:

```sh
.tooling/flutter/bin/flutter build ipa --release
```

`flutter build ios --release --no-codesign` permite verificar compilación y no
genera una entrega distribuible. macOS:

```sh
.tooling/flutter/bin/flutter build macos --release
```

La aplicación macOS debe archivarse y firmarse para el canal elegido: Mac App
Store o Developer ID con notarización. La firma ad hoc utilizada para pruebas
locales no sustituye esa distribución. No se han creado claves ni modificado
identidades del titular.

## Privacidad y revisión de tiendas

La app incluye `PrivacyInfo.xcprivacy` en los recursos de Runner iOS y macOS,
declarando el acceso a metadatos de archivos: `C617.1` para la base local/caché en
el contenedor y `3B52.1` para comprobar el tamaño de imágenes elegidas mediante
el selector. Son los usos observados en el código; no se declaran usos de APIs
que la app no necesita. [Apple: razones de acceso a archivos](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype).

El motor Flutter instalado y los plugins nativos incluyen manifiestos de
privacidad. Se inspeccionaron los de `flutter_secure_storage_darwin`,
`sqflite_darwin`, `webview_flutter_wkwebview` y los bundles del build macOS
existente. Deben conservarse en el archivo final; generar el informe de
privacidad desde el Archive de Xcode antes de subirlo. El manifiesto propio
declara razones de acceso; no afirma que el servicio no recoge datos.

El titular debe contrastar las etiquetas App Privacy/Data safety y la política
publicada con los datos reales del servicio: cuenta y correo, contenido y fotos
enviados, preferencias, interacción con artículos, registros del servidor y los
servicios externos de vídeo/pago. El manifiesto de un SDK no sustituye las
declaraciones de la aplicación. [Apple: manifiestos de privacidad](https://developer.apple.com/documentation/bundleresources/privacy-manifest-files).

Las promociones Featured Posts se pagan mediante un enlace a Stripe. Antes de
distribuir hay que confirmar storefronts y modalidad de compra: Apple distingue
los enlaces externos permitidos en Estados Unidos de otros storefronts, y
regula la compra de promociones consumidas dentro de una app. No se ha añadido
StoreKit ni asumido autorización global del enlace. Si se habilita creación de
cuentas en la app, debe existir eliminación de cuenta accesible desde ella.
[Apple: App Review, 3.1.1(a), 3.1.3(g), 5.1.1(v)](https://developer.apple.com/app-store/review/guidelines/).

## Bloqueos comprobados de este entorno

- No hay Android SDK en la ubicación estándar ni `sdk.dir` configurado; no se
  encontró `android/key.properties`. Hace falta el entorno Android y la clave
  real del titular para construir una entrega firmada.
- El target iOS no configura `DEVELOPMENT_TEAM`. La compilación sin firma puede
  comprobarse, pero no reemplaza certificados/perfiles de distribución.
- `xcodebuild -showdestinations -workspace ios/Runner.xcworkspace -scheme Runner`
  no encuentra destinos iOS elegibles: tanto `Work_phone` como el destino genérico
  indican que falta instalar iOS 26.5 en Xcode → Settings → Components. Es un
  bloqueo anterior a la compilación, aunque exista el directorio de SDK en disco.
- El target macOS sí contiene un equipo; eso por sí solo no prueba que haya
  certificado Developer ID/App Store y perfil aptos para distribuir.
  `security find-identity -v -p codesigning` devuelve cero identidades válidas
  accesibles en esta sesión. Un build local con firma ad hoc no resuelve esto.
- Los flujos de escritura, inicio de sesión, selección de archivos, reproducción
  externa, calendario y pagos deben verificarse en dispositivos con una cuenta
  de prueba contra el backend desplegado. Las pruebas locales simuladas no
  equivalen a esa integración. No se efectuaron cobros ni publicaciones reales.

La disponibilidad del backend real debe comprobarse con el preflight anterior:
seis rutas públicas/protegidas deben responder según contrato. Los resultados
históricos de `REVIEW_READY_2026-09-29.md` no prueban el estado actual del dominio.

## Cierre de la revisión

La verificación final del cliente, las capturas y el artefacto se registran en
[FINAL_REVIEW_2026-10-03.md](FINAL_REVIEW_2026-10-03.md). El 2 de octubre las seis
rutas del preflight HTTP respondieron con los estados esperados, incluyendo
`/categories` y `/promotions/pricing` (200) y `/me/preferences` sin sesión (401).
Esto sustituye los fallos históricos de categorías descritos en las revisiones
de septiembre; no certifica flujos autenticados ni cobros.
