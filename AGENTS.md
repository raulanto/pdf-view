# Guía para agentes — pdf-view

Estas instrucciones se aplican a todo el repositorio. Antes de editar un subdirectorio, revisa si contiene un `AGENTS.md` con instrucciones adicionales. Respeta las instrucciones explícitas del usuario y conserva los cambios existentes que no pertenezcan a tu tarea.

## Objetivo y alcance

`pdf-view` es un visor PDF de escritorio para Arch Linux y Omarchy, orientado a lectura local, respuesta rápida, navegación por teclado e integración visual con el escritorio. El frontend está construido enteramente en Quickshell/QML; los servicios propios están escritos en Rust.

El alcance actual incluye:

- Apertura de archivos locales mediante CLI, selector o arrastre, incluidos documentos con contraseña.
- Navegación multipágina, miniaturas e índice del documento.
- Zoom, ajuste de página/ancho y rotaciones de 90° para visualización.
- Búsqueda en el documento, resaltados, selección por palabras y entre páginas, y copia al portapapeles.
- OCR local de páginas sin texto nativo, con Tesseract y modelos instalados en el sistema.
- Tema Omarchy con recarga en vivo y paleta de respaldo.
- Caché acotada, detalle de la región visible y procesamiento PDF en aislamiento.
- Compilación reproducible a partir de dependencias fijadas y empaquetado local para Pacman.

La aplicación es de **solo lectura**: no modifica el PDF. No amplíes el alcance a edición, anotaciones persistentes, firma, sincronización, cuentas, telemetría, servicios en la nube o descarga de documentos salvo que la tarea lo pida. OCR no significa guardar una capa de texto en el archivo original. Tampoco debe describirse la aplicación como auditada o completamente segura.

## Arquitectura y mapa del repositorio

| Ubicación | Responsabilidad |
|---|---|
| `shell.qml` | Entrada de la aplicación Quickshell |
| `qml/Main.qml` | Ventana, disposición, controles, atajos y estado visible |
| `qml/FilePicker.qml` | Selector local de archivos con la paleta del visor |
| `qml/PdfPage.qml` | Presentación de páginas, interacción con texto y cliente IPC |
| `qml/Theme.qml` | Cliente del servicio de temas |
| `rust/pdf/src/main.rs` | `pdf-view-backend`: apertura, descriptores, Bubblewrap, cancelación, caché y validación de respuestas |
| `rust/pdf/src/worker.rs` | `pdf-worker`: ejecución de operaciones PDF/OCR y límites de recursos |
| `rust/pdf/src/native.rs` | Frontera FFI con PDFium, Poppler GLib, Cairo y Tesseract y gestión de sus recursos |
| `rust/pdf/src/lib.rs` | Tipos, geometría, utilidades y protocolo del worker |
| `rust/pdf/src/probe.rs` | Sonda de aislamiento para pruebas; no se instala con la aplicación |
| `rust/theme/` | `pdf-view-theme`: lectura TOML, vigilancia de archivos y publicación de paletas |
| `tests/` | Pruebas de integración del backend, temas y eventos de interacción QML |
| `smoke.qml`, `interaction.qml` | Entradas de las pruebas visuales dentro de Quickshell |
| `scripts/` | Lanzamiento desde el repositorio, pruebas visuales y preparación del paquete fuente |
| `packaging/` | PKGBUILD, lanzador instalado, entrada de escritorio e icono |
| `CMakeLists.txt` | Orquestación de Cargo, CTest e instalación |
| `README.md` | Presentación e inicio rápido |
| `docs/` | Guías de uso, arquitectura, desarrollo, seguridad, pruebas y empaquetado |

Hay dos paquetes Cargo independientes, `rust/pdf` y `rust/theme`, cada uno con su `Cargo.lock`; no presupongas un workspace Cargo en la raíz. CMake usa `LANGUAGES NONE`: no debe volver a compilar código C++ propio.

La migración a Rust no elimina las bibliotecas externas C/C++: Quickshell/Qt, PDFium, Poppler, Cairo y Tesseract siguen siendo dependencias del sistema. No añadas un puente Qt/C++, bindings `poppler-qt6`, GTK, Electron, Tauri ni un frontend web para sustituir esta arquitectura.

## Contratos de procesos e IPC

Toda comunicación entre procesos propios usa JSON por líneas sobre stdin/stdout. No introduzcas un servidor HTTP, puertos de escucha ni archivos temporales como canal de transporte de documentos, contraseñas o imágenes.

- **QML → backend:** solicitudes con `id`, `kind`, `op` y parámetros. Los canales actuales son `0` renderizado, `1` búsqueda y `2` operaciones auxiliares.
- **Backend → QML:** respuestas con `id`, `kind` y `data`. La interfaz solo aplica la respuesta correspondiente a la solicitud vigente. Preserva esta regla al cambiar de documento, página o consulta.
- **Backend → worker:** operaciones secuenciales por worker persistente, con parámetros enviados por stdin. El documento se entrega mediante un descriptor abierto y montado por Bubblewrap.
- **Worker → backend:** una línea JSON con `meta` y `pixels`; los píxeles son RGB crudos codificados en base64. El backend valida metadatos, dimensiones y longitud antes de codificar el PNG que recibe QML.
- **Servicio de temas → QML:** eventos con `palette` y `status`. Son actualizaciones espontáneas, no respuestas correlacionadas con solicitudes del visor.

