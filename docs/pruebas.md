# Pruebas y diagnóstico

[Índice de documentación](README.md)

Compila primero siguiendo [Desarrollo](desarrollo.md). Ejecuta los comandos desde la raíz del repositorio.

```bash
ctest --test-dir build --output-on-failure
./scripts/smoke.sh
PDF_VIEW_TEST_THEME=1 ./scripts/smoke.sh
cargo clippy --locked --offline --manifest-path rust/pdf/Cargo.toml --target-dir build/rust --all-targets -- -D warnings
```

Las pruebas Rust validan protocolo, geometría y respuestas inválidas. `tests/backend.py` genera documentos sin dependencias Python adicionales y prueba renderizado, rotaciones, coincidencia entre coordenadas de búsqueda y selección, índice, miniaturas, regiones, rangos, OCR, modelos ausentes, caché y reutilización del worker aunque su ejecutable se renombre, cancelación de un worker bloqueado, imagen sin OCR, texto diferido, URLs remotas, archivos inválidos y FIFO. Si está instalado `qpdf`, también comprueba contraseñas y permisos de copia. `sandbox-probe`, escrito en Rust, verifica la misma política de aislamiento que el worker.

`scripts/smoke.sh` requiere una sesión Wayland y abre ventanas temporales que se cierran solas. Comprueba el flujo del visor y la selección con eventos de ratón de Qt Test en cuatro orientaciones, arrastre, portapapeles y Shift+clic entre páginas. Guarda captura y registros en `build/`. La prueba de temas usa un archivo temporal y nunca cambia el escritorio. En entornos que bloquean namespaces deben ejecutarse las pruebas en el host; no se debe desactivar Bubblewrap.

## Comprobaciones de Rust

```bash
cargo fmt --check --manifest-path rust/pdf/Cargo.toml
cargo fmt --check --manifest-path rust/theme/Cargo.toml
cargo clippy --locked --offline --manifest-path rust/theme/Cargo.toml --target-dir build/rust --all-targets -- -D warnings
```

| Suite / recorrido | Qué verifica |
|---|---|
| `theme-unit` | Parseo y validación de paletas TOML |
| `pdf-unit` | Protocolo, geometría y rechazo de respuestas inválidas |
| `theme-reload` | Recuperación, reemplazo de directorio y enlaces simbólicos |
| `integration` | Backend y worker reales dentro de Bubblewrap |
| `smoke.qml` | Apertura, navegación, zoom, rotación, búsqueda, miniaturas, regiones y rangos |
| `interaction.qml` | Ratón en cuatro orientaciones, arrastre, copia y Shift+clic |

Las pruebas visuales se ejecutan dentro de Quickshell, que registra sus módulos. `qmltestrunner` independiente no los carga necesariamente. El modo de temas requiere el archivo Tokyo Night de Omarchy en la ruta usada por el script.

## Diagnóstico básico

| Síntoma | Comprobación |
|---|---|
| Se ve una versión anterior después de editar Rust | Recompila con `cmake --build build -j 2` y vuelve a abrir `scripts/run.sh` |
| Falta un binario del servicio | Revisa la compilación y las rutas que exporta el lanzador |
| Cargo offline no encuentra una dependencia | Ejecuta el `cargo fetch --locked` del paquete afectado con acceso a red |
| Error de aislamiento | Comprueba Bubblewrap y la disponibilidad de namespaces; no ejecutes el worker sin aislamiento como solución |
| OCR no reconoce o falta el modelo | Comprueba `eng` / `spa+eng`, el paquete de idioma y la calidad del escaneo |
| Cambiar el tema no actualiza el visor | Revisa `PDF_VIEW_THEME_FILE`, las rutas descritas en Uso y la validez del TOML |
| Búsqueda o extracción agota el tiempo | Reduce el rango o comprueba si el documento necesita OCR; no asumas resultados completos |
| Falla un recorrido visual | Revisa `build/smoke.log`, `build/interaction.log` y las capturas disponibles |

Informa las pruebas omitidas o bloqueadas por el entorno. Para cambios solo de documentación basta validar enlaces, rutas, comandos y coherencia; no es necesario ejecutar la aplicación.

Para repetir las pruebas con PDFium: `PDF_VIEW_ENGINE=pdfium PDF_VIEW_PDFIUM="$PWD/build/pdfium/lib/libpdfium.so" ./scripts/smoke.sh`. La misma suite verifica ambos motores; los tiempos de [Rendimiento](rendimiento.md) no son pruebas de aceptación para cualquier documento.

Las pruebas visuales verifican también interpolación del scroll con rueda, precarga a resolución de lectura, navegación repetida sin renderizado en primer plano, conservación de los delegados visibles y descarte de imágenes tardías después de cambiar a una página en caché.

Con PDFium, `integration` guarda subrayados y notas Unicode sobre PDFs temporales, vuelve a abrirlos en otro broker y verifica su persistencia. Comprueba también rechazo de coordenadas inválidas, archivos sin permiso de escritura, archivos sustituidos y PDFs cifrados, preservando los bytes originales y limpiando archivos de preparación. La prueba visual crea una nota desde el diálogo; la interacción comprueba subrayado tras rotación y reapertura. Ninguna prueba modifica documentos personales.

La cinta rápida se prueba con eventos reales de clic izquierdo: apertura al seleccionar, elección de azul, subrayado y lectura del color guardado. La integración verifica persistencia RGB y rechazo de colores malformados sin modificar el original.

La regresión de subrayados comprueba los píxeles renderizados de los seis colores después de guardar y reabrir: exige una línea continua bajo cada palabra. Validar únicamente el campo RGB no detectaba el orden incorrecto de QuadPoints.

La eliminación se comprueba mediante clic real en la cinta y reapertura. Para los seis colores, la imagen tras borrar debe coincidir con la página original sin subrayados. Se verifica también que borrar conserve notas y subrayados fuera de la selección, y que una selección sin marcas no modifique el archivo.

`settings` verifica persistencia en un archivo temporal, normalización de atajos, duplicados, JSON dañado y rechazo de enlaces. La interacción abre el menú, intenta un atajo duplicado, corrige y guarda mediante clic, vuelve a abrir y restaura los valores de prueba. El desmarcado parcial comprueba que el resto de palabras conserva sus píxeles de color tras reabrir.
