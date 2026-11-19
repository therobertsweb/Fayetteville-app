# Revisión final · 3 de octubre de 2026

La app quedó mejorada y verificada como candidata para revisión local. La entrega
a tiendas permanece condicionada a firma, herramientas móviles y validación de
integraciones con cuentas de prueba. No se publicó una versión ni se hicieron
cobros, publicaciones, comentarios o envíos reales.

## Resultado verificado

| Comprobación | Resultado |
| --- | --- |
| `flutter analyze` | Sin incidencias |
| `flutter test` | 64 pruebas aprobadas |
| `flutter test tool/smoke_public_test.dart` | 1 prueba real de lectura aprobada |
| `release_preflight.py --api-url https://fayettevillethepeoplevoice.com` | 22 comprobaciones aprobadas: 16 nativas y 6 HTTP |
| `flutter build macos --release` | Compilación universal x86_64/arm64 generada, 59,0 MB |
| `codesign --verify --deep --strict` | Firma e integridad del bundle válidas |
| Manifiesto de privacidad en bundle | Presente, `plutil -lint` correcto |

La firma del artefacto es **ad hoc**, con hardened runtime. Sus entitlements
permiten sandbox, red saliente y archivos elegidos por el usuario; no incluyen
JIT, servidor de depuración ni `get-task-allow`. Esa verificación de integridad
no lo convierte en un instalador firmado/notarizado para distribución pública.

## Mejoras visuales

- Portada con cabecera legible en móvil, navegación de cinco destinos y menú
  More que conserva categorías, artículos propios y cuenta.
- Tema editorial coherente en claro y oscuro, tarjetas, botones, formularios,
  separadores, iconos y textos con colores adaptados al fondo.
- Búsqueda con estados inicial, carga, vacío, error y reintento; biblioteca con
  favoritos y descarga local; categorías con iconos propios y acceso permanente.
- Lector con metadatos, tiempo de lectura, selección de texto, favoritos y
  acceso a ajustes. Imágenes no disponibles con estado legible en ambos temas.
- Preferencias agrupadas, vista previa del tamaño de texto y notificaciones
  con jerarquía de leídos/no leídos y fechas seguras.
- Cuenta con validación antes del envío, autocompletado, visibilidad de contraseña
  y formulario antes de enlaces secundarios. Recuperación de almacenamiento
  con reintento sin pedir borrar borradores.
- Iconos Android de marca en lugar de los iconos de plantilla.

Capturas reproducibles generadas por pruebas con datos de ejemplo:

- [Móvil claro](../build/previews/iphone-news.png)
- [Móvil oscuro](../build/previews/iphone-dark.png)
- [Escritorio](../build/previews/macos-news.png)

Las pruebas de diseño cubren anchos 320, 390, 700, 834 y 1440; las nuevas pruebas
comprueban también texto a 1,8×, navegación móvil y recuperación de búsqueda.
Estas capturas no sustituyen una sesión manual en dispositivos físicos.

## Correcciones funcionales

- Descargas de imágenes: eliminado un Future que se esperaba a sí mismo y podía
  dejar una portada cargando indefinidamente. Reintentos y caché cubiertos.
- Sesiones: respuestas tardías de login/restauración no reactivan una cuenta
  después de logout; cierre local inmediato y errores de almacenamiento tratados.
- Preferencias: escrituras serializadas, protección al cambiar de cuenta y al
  editar durante sincronización. Los eventos guardados durante arranque conservan
  los que ya existían.
- Biblioteca, artículos privados y borradores: eliminación inmediata de la vista
  anterior al cambiar cuenta; actualización tras sincronizar o volver de lectura.
- Artículos propios: cursores codificados, detección de ciclos y límite de páginas.
- Búsqueda: cancelar/limpiar descarta respuestas antiguas, paginación coherente
  y eliminación de duplicados; For you reacciona a cambios de intereses.
- Actualización de pantallas: callbacks de `setState` dejan de devolver Futures
  en biblioteca, categorías, artículos, borradores, sugerencias y comunidad admin.
- Respuestas de listas inválidas no sustituyen la copia local válida.

## API desplegada

El 3 de octubre respondieron correctamente lectura de noticias, destacados,
búsqueda, eventos, negocios, rankings, detalle y comentarios de un artículo.
El preflight confirmó `/categories` y `/promotions/pricing` con 200; las rutas
protegidas consultadas sin sesión devolvieron 401. Los fallos de categorías de
los informes de septiembre no describen el estado comprobado hoy.

No se validaron escrituras autenticadas reales, publicación en redes, proveedores
IA, cobros Stripe, reproducción real de cada proveedor de vídeo ni selectores
nativos en dispositivos. Los flujos simulados cubiertos están en la suite local.

## Artefacto y requisitos externos

- Bundle: `build/macos/Build/Products/Release/The People Voice.app`.
- Paquete local: [The-People-Voice-macOS-1.0.0-local-review.zip](../build/releases/The-People-Voice-macOS-1.0.0-local-review.zip).
- iOS: instalar el componente iOS 26.5 que solicita Xcode y configurar equipo,
  certificados y perfiles del titular. No se produjo un IPA distribuible.
- Android: instalar/configurar SDK y proporcionar keystore real. No se produjo
  un AAB/APK de producción; la configuración impide firmar release con debug.
- macOS: certificado de distribución y notarización o flujo Mac App Store;
  no había identidades de firma válidas accesibles en la auditoría.
- Antes de publicar: cuenta de prueba para validación autenticada, entorno de
  pagos de prueba, y declaraciones de privacidad/distribución correspondientes.

Las instrucciones están en [PRODUCTION_READINESS.md](PRODUCTION_READINESS.md).
El backend no está incluido en este workspace; no se atribuyen a esta revisión
las cifras históricas de pruebas del servidor. No se creó commit porque el
proyecto local no contiene un repositorio Git.
