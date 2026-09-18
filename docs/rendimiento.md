# Rendimiento y motores

[Índice](README.md)

El renderizador recomendado está integrado con [`pdfium-render` 0.9.4](https://docs.rs/pdfium-render/0.9.4/pdfium_render/) y [PDFium 7881](https://github.com/bblanchon/pdfium-binaries/releases/tag/chromium%2F7881). El binding es Rust; PDFium es una biblioteca C++ externa. Poppler sigue proporcionando texto, búsqueda, permisos e índice, y permite comparar el renderizado sin perder funciones.

## Ejecutar

```bash
./scripts/fetch-pdfium.sh
cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release
cmake --build build -j 2
./scripts/run.sh /ruta/documento.pdf
# Comparar con Poppler:
PDF_VIEW_ENGINE=poppler ./scripts/run.sh /ruta/documento.pdf
```

El paquete Arch incluye la biblioteca y sus licencias. En desarrollo, el script de descarga verifica el SHA-256 del archivo y `run.sh` encuentra la biblioteca en `build/pdfium`. No se descarga nada al abrir un PDF. Solicitar explícitamente PDFium sin una biblioteca compatible muestra un error; no omite el aislamiento. Sin selección explícita y sin biblioteca se usa Poppler.

## Comportamiento

- Primera imagen a 54 dpi; después se refina con la resolución de lectura.
- Texto, índice y OCR posteriores a la imagen, en un canal independiente del renderizado.
- Workers persistentes y cancelación sin esperar a que finalice una lectura bloqueada.
- Caché acotada de imágenes recientes y miniaturas vecinas; el zoom conserva la imagen anterior durante el refinamiento.
- Solo se crean objetos QML de las páginas visibles y próximas. No se crea un objeto por cada página del archivo completo.

No hay una pantalla de carga que bloquee la lectura. Esto no implica latencia cero: documentos grandes, dañados, escaneados o complejos aún necesitan procesamiento. Las páginas que aún no tienen una imagen pueden verse vacías brevemente. El OCR no bloquea el renderizado, pero comparte el canal auxiliar con miniaturas y selección de rangos.

## Medición reproducible

```bash
python3 scripts/benchmark-pdf.py /ruta/documento.pdf \
  --pdfium build/pdfium/lib/libpdfium.so --runs 5
```

Medianas locales del 17 de septiembre de 2026, con `build/smoke.pdf` (dos páginas de texto), cinco procesos nuevos por motor:

| Operación | Poppler | PDFium |
|---|---:|---:|
| Primera imagen, 54 dpi | 341,49 ms | 24,57 ms |
| Refinamiento, 144 dpi, worker reutilizado | 21,81 ms | 21,33 ms |
| Repetición desde caché | 0,31 ms | 0,30 ms |

Se mide desde enviar la petición hasta recibir y decodificar el JSON de respuesta, incluidos apertura, sandbox, renderizado y transporte PNG. No incluye inicio de Quickshell ni presentación por la GPU. Son aperturas nuevas de proceso, no una caché fría del sistema operativo. Este PDF pequeño no representa documentos grandes o escaneados; repite el comando con documentos reales antes de generalizar la mejora.
