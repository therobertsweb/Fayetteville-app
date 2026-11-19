# Correcciones del diagnóstico — 19 de noviembre de 2026

## App y configuración Apple

- Un único encabezado «FEATURED POSTS» en News. El componente de promociones conserva su encabezado cuando aparece fuera de ese contexto.
- Sustitución de `cacheExtent` por `ScrollCacheExtent.pixels`, manteniendo la distancia de precarga.
- Manifiestos `PrivacyInfo.xcprivacy` integrados en los recursos de Runner, tanto en iOS como en macOS.
- Categoría News, hardened runtime y exclusión de permisos de depuración en macOS Release.
- Iconos macOS de 256 y 512 generados a partir del icono existente de 1024.
- El preflight ahora comprueba también la existencia de los iconos y de los archivos esenciales del SDK Android; ya no considera suficiente la presencia de carpetas vacías.

## Verificación completada

- `flutter analyze --no-pub`: sin incidencias.
- Suite completa: **122 pruebas aprobadas**.
- Prueba pública real: aprobada.
- Preflight de configuración de la app: aprobado.
- macOS Release compilado; firma local ad hoc verificada con `codesign --verify --deep --strict`. El paquete incluye el manifiesto, la categoría News y hardened runtime. No contiene `get-task-allow`, JIT ni permiso de servidor entrante.
- iOS Simulator Debug compilado; firma y manifiesto verificados. Instalado y abierto en iPhone 17 Pro con iOS 26.5: la pantalla principal carga noticias e imágenes reales. Captura: [iPhone](corrections-2026-11-19/fayette-fixed-ios.png).

Los archivos funcionales y recursos compilados se compararon con los del espacio de trabajo y coinciden.

## Entorno

La instalación de Flutter de `.tooling/flutter` estaba incompleta. `scripts/flutter.sh` utiliza una instalación completa (`$HOME/flutter`, configurable mediante `FLUTTER_SDK`) y mantiene Dart y Flutter en el mismo PATH. `tool/android-build` utiliza ese mismo lanzador.

La carpeta del Escritorio está sincronizada y añade metadatos de Finder a los frameworks, lo que puede impedir su firma. `scripts/build_apple_local.sh macos` y `scripts/build_apple_local.sh ios` compilan una copia temporal local del proyecto y muestran la ruta del paquete. No mueven el proyecto ni publican la app.

Java 17 fue reinstalado fuera de la carpeta sincronizada, en `$HOME/.local/share/fayetteville-tools/jdk17`, y Flutter fue configurado para utilizarlo. La instalación anterior incompleta se conserva en `.tooling/jdk-incomplete-20261119`. También se reinstaló Android Platform Tools y se verificó `adb version`.

## Android pendiente por decisión del usuario

Se finaliza con macOS e iOS verificados y se deja Android pendiente. Se detuvieron las descargas del NDK y de las herramientas de línea de comandos; sus archivos parciales se conservan en `/private/tmp/fayette-ndk28.zip` y `/private/tmp/fayette-cmdline.zip` mientras el sistema no limpie los temporales.

El SDK externo está en `$HOME/.local/share/fayetteville-tools/android-sdk`. Se restauraron Platform Tools, la plataforma Android 36 y Build Tools 36.0.0. El preflight pasa sus comprobaciones de archivos esenciales, pero no comprueba la integridad del NDK ni de sdkmanager y no sustituye una compilación.

El intento de compilar el APK falló porque sdkmanager está incompleto (`SdkManagerCli` ausente) y falta completar el NDK 28.2.13676358. Para retomar Android hay que completar esas dos instalaciones y repetir la compilación y las pruebas. **No se generó ni validó un APK Android.**

## Límites de la verificación

La firma ad hoc de macOS permite validar localmente el paquete; no equivale a una distribución firmada y notarizada. Las pruebas no realizan pagos, publicaciones, envíos de mensajes ni cambios administrativos en producción. Esos recorridos requieren una cuenta y un entorno de pruebas.

Las compilaciones Apple usan Swift Package Manager. La advertencia de Doctor sobre CocoaPods no bloqueó las compilaciones. El simulador iOS 26.5 instalado funcionó, aunque Doctor recomienda instalar también el runtime correspondiente a Xcode 27.2. Chrome no es necesario para estas apps nativas.

Persisten advertencias del compilador en dependencias nativas externas (audio y editor), sin errores de compilación; no se modificaron ni se ocultaron esas dependencias.

Registros: [corrections-2026-11-19](corrections-2026-11-19/).
