# Desarrollo

[Índice de documentación](README.md)

Ejecuta los comandos desde la raíz del repositorio, salvo que se indique otra ubicación. Las reglas para agentes y colaboradores están en [AGENTS.md](../AGENTS.md).

## Dependencias y compilación

Dependencias Arch: `quickshell`, `qt6-base`, `qt6-declarative`, `poppler-glib`, `cairo`, `bubblewrap`, `tesseract`, `tesseract-data-eng`, `bash` y `python`. Para compilar: `rust`, `gcc`, `pkgconf`, `cmake` y `ninja`. `poppler-qt6` ya no es necesario.

```bash
cargo fetch --locked --manifest-path rust/theme/Cargo.toml
cargo fetch --locked --manifest-path rust/pdf/Cargo.toml
cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release
cmake --build build -j 2
./scripts/run.sh
./scripts/run.sh "/ruta/a/documento.pdf"
```

El lanzador abre Quickshell y configura las rutas de los servicios Rust. No instala módulos Qt en el sistema. CMake organiza compilación, pruebas e instalación; Cargo compila ambos paquetes con sus dependencias fijadas por `Cargo.lock`, sin red después de `cargo fetch`.

## Iteración diaria

- Un cambio QML se carga desde los archivos del proyecto al abrir el visor; no requiere compilar Rust.
- Después de editar Rust, ejecuta `cmake --build build -j 2`. `scripts/run.sh` no recompila automáticamente.
- Hay dos paquetes Cargo independientes, `rust/pdf` y `rust/theme`, sin workspace Cargo en la raíz.
- CMake instala y coordina las herramientas; Cargo compila los servicios. No se genera un puente C++.
- Conserva los `Cargo.lock`. Usa `cargo fetch --locked` para preparar dependencias y los comandos offline para el trabajo posterior.

## Variables de entorno

| Variable | Uso |
|---|---|
| `PDF_VIEW_BACKEND` | Ruta del servicio de documentos Rust |
| `PDF_VIEW_ENGINE` | `pdfium` o `poppler`; sin definir, usa PDFium si encuentra su biblioteca |
| `PDF_VIEW_PDFIUM` | Ruta explícita a `libpdfium.so`; si falta, busca junto al worker |
| `PDF_VIEW_WORKER` | Ruta del worker aislado |
| `PDF_VIEW_THEME_HELPER` | Ruta del servicio de temas |
| `PDF_VIEW_DOCUMENT` | URL `file:` que abre QML al iniciar |
| `PDF_VIEW_THEME_FILE` | Archivo TOML de paleta personalizado o de prueba |
| `PDF_VIEW_TEST_THEME` | Activa el recorrido de tema en `scripts/smoke.sh` |
| `PDF_VIEW_TEST_FIXTURE` | Destino del PDF generado por la integración para la prueba visual |
| `PDF_VIEW_SCREENSHOT` | Destino de la captura de las pruebas QML |

Los lanzadores preparan las rutas de producción; normalmente no necesitas definirlas a mano. No incluyas contraseñas en estas variables ni en argumentos CLI.

## Criterios para cambios

Mantén el frontend en Quickshell, la lógica de servicios en Rust y las bibliotecas PDF/OCR dentro del worker. Usa Rustix para operaciones de descriptores en el backend. Prefiere funciones existentes y dependencias ya disponibles; no añadas abstracciones para funciones hipotéticas.

Conserva el diseño monoespaciado, la paleta compartida, el foco visible, los nombres accesibles y los atajos. Los textos de documentos se muestran como texto plano. Un cambio IPC debe actualizar sus productores, consumidores y pruebas.

Consulta [Pruebas y diagnóstico](pruebas.md) antes de entregar cambios y [Empaquetado](empaquetado.md) para generar una distribución local.

Para preparar el motor de renderizado recomendado antes de configurar CMake, ejecuta `./scripts/fetch-pdfium.sh` (requiere `curl` y red). Descarga PDFium 7881 Linux x86_64, verifica SHA-256 y conserva sus licencias en `build/pdfium`. `pdfium-render` 0.9.4 está fijado en Cargo; no trae la biblioteca nativa. Sin ella se puede compilar y utilizar Poppler. Véase [Rendimiento](rendimiento.md).
