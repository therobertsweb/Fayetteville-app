# Diagnóstico de la app — 19 de noviembre de 2026

Versión examinada: 1.0.0+15. Flutter utilizado: /Users/dev/flutter, 3.47.9, Dart 3.13.7.

## Resultado

La compilación de depuración para macOS funciona y las consultas públicas probadas responden correctamente. No se puede afirmar que todo funciona: hay un fallo visual reproducible y problemas de configuración de distribución. Esta revisión no modifica el código funcional ni publica contenido.

| Comprobación | Resultado |
| --- | --- |
| Suite completa `flutter test --no-pub` | 121 pruebas aprobadas, 1 fallida |
| Repetición aislada de la prueba fallida | Mismo fallo reproducido |
| `flutter analyze --no-pub` | Sin errores ni warnings; 1 aviso informativo de API obsoleta |
| `flutter build macos --debug --no-pub` | Compilación correcta; avisos de iconos ausentes |
| Prueba pública real `tool/smoke_public_test.dart` | Aprobada |
| Preflight de configuración y API | 5 comprobaciones fallidas |
| Servicio público de podcasts `/episodes` | HTTP 200, objeto JSON con `data` y `next_page` |

## Hallazgos

1. **Encabezado duplicado en el feed.** `lib/ui/home.dart` muestra `FEATURED POSTS` tanto en la fila de promociones como dentro de `PromotionalFeatured`. Cuando hay promociones se renderizan ambos. Falla `test/design_test.dart:145` porque espera un único encabezado. Confirmado también ejecutando esa prueba por separado.
2. **Manifiestos de privacidad sin integración en los proyectos Apple.** Existen `ios/Runner/PrivacyInfo.xcprivacy` y `macos/Runner/PrivacyInfo.xcprivacy`, con las razones que comprueba el script, pero no están referenciados en los respectivos `project.pbxproj`. Fallan dos comprobaciones de inclusión en recursos.
3. **Categoría de macOS ausente.** Falta `LSApplicationCategoryType` en el Info.plist fuente y en el de la app Debug compilada. Falla la comprobación local de categoría News.
4. **Dos ajustes de distribución macOS no declarados.** El preflight no encuentra `ENABLE_HARDENED_RUNTIME = YES` ni `CODE_SIGN_INJECT_BASE_ENTITLEMENTS = NO`. Esto describe la configuración del proyecto; no se ha validado un archivo Release firmado ni su configuración efectiva.
5. **Iconos incompletos.** El catálogo de macOS referencia `app_icon_256.png` y `app_icon_512.png`, que no existen. Xcode avisa, aunque completa la compilación.
6. **Aviso menor del analizador.** `cacheExtent` en `lib/ui/home.dart:614` está obsoleto en el SDK utilizado. No impide compilar.
7. **Entorno de desarrollo incompleto.** Doctor informa de `adb` ausente, simulador iOS 27.2 no instalado y CocoaPods no instalado. macOS sí compiló con la integración disponible. También detecta distintas instalaciones de Flutter/Dart en PATH y Chrome ausente; Chrome no es necesario para los destinos nativos de este proyecto.

## Alcance comprobado

La suite cubre navegación, diseños adaptables, categorías, lectura, búsqueda, guardados, datos sin conexión, aislamiento de cuentas, borradores/editor, medios, comentarios, preferencias, promociones, podcasts y administración mediante pruebas automatizadas y respuestas simuladas.

Las consultas reales de solo lectura verificaron noticias, destacados, búsqueda, eventos, negocios, rankings, detalle de artículo, comentarios, categorías, precios de promociones y los rechazos 401 esperados de preferencias/capacidades sin autenticación. Podcasts devolvió una respuesta pública correcta; esto no prueba la reproducción de audio.

## Pendiente para comprobar el funcionamiento completo

- Recorrido manual en la aplicación abierta, incluyendo imágenes, desplazamiento y reproducción real de audio/video.
- Inicio de sesión y flujos autenticados contra el servidor con una cuenta de pruebas: sincronización, comentarios, cargas, publicación y administración.
- Checkout con entorno de pagos de prueba y confirmación del servidor.
- Compilación y ejecución en iPhone y Android; esta sesión compiló únicamente macOS Debug.
- Archivo Release firmado, recursos de privacidad e iconos dentro del paquete final.

No se realizaron pagos, envíos de mensajes, publicaciones, borrados de datos de producción ni subidas a las tiendas.

## Evidencia

Los registros completos están en [diagnostics-2026-11-19](diagnostics-2026-11-19/): `tests.log`, `repro.log`, `analysis.log`, `build.log`, `smoke.log`, `preflight.log` y `doctor.log`.
