# PDF View — Quickshell + Rust

Visor PDF local para Arch Linux / Omarchy, con interfaz Quickshell estilo terminal y servicios Rust. Incluye navegación multipágina, zoom, rotación, búsqueda, selección y copia, miniaturas, índice, OCR local y colores de Omarchy con recarga en vivo.

La aplicación permite leer PDFs y guardar notas y subrayados dentro del archivo abierto. PDFium renderiza las páginas; Poppler GLib, Cairo y Tesseract conservan texto, búsqueda y OCR. Estos motores trabajan dentro de Bubblewrap; no hay código C++ propio ni un frontend web.

## Empezar

Consulta [Desarrollo](docs/desarrollo.md) para instalar las dependencias y compilar. Después, desde la raíz del repositorio:

```bash
./scripts/run.sh
./scripts/run.sh "/ruta/a/documento.pdf"
```

`run.sh` carga el QML del proyecto y los binarios de `build/rust/release`; no recompila Rust automáticamente.

PDFium se incluye en el paquete Arch. En desarrollo, `./scripts/fetch-pdfium.sh` prepara la biblioteca verificada y `./scripts/run.sh` la selecciona automáticamente. La imagen inicial aparece antes de extraer texto u OCR; consulta [Rendimiento y motores](docs/rendimiento.md).

Para anotar: selecciona palabras con clic izquierdo, elige un color en la cinta rápida y pulsa **subrayar**, o abre **notas** y pulsa **guardar nota**. Cada acción se guarda sobre el PDF abierto; las notas se consultan al reabrirlo desde **notas**. Consulta [Uso](docs/uso.md).

## Documentación

La [documentación del proyecto](docs/README.md) contiene las guías de uso, arquitectura, desarrollo, seguridad, pruebas y empaquetado. Las instrucciones para agentes y colaboradores están en [AGENTS.md](AGENTS.md).

Versión actual: **0.5.0**. Consulta [Empaquetado Arch](docs/empaquetado.md) para generar el paquete local y [Seguridad y límites](docs/seguridad.md) para conocer las protecciones y restricciones existentes.

Para quitar una marca, selecciona una palabra subrayada y pulsa **quitar subrayado** en la cinta; se elimina la anotación completa y se guarda el PDF.
