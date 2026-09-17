# PDF View — prototipo Quickshell

Visor nativo para Arch Linux / Omarchy. Fases 1 y 2: ventana Quickshell, primera página renderizada por Poppler en aislamiento y tema Omarchy con recarga en vivo mediante un servicio Rust. La interfaz está en QML; el componente nativo `PdfPage` entrega la imagen al scene graph de Qt Quick. No usa GTK ni un navegador.

## Compilar y abrir

Dependencias de Arch: `quickshell`, `qt6-base`, `qt6-declarative`, `poppler-qt6`, `bubblewrap`; para construir: `cmake`, `ninja`, `gcc`, `pkgconf` y Rust/Cargo. El lanzador usa Bash y Python 3 para convertir rutas en URLs de archivo correctamente.

```bash
cargo fetch --locked --manifest-path rust/theme/Cargo.toml
cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release
cmake --build build -j 2
./scripts/run.sh
./scripts/run.sh "/ruta/a/documento.pdf"
```

Usar «Abrir PDF» o Ctrl+O. El prototipo muestra únicamente la primera página, ajustada al área disponible, y el número total de páginas. Los PDF protegidos por contraseña todavía no se admiten. No hace falta instalar el módulo en el sistema: el lanzador configura `QML_IMPORT_PATH` y la ubicación del proceso auxiliar.

Entorno verificado: Omarchy 4.0.4, Quickshell 0.3.1, Qt 6.11.2 y Poppler 26.08.0. La política de Bubblewrap usa `--ro-bind-fd` y `--disable-userns`; las versiones antiguas que no los soporten fallarán sin ejecutar el motor fuera del aislamiento.

## Arquitectura

- `shell.qml` y `qml/Main.qml`: ventana independiente, selector de archivos y estados de carga/error.
- `src/pdfpage.*`: tipo QML `PdfView.PdfPage`, lanzamiento asíncrono, timeout y validación de respuesta.
- `src/sandbox.h`: política de Bubblewrap compartida por aplicación y prueba de aislamiento.
- `src/worker.cpp`: análisis del PDF y renderizado exclusivo de la primera página.
- `scripts/run.sh`: ejecución desde el árbol de compilación.

El proceso principal abre un archivo regular en modo de solo lectura. Pasa el descriptor a Bubblewrap, que monta exactamente ese archivo como `/document.pdf`; no vuelve a resolver la ruta original durante el montaje. El motor solo recibe el documento, `/usr` en modo de lectura, las fuentes de `/etc/fonts`, dispositivos mínimos, un `/proc` de su namespace y un `/tmp` privado. No se comparte el directorio personal, sockets de Wayland/D-Bus ni la red del host. El descriptor se reserva como fd 3 y se cierran los demás descriptores heredados desde fd 4.

## Límites del prototipo

- Archivo de entrada: hasta 256 MiB.
- Renderizado: hasta 144 dpi, lado mayor objetivo de 2000 píxeles.
- IPC: cabecera `PDF1` y cuatro enteros little-endian de 32 bits (ancho, alto, páginas, bytes), seguidos por RGBA8888 sin compresión; máximo aceptado de 2048 × 2048 píxeles.
- Memoria virtual del motor: 1 GiB; CPU: 10 segundos; tiempo total: 15 segundos.
- Core dumps desactivados. Sin ejecución de acciones incrustadas o JavaScript desde la aplicación.
- Si el motor o el aislamiento falla, se informa al usuario; no existe una ruta alternativa sin aislamiento.

Esto es una base funcional de aislamiento, no una auditoría de seguridad completa. La política aún monta `/usr` completo en solo lectura, no incorpora filtro seccomp y los límites de recursos son del proceso motor, no de un cgroup completo. El endurecimiento adicional y las pruebas con documentos hostiles pertenecen a la fase de robustez. El raster fijo y `QQuickPaintedItem` sirven para validar la integración; el renderizado por regiones, caché y zoom se incorporarán después.

## Verificación

```bash
ctest --test-dir build --output-on-failure
./scripts/smoke.sh
```

Las pruebas de integración generan un PDF de dos páginas y comprueban renderizado, rechazo de URL remota, archivo inválido y recuperación. Una sonda dentro de la misma política comprueba que `/home`, `/run/user` y `/etc/passwd` no son accesibles, que el documento no es escribible y que no hay interfaces de red externas.

La prueba `smoke.sh` requiere una sesión Wayland. Abre una ventana temporal de Quickshell, carga el módulo y el PDF, guarda `build/smoke.png` y sale. También deja el documento de ejemplo en `build/smoke.pdf` y el registro en `build/smoke.log`. Solo tiene éxito si confirma el renderizado y la captura. En contenedores de desarrollo que bloquean namespaces, las pruebas de Bubblewrap deben ejecutarse en el host; no se debe desactivar el aislamiento para hacerlas pasar.

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

## Siguiente fase

Navegación multipágina, zoom, rotación y apertura ampliada. Búsqueda, selección de texto, miniaturas y empaquetado Pacman continúan pendientes.

Referencias: [Quickshell FloatingWindow](https://quickshell.org/docs/v0.3.0/types/Quickshell/FloatingWindow/), [módulos QML](https://doc.qt.io/qt-6/qtqml-syntax-imports.html), [QProcess](https://doc.qt.io/qt-6/qprocess.html), [Bubblewrap](https://github.com/containers/bubblewrap).
