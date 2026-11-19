# Revisión funcional — 29 de septiembre de 2026

## Resultado

40 pruebas automatizadas aprobadas, análisis estático sin errores (31 avisos de estilo informativos) y una
prueba adicional de lectura contra producción aprobada con el cliente HTTP de
Flutter. No se generó una compilación macOS/iOS/Android. No se publicaron
artículos/comentarios, enviaron mensajes ni ejecutaron pagos reales.

Esto valida las rutas probadas, no certifica todas las funciones en dispositivos
reales ni las integraciones autenticadas de producción.

## Correcciones de esta revisión

- Comentarios: reproducido y corregido `TextEditingController was used after
  being disposed` al cerrar el diálogo de respuesta. El diálogo ahora es dueño
  de su controlador y solo cierra tras confirmar publicación.
- Comentarios: conserva el texto mientras el diálogo permanezca abierto ante
  errores; reintenta publicación con el mismo ID de borrador. Si la creación
  queda sin confirmar, bloquea su repetición automática. El contenido escrito
  se escapa antes de enviarlo como HTML.
- Categorías: producción ignoraba `category` en `/posts` (Business y una
  categoría inexistente devolvían los mismos IDs y total que el feed general).
  Ahora la app usa búsqueda y verifica la categoría real de los resultados;
  se agregaron controles de paginación. Puede haber páginas sin coincidencias
  porque la búsqueda del servidor también encuentra palabras en el contenido.
- Diálogos administrativos y recuperación de borradores: los controladores se
  liberan después de finalizar la transición, en vez de depender de un retraso
  fijo o quedar sin liberar.

## Cobertura y límites

| Función | Verificación | Límite |
| --- | --- | --- |
| Navegación y redimensionado | Prueba de diseño con promociones cargadas y varios tamaños | No se ejecutó una nueva sesión gráfica en Xcode |
| Lectura, búsquedas, destacados | API real con HTTP 200 y cliente Flutter | No se verificó cada artículo individual |
| Editor | Entrada de teclado, formato, HTML/Delta y reapertura del borrador | Sin nueva prueba física del teclado en macOS |
| Imágenes y videos | Validación de enlaces, serialización y subidas simuladas con reintentos | No se verificó reproducción real en cada proveedor ni el selector nativo |
| Offline y favoritos | Persistencia SQLite, aislamiento de cuentas, errores y sincronización simulada | No se desconectó físicamente un dispositivo |
| Comentarios y respuestas | Lectura real, escritura simulada, padre correcto y reintento de publicación | Sin comentario publicado en producción |
| Community | API real y pruebas de pestañas, detalles, formularios y navegación | Eventos y negocios devuelven listas vacías; noticias relacionadas sí disponibles |
| Contacto | Preparación de sugerencias y pruebas existentes con respuestas simuladas | No se enviaron mensajes reales |
| Categorías | Prueba de filtrado exacto y paginación; comprobación de endpoint real | `/api/v1/categories` devuelve 404; catálogo lateral depende de datos locales |
| Login, roles y administración | Revisión del cliente y pruebas simuladas de permisos/operaciones | Falta sesión de prueba para comprobación de extremo a extremo |
| IA y publicación en redes | Pruebas de flujo/contrato con respuestas simuladas | No se invocaron proveedores reales |
| Estadísticas | `/rankings` responde en producción y pruebas de gráficos | Estadísticas administrativas requieren cuenta autorizada |
| Notificaciones | Pruebas de sincronización y estado leído/offline | No se confirmó entrega real de una notificación |
| Stripe | Revisión de conexión en código | `featuredCheckout` existe, pero el botón promocional abre contacto; pago directo pendiente |
| Productos | `/products` responde HTTP 200 | No se hizo una compra |

## Producción: pendientes confirmados

1. Publicar el catálogo y filtro de categorías en el backend. El código del
   servidor ya no está en este workspace; aquí solo está `people_voice_mobile`.
2. Cargar/aprobar entradas reales para el directorio de eventos y negocios.
3. Conectar el pago promocional a la selección de un artículo y validar Stripe
   en entorno de pruebas antes de confirmar la integración completa.
4. Validar con una cuenta de prueba login/logout, publicación, administración,
   comentarios, IA, contacto y notificaciones. No se inspeccionaron credenciales
   ni se reutilizaron sesiones guardadas del usuario para esta auditoría.

## Comandos de verificación

```sh
./.tooling/flutter/bin/flutter analyze
./.tooling/flutter/bin/flutter test
./.tooling/flutter/bin/flutter test tool/smoke_public_test.dart
```

La última comprobación usa únicamente GET contra la API configurada. La ruta
`/mobile/capabilities` devolvió 401 sin sesión, que es el comportamiento esperado.
