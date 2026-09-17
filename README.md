# PDF View — prototipo Quickshell

Visor nativo para Arch Linux / Omarchy. Ventana Quickshell con lectura multipágina, zoom, rotación, búsqueda, selección de texto y tema Omarchy con recarga en vivo mediante un servicio Rust. Poppler procesa los documentos en aislamiento. La interfaz está en QML; el componente nativo `PdfPage` entrega la imagen al scene graph de Qt Quick. No usa GTK ni un navegador.

## Compilar y abrir

Dependencias de Arch: `quickshell`, `qt6-base`, `qt6-declarative`, `poppler-qt6`, `bubblewrap`, `tesseract`, `tesseract-data-eng`; para construir: `cmake`, `ninja`, `gcc`, `pkgconf` y Rust/Cargo. El lanzador usa Bash y Python 3 para convertir rutas en URLs de archivo correctamente.

```bash
cargo fetch --locked --manifest-path rust/theme/Cargo.toml
cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release
cmake --build build -j 2
./scripts/run.sh
./scripts/run.sh "/ruta/a/documento.pdf"
```

Usar «abrir», Ctrl+O, una ruta en el lanzador o arrastrar un único archivo local a la ventana. Los documentos protegidos solicitan su contraseña; se conserva en memoria mientras está abierto el documento y se envía por stdin al motor, nunca en la línea de comandos ni en archivos de preferencias. No hace falta instalar el módulo en el sistema: el lanzador configura `QML_IMPORT_PATH` y la ubicación del proceso auxiliar.

Entorno verificado: Omarchy 4.0.4, Quickshell 0.3.1, Qt 6.11.2 y Poppler 26.08.0. La política de Bubblewrap usa `--ro-bind-fd` y `--disable-userns`; las versiones antiguas que no los soporten fallarán sin ejecutar el motor fuera del aislamiento.

## Arquitectura

- `shell.qml` y `qml/Main.qml`: ventana independiente, selector de archivos y estados de carga/error.
- `src/pdfpage.*`: tipo QML `PdfView.PdfPage`, lanzamiento asíncrono, timeout y validación de respuesta.
- `src/sandbox.h`: política de Bubblewrap compartida por aplicación y prueba de aislamiento.
- `src/worker.cpp`: análisis, renderizado de la página solicitada, extracción de palabras y búsqueda en el documento.
- `scripts/run.sh`: ejecución desde el árbol de compilación.

El proceso principal abre un archivo regular en modo de solo lectura. Pasa el descriptor a Bubblewrap, que monta exactamente ese archivo como `/document.pdf`; no vuelve a resolver la ruta original durante el montaje. El motor solo recibe el documento, `/usr` en modo de lectura, las fuentes de `/etc/fonts`, dispositivos mínimos, un `/proc` de su namespace y un `/tmp` privado. No se comparte el directorio personal, sockets de Wayland/D-Bus ni la red del host. El descriptor se reserva como fd 3 y se cierran los demás descriptores heredados desde fd 4.

## Límites del prototipo

- Archivo de entrada: hasta 256 MiB.
- Renderizado adaptado al zoom y al escalado del monitor, con vista base con lado mayor de 2000 píxeles y detalle de la región visible de hasta 2048 × 2048. El zoom manual admite 25–400%; ajustar página/ancho calcula la escala según el área disponible.
- IPC: petición JSON por stdin (máximo 16 KiB). Respuesta `PDF2`, longitud JSON little-endian de 32 bits, metadatos JSON (hasta 8 MiB) y píxeles RGBA8888 sin compresión para renderizados. Máximo aceptado de 4096 × 4096 píxeles; la textura de Qt Quick también tiene tamaño acotado. Se validan tamaños, coordenadas y límites antes de usarlos.
- Memoria virtual por proceso: 1 GiB; CPU por operación: 30 segundos; tiempo total: 20 segundos para renderizado nativo y 45 para OCR, búsqueda y operaciones auxiliares. Puede haber un renderizado, una búsqueda y una operación auxiliar simultáneos.
- Core dumps desactivados. Sin ejecución de acciones incrustadas o JavaScript desde la aplicación.
- Si el motor o el aislamiento falla, se informa al usuario; no existe una ruta alternativa sin aislamiento.

