# PDF View — Quickshell + Rust

Visor PDF local para Arch Linux / Omarchy, con interfaz Quickshell estilo terminal y servicios Rust. Incluye navegación multipágina, zoom, rotación, búsqueda, selección y copia, miniaturas, índice, OCR local y colores de Omarchy con recarga en vivo.

La aplicación abre documentos en solo lectura. Poppler GLib, Cairo y Tesseract procesan PDF y OCR dentro de Bubblewrap; no hay código C++ propio ni un frontend web.

## Empezar

Consulta [Desarrollo](docs/desarrollo.md) para instalar las dependencias y compilar. Después, desde la raíz del repositorio:

```bash
./scripts/run.sh
./scripts/run.sh "/ruta/a/documento.pdf"
```

`run.sh` carga el QML del proyecto y los binarios de `build/rust/release`; no recompila Rust automáticamente.

## Documentación

La [documentación del proyecto](docs/README.md) contiene las guías de uso, arquitectura, desarrollo, seguridad, pruebas y empaquetado. Las instrucciones para agentes y colaboradores están en [AGENTS.md](AGENTS.md).

Versión actual: **0.5.0**. Consulta [Empaquetado Arch](docs/empaquetado.md) para generar el paquete local y [Seguridad y límites](docs/seguridad.md) para conocer las protecciones y restricciones existentes.