Reserva stdout para el protocolo; los diagnósticos van a stderr. No registres contraseñas ni texto extraído del documento. Cambia productores, consumidores y pruebas juntos si modificas un contrato. No añadas formatos alternativos ni compatibilidad especulativa.

## Seguridad y límites que deben preservarse

1. El procesamiento nativo de PDF, renderizado y OCR está restringido a `worker.rs` y `native.rs`, dentro de Bubblewrap. El frontend y el backend principal nunca cargan Poppler, Cairo o Tesseract.
2. No realices llamadas FFI directas a bibliotecas C desde `main.rs`. Usa las interfaces Rust existentes, incluido Rustix para operaciones con descriptores. El uso de `unsafe` debe ser mínimo y explicar las condiciones que lo hacen válido, especialmente después de `fork`.
3. Conserva el descriptor del archivo regular abierto en solo lectura. No reabras por su ruta al montar el documento; un reemplazo de la ruta no debe cambiar el archivo entregado al worker.
4. Mantén la separación de red, directorio personal y sockets de sesión. Los descriptores ajenos al documento no deben llegar al worker. Un fallo de Bubblewrap debe producir un error, nunca un reintento sin aislamiento.
5. Trata como no confiables tanto el PDF como las respuestas del worker: valida tipos, tamaños, dimensiones, coordenadas, texto, índices y cantidad de resultados antes de usarlos.
6. Conserva los límites de memoria, CPU, tiempo, tamaño de entrada/salida, caché y colas. Los valores vigentes están documentados en `docs/seguridad.md` y definidos en el código. Cualquier cambio debe actualizar ambos y comprobar los casos límite afectados.
7. Respeta los permisos de copia del documento en extracción, selección y OCR. No ejecutes acciones incrustadas, JavaScript, programas o enlaces externos del PDF.
8. Las contraseñas se mantienen en memoria y se transmiten por stdin, nunca por argumentos CLI, logs, preferencias o archivos temporales.
9. Presenta nombres de archivo, títulos del índice y otros textos del documento como texto plano; no los interpretes como HTML, QML o instrucciones.
10. Los errores de entrada, OCR o procesos deben terminar en mensajes recuperables, no en `panic!` del backend principal ni resultados incompletos presentados como correctos.

No elimines estas garantías para reducir código, acelerar una prueba o resolver una incompatibilidad del entorno. El aislamiento actual no incluye seccomp ni límites globales mediante cgroups; no afirmes que esas protecciones existen.

## Interfaz, accesibilidad y Omarchy

- Conserva el estilo terminal: tipografía monoespaciada, controles compactos, bordes rectos y estados claros de carga/error.
- Usa la paleta compartida de `Theme.qml`; evita colores fijos en controles nuevos. Mantén temas claros y oscuros y conserva los colores originales del PDF.
- No modifiques la configuración del escritorio, hooks de Omarchy ni asociaciones predeterminadas para implementar una función del visor.
- Mantén navegación por teclado, foco visible, nombres accesibles y equivalentes de los controles con ratón.
- Evita que los atajos globales interfieran con campos de texto o diálogos activos.
- No bloquees el hilo de interfaz con procesamiento PDF/OCR. Conserva la agrupación de cambios de zoom y región visible, las colas acotadas y el descarte de respuestas obsoletas.
- Usa mensajes visibles en español, concretos y sin exponer detalles internos innecesarios.

## Forma de trabajar

Antes de cambiar código, lee el flujo completo afectado y sus llamadas, revisa `git status` y consulta `README.md`. Usa `rg` para localizar referencias. La guía `.agents/skills/pdf-view-dev/SKILL.md`, si está disponible, complementa estas instrucciones.

Prefiere reutilizar funciones y bibliotecas existentes, la biblioteca estándar y las capacidades nativas de Quickshell. Añade una dependencia solo si resuelve una necesidad concreta; evita abstracciones para futuras funciones. Conserva los archivos lock y no actualices dependencias ajenas a la tarea.

Formatea Rust con `cargo fmt`. Mantén el estilo QML del archivo y documenta contratos o decisiones difíciles, no operaciones obvias. Si corriges un fallo, comprueba los demás consumidores de la función compartida. Elimina código en desuso solo tras verificar sus referencias, incluidas QML, pruebas y empaquetado.

No reviertas trabajo del usuario, no limpies directorios ajenos a la tarea ni incluyas artefactos de `build/` o `target/` en los cambios de código. No edites los paquetes generados como si fueran la fuente: modifica `packaging/` o los scripts y regenera el resultado.