Esto es una base funcional de aislamiento, no una auditoría de seguridad completa. La política aún monta `/usr` completo en solo lectura, no incorpora filtro seccomp y los límites de recursos son del proceso motor, no de un cgroup completo. El endurecimiento adicional y las pruebas con documentos hostiles pertenecen a la fase de robustez. Las peticiones sin caché vuelven a abrir el documento dentro de un proceso aislado. La caché de respuestas tiene un presupuesto de 96 MiB, adicional a las imágenes y texturas activas. Se conservan hasta 48 miniaturas de 220 píxeles de lado mayor. A zoom alto se solicita el detalle de la región visible, agrupando cambios durante 180 ms. El índice admite 2048 entradas y 16 niveles. La extracción por rango admite hasta 100 páginas y 2 millones de caracteres.

## Verificación

```bash
ctest --test-dir build --output-on-failure
./scripts/smoke.sh
```

Las pruebas de integración generan un PDF de dos páginas y comprueban OCR de un PDF escaneado, índice, miniaturas, caché, regiones, selección entre páginas, navegación, zoom, rotación, selección con ratón en las cuatro orientaciones, portapapeles en plataforma offscreen, búsqueda insensible a mayúsculas, cancelación de peticiones, rechazo de URL remota, archivo inválido y recuperación. Con `qpdf` instalado también generan un PDF protegido y comprueban contraseñas correctas/incorrectas y restricciones de copia; esta prueba se omite si falta esa herramienta. Una sonda dentro de la misma política comprueba que `/home`, `/run/user` y `/etc/passwd` no son accesibles, que el documento no es escribible y que no hay interfaces de red externas.

La prueba `smoke.sh` requiere una sesión Wayland. Abre una ventana temporal de Quickshell, recorre páginas, amplía, rota, busca y selecciona texto, guarda `build/smoke.png` y sale. También deja el documento de ejemplo en `build/smoke.pdf` y el registro en `build/smoke.log`. Solo tiene éxito si confirma el flujo y la captura sin errores QML ni ciclos de bindings. En contenedores de desarrollo que bloquean namespaces, las pruebas de Bubblewrap deben ejecutarse en el host; no se debe desactivar el aislamiento para hacerlas pasar.

La captura de Wayland se verificó visualmente. Qt emite un aviso de registro del portal de escritorio en esta sesión, sin impedir el renderizado. El selector de archivos es ahora un diálogo QML propio que hereda la paleta.

## Fase 2: temas de Omarchy en Rust

`rust/theme` contiene `pdf-view-theme`: un proceso Rust que lee TOML con `toml`, vigila archivos y directorios con `notify` y publica una paleta JSON por línea. `qml/Theme.qml` recibe los cambios mediante `Quickshell.Io.Process`. El proceso termina con la aplicación y se reinicia si falla. `Cargo.lock` fija dependencias; CMake compila el servicio en modo offline después de `cargo fetch`.

**El servicio de temas está escrito en Rust; el puente Qt y el motor PDF de la fase 1 continúan en C++. La migración del motor PDF a Rust no forma parte de esta entrega.**

Prioridad de detección:

1. `PDF_VIEW_THEME_FILE`, si se define (ruta de prueba o personalizada).
2. `$XDG_STATE_HOME/omarchy/current/theme/colors.toml` cuando XDG_STATE_HOME es absoluto; por defecto `~/.local/state`.
3. `~/.local/state/omarchy/current/theme/colors.toml`, ruta usada por el Omarchy instalado.
4. `$XDG_CONFIG_HOME/omarchy/current/theme/colors.toml` para instalaciones anteriores; por defecto `~/.config`.

El servicio vigila los directorios padres y los destinos de enlaces simbólicos. Agrupa eventos durante 120 ms y hace una comprobación de recuperación cada 2 segundos. Conserva la última paleta válida durante un reemplazo, archivo ausente o TOML inválido. Al iniciar sin una paleta válida usa colores integrados. Exige `background`, `foreground` y `accent` en formato `#RRGGBB`; admite los colores opcionales de superficie, selección, borde y error, y modo claro/oscuro. Limita el archivo a 64 KiB. Los colores del PDF no se alteran.

El selector QML muestra carpetas y archivos PDF, permite subir de directorio y abrir un archivo. Botones, textos, fondos, foco y selección heredan la paleta. No modifica archivos de Omarchy ni requiere instalar hooks.

Pruebas adicionales:

```bash
ctest --test-dir build -R theme --output-on-failure
PDF_VIEW_TEST_THEME=1 ./scripts/smoke.sh
```

