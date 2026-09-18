# Seguridad y límites

[Índice de documentación](README.md)

Bubblewrap recibe el descriptor de un archivo regular abierto en solo lectura y lo monta como `/document.pdf`. Reemplazar su ruta no cambia el documento abierto. El worker solo recibe ese archivo, `/usr` en lectura, fuentes de `/etc/fonts`, dispositivos mínimos, un `/proc` de su namespace y un `/tmp` privado. No recibe el directorio personal, sockets de sesión ni red del host. Los demás descriptores se cierran al ejecutar Bubblewrap. Si el aislamiento falla, la operación falla: no se reintenta sin él.

| Recurso | Límite |
|---|---|
| Archivo PDF | 256 MiB |
| Memoria virtual / CPU por worker | 1 GiB / 30 segundos; core dumps desactivados |
| Tiempo por petición | 20 s render nativo; 45 s OCR, búsqueda y operaciones auxiliares |
| Concurrencia | Un renderizado, una búsqueda y una operación auxiliar |
| Petición / metadatos worker | 16 KiB / 8 MiB |
| Imagen base / detalle visible | Lado mayor 2000 px / hasta 2048 × 2048 px |
| Zoom manual | 25–400%; ajuste automático según ventana |
| Caché de respuestas | Presupuesto de 96 MiB, adicional a imágenes y objetos activos |
| Miniaturas | Hasta 48 en la interfaz, lado mayor 220 px; cola de 24 |
| Texto por página | 50 000 palabras, 4096 caracteres por palabra |
| Búsqueda | 2000 coincidencias; `+` indica truncamiento |
| Extracción de rango | 100 páginas, 2 Mi caracteres |
| Índice | 2048 entradas, 16 niveles |
| OCR | Hasta 220 dpi y 2600 px de lado mayor |

Las peticiones sin caché vuelven a abrir el PDF en un worker nuevo. La caché se vacía al abrir otro documento, cambiar de contraseña o detectar cambios en tamaño/fecha del archivo; las vistas ya mostradas requieren reabrir el documento para reflejar cambios externos. El detalle visible se agrupa durante 180 ms. Las contraseñas solo se conservan en memoria y viajan por stdin.

Este aislamiento no equivale a una auditoría de seguridad: `/usr` completo se monta en lectura, no hay filtro seccomp, las bibliotecas nativas usan FFI y los límites no son un cgroup global. Las pruebas con corpus hostiles y el endurecimiento adicional siguen pendientes.

## Fronteras de confianza

El documento y la salida del worker son entradas no confiables. El backend valida metadatos, dimensiones, coordenadas, cantidades de texto y tamaños antes de entregar datos a QML. El PNG se genera desde los píxeles RGBA validados, no desde un archivo de imagen comprimido suministrado por el parser PDF.

Las llamadas FFI a Poppler GLib, Cairo y Tesseract permanecen en el worker. Rust reduce riesgos en el código propio, pero no convierte esas bibliotecas en código Rust ni elimina los riesgos de procesar archivos hostiles.

La aplicación respeta permisos de copia y no ejecuta acciones, enlaces externos ni JavaScript incrustado. No usa servicios remotos, telemetría ni persistencia de contraseñas. La selección solo se envía al portapapeles al solicitar la copia.

## Verificación y cambios de seguridad

La sonda Rust comprueba la inaccesibilidad del directorio personal y de la sesión, la lectura sin escritura del PDF, la ausencia de red externa y que un descriptor privado heredado no llegue al worker. Las pruebas también cubren URLs remotas, archivos inválidos, FIFO, permisos y límites del protocolo.

Estas pruebas no sustituyen una auditoría ni un corpus exhaustivo de documentos maliciosos. Al cambiar el sandbox o un límite, actualiza el código, esta documentación y el caso de prueba correspondiente. Nunca desactives Bubblewrap como alternativa para hacer pasar las pruebas.