## Preparación y compilación

Las dependencias Arch de ejecución y construcción están en `packaging/PKGBUILD` y `docs/desarrollo.md`. Usa los modelos OCR ya instalados; `eng` es el valor inicial y `spa+eng` requiere `tesseract-data-spa`. No descargues modelos desde la interfaz sin una tarea que lo requiera.

Desde la raíz del repositorio:

```bash
# Preparación inicial o tras cambiar dependencias; requiere acceso a red si faltan en caché.
cargo fetch --locked --manifest-path rust/theme/Cargo.toml
cargo fetch --locked --manifest-path rust/pdf/Cargo.toml

cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release
cmake --build build -j 2
./scripts/run.sh "/ruta/a/documento.pdf"
```

CMake ejecuta Cargo con `--locked --offline` y usa `build/rust` como directorio de compilación compartido. Los lanzadores configuran `PDF_VIEW_BACKEND`, `PDF_VIEW_WORKER`, `PDF_VIEW_THEME_HELPER` y, cuando se abre un archivo, `PDF_VIEW_DOCUMENT`. `PDF_VIEW_THEME_FILE` permite un tema de prueba sin cambiar el escritorio.

## Validación según el cambio

| Cambio | Comprobación pertinente |
|---|---|
| Backend, worker, FFI, caché o IPC | Compilación, Clippy del paquete PDF y CTest; añade un caso de regresión cuando corresponda |
| Servicio de temas | Formato, pruebas Rust del paquete y `theme-reload`; prueba visual si cambia la integración QML |
| Interfaz o interacción | Compilación si afecta servicios y `scripts/smoke.sh`; inspecciona la captura y los errores QML |
| Paleta o selector temático | `PDF_VIEW_TEST_THEME=1 scripts/smoke.sh` |
| Lanzador, CMake o paquete | Construcción del paquete y comprobación del contenido/instalación temporal |
| Solo documentación | Verifica rutas, comandos y coherencia; no recompiles sin motivo |

Comandos de referencia:

```bash
cargo fmt --check --manifest-path rust/pdf/Cargo.toml
cargo fmt --check --manifest-path rust/theme/Cargo.toml
cargo clippy --locked --offline --manifest-path rust/pdf/Cargo.toml --target-dir build/rust --all-targets -- -D warnings
ctest --test-dir build --output-on-failure
./scripts/smoke.sh
PDF_VIEW_TEST_THEME=1 ./scripts/smoke.sh
```

CTest incluye `theme-unit`, `pdf-unit`, `theme-reload` e `integration`. La integración necesita namespaces de Bubblewrap; las pruebas de contraseñas y permisos de copia requieren `qpdf` y se omiten si falta. No presentes una prueba omitida como ejecutada.

Las pruebas visuales necesitan una sesión Wayland y módulos Qt Test disponibles; el modo de tema también usa el tema Tokyo Night de Omarchy. Se ejecutan dentro de Quickshell, que registra sus propios módulos; no presupongas que `qmltestrunner` puede cargarlos por separado. Los scripts abren ventanas temporales y guardan capturas/registros en `build/`.

Si una restricción del entorno impide una comprobación, informa cuál quedó pendiente y por qué. No desactives el sandbox para obtener un resultado exitoso. Una vez pasadas las comprobaciones pertinentes, no las repitas sin cambios o dudas concretas.

## Empaquetado y entrega

```bash
./scripts/source-package.sh
cd build/package
makepkg --force --noconfirm
```

El script genera el archivo fuente y un PKGBUILD con su SHA-256; `makepkg` produce el paquete local. Comprueba que incluya el frontend QML, los tres ejecutables de producción, el lanzador, la entrada de escritorio, el icono y la documentación. No debe incluir el antiguo puente C++, la sonda de pruebas ni cachés de compilación.

Al cambiar la versión de la aplicación, revisa `CMakeLists.txt`, `packaging/PKGBUILD`, `scripts/source-package.sh`, el paquete Cargo afectado y los ejemplos de la documentación. El servicio de temas tiene su propia versión; no la cambies automáticamente si no corresponde.

No instales el paquete en el sistema ni lo publiques por el solo hecho de construirlo. Sigue el alcance solicitado para instalación o publicación. La licencia del proyecto todavía debe ser elegida por su autor antes de distribución pública; no inventes una licencia ni prepares una publicación en AUR suponiéndola.

## Criterio de trabajo terminado

La función solicitada está implementada, las comprobaciones pertinentes pasan o sus limitaciones están indicadas, y no quedan rutas activas al código sustituido. Actualiza README, instrucciones y empaquetado cuando cambien comportamientos, contratos, dependencias o comandos. Si entregas un paquete, debe corresponder al código final.

La respuesta de entrega debe indicar brevemente qué cambió, cómo se verificó y cualquier limitación pendiente. Distingue entre código propio Rust y bibliotecas nativas externas, entre pruebas automatizadas y revisión visual, y entre un paquete construido, una instalación temporal y una instalación real en el sistema.