Las pruebas Rust validan TOML, colores, temas claros y entradas incompletas. La integración comprueba recuperación, reemplazo de directorio y enlaces simbólicos. La prueba visual usa `build/test-colors.toml`, cambia de oscuro a claro en la misma ventana y abre el selector temático; nunca cambia el tema del escritorio. Este modo visual toma la paleta oscura de `/usr/share/omarchy/themes/tokyo-night/colors.toml` y por tanto requiere Omarchy. Guarda la captura oscura en `build/smoke.png.dark.png` y el contenido del selector claro en `build/smoke.png`.

## Diseño estilo terminal

La interfaz QML usa tipografía monoespaciada, controles de texto, bordes rectos de un píxel, una barra superior con la ruta del documento, un panel lateral compacto y una barra de estado. El selector comparte esta apariencia. Los colores siguen la paleta activa de Omarchy, tanto clara como oscura; el PDF conserva sus colores originales. Los controles se adaptan al ancho de la ventana y muestran solo funciones disponibles.

## Lectura, búsqueda y selección

| Acción | Control |
|---|---|
| Abrir | Ctrl+O, selector, ruta CLI o arrastrar un archivo local |
| Página anterior/siguiente | PgUp / PgDn o botones ‹ / › |
| Ir a página | Número en la barra y Enter |
| Primera/última página | Ctrl+Home / Ctrl+End |
| Zoom | + / −, Ctrl++ / Ctrl+− o Ctrl+rueda |
| Ajustar página | Botón ajustar o Ctrl+0 |
| Ajustar ancho | Botón ancho |
| Girar 90° | Botón ↻ o Ctrl+R |
| Buscar | Ctrl+F; escribe o pulsa Enter |
| Siguiente/anterior coincidencia | F3 / Shift+F3 o flechas de búsqueda |
| Cerrar búsqueda | Escape o [x] |
| Seleccionar texto | Arrastrar desde una palabra con botón izquierdo |
| Seleccionar texto de la página | Ctrl+A |
| Copiar selección | Ctrl+C o botón copiar |
| Desplazar una página ampliada | Rueda, barras o arrastrar con botón central |

La búsqueda se realiza en todo el documento sin distinguir mayúsculas; resalta coincidencias y navega a su página. El límite es de 2000 resultados y se indica con `+` cuando se alcanza. Una búsqueda demasiado costosa termina con un error de tiempo, no con resultados silenciosamente incompletos. Al cambiar de consulta o documento se cancelan las peticiones anteriores.

La selección es por palabras y respeta el permiso de copia del PDF. Para seleccionar entre páginas, marca una palabra, navega y usa Shift+clic en la palabra final; también puedes usar «seleccionar rango» para extraer páginas completas. Ctrl+C copia el resultado. El orden de lectura depende de Poppler o del OCR. La rotación y el zoom son de visualización: no escriben sobre el PDF.

## OCR local

Activa OCR en el panel lateral para buscar y seleccionar texto de páginas sin texto nativo. Tesseract trabaja dentro del aislamiento, en memoria, sin subir archivos ni modificar el PDF. No sustituye texto nativo existente ni reconoce automáticamente imágenes dentro de páginas mixtas. La imagen de reconocimiento se limita a 220 dpi y 2600 píxeles de lado mayor.

El idioma inicial es `eng`. Para español instala `tesseract-data-spa`, escribe `spa+eng` en el campo de idioma y pulsa Enter. Un modelo ausente produce un error visible. La precisión depende de la calidad del escaneo; documentos largos pueden alcanzar el límite de tiempo.

## Paquete Arch

```bash
./scripts/source-package.sh
cd build/package
makepkg --force --noconfirm
# Instalación opcional del paquete generado:
sudo pacman -U pdf-view-0.4.0-1-x86_64.pkg.tar.zst
```

El paquete instala `pdf-view`, el módulo QML, los procesos auxiliares, un icono y una entrada de escritorio con soporte PDF. Después puede abrirse con `pdf-view /ruta/documento.pdf`. No cambia la asociación predeterminada de archivos. La compilación descarga las dependencias Rust fijadas por Cargo.lock; no requiere privilegios de administrador.

El PKGBUILD es para distribución local: el autor todavía debe elegir una licencia antes de publicar el proyecto o enviarlo a AUR. La migración del motor y puente C++ a Rust y el endurecimiento adicional del aislamiento siguen pendientes.

Referencias: [Quickshell FloatingWindow](https://quickshell.org/docs/v0.3.0/types/Quickshell/FloatingWindow/), [módulos QML](https://doc.qt.io/qt-6/qtqml-syntax-imports.html), [QProcess](https://doc.qt.io/qt-6/qprocess.html), [Bubblewrap](https://github.com/containers/bubblewrap).
