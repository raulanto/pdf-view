# Uso del visor

[Índice de documentación](README.md)

| Acción | Control |
|---|---|
| Abrir | Ctrl+O, selector, ruta CLI o arrastrar un PDF local |
| Página anterior/siguiente | PgUp / PgDn o botones ‹ / › |
| Ir a página | Campo de página y Enter, miniatura o entrada del índice |
| Primera/última página | Ctrl+Home / Ctrl+End |
| Zoom | Botones + / −, Ctrl++ / Ctrl+− o Ctrl+rueda |
| Ajustar página/ancho | Botones ajustar/ancho; Ctrl+0 ajusta página |
| Girar 90° | Botón ↻ o Ctrl+R |
| Buscar en todo el documento | Ctrl+F y Enter; también busca tras una pausa al escribir |
| Siguiente/anterior resultado | F3 / Shift+F3 o flechas de búsqueda |
| Cerrar búsqueda | Escape o [x] |
| Seleccionar texto | Arrastrar desde una palabra con botón izquierdo |
| Seleccionar toda la página | Ctrl+A |
| Seleccionar entre páginas | Marca una palabra, navega y usa Shift+clic en la palabra final |
| Extraer páginas completas | «seleccionar rango» en el panel lateral |
| Copiar selección | Ctrl+C o botón ^C |
| Desplazar página ampliada | Rueda, barras o arrastrar con botón central |

La selección respeta el permiso de copia del documento. El orden de lectura depende de Poppler o Tesseract. La búsqueda es insensible a mayúsculas, resalta coincidencias y navega a su página. El PDF se abre en solo lectura: zoom, rotación, selección y OCR no modifican el original. Los índices pueden contener títulos sin destino; la aplicación no ejecuta enlaces externos, acciones ni JavaScript.

## OCR local

Activa OCR para buscar y seleccionar texto de páginas sin texto nativo. Tesseract trabaja dentro del aislamiento, en memoria y sin subir archivos. No sustituye texto nativo existente ni reconoce imágenes dentro de páginas mixtas.

El idioma inicial es `eng`. Para español instala `tesseract-data-spa`, escribe `spa+eng` en el campo de idioma y pulsa Enter. Los modelos ausentes producen un error visible. La precisión depende del escaneo; un documento muy largo puede agotar el tiempo permitido.

## Tema Omarchy

El servicio Rust lee y vigila el archivo `colors.toml` en este orden:

1. `PDF_VIEW_THEME_FILE`, si se define.
2. `$XDG_STATE_HOME/omarchy/current/theme/colors.toml` cuando la variable es absoluta; por defecto `~/.local/state`.
3. `~/.local/state/omarchy/current/theme/colors.toml`.
4. `$XDG_CONFIG_HOME/omarchy/current/theme/colors.toml` para instalaciones anteriores; por defecto `~/.config`.

Admite reemplazo de directorios y enlaces simbólicos. Conserva la última paleta válida si el archivo desaparece o contiene errores; al iniciar sin tema usa una paleta integrada. Exige `background`, `foreground` y `accent` en `#RRGGBB`. Limita el archivo a 64 KiB, agrupa eventos durante 120 ms y comprueba recuperación cada 2 segundos. No modifica archivos ni hooks de Omarchy. El documento conserva sus colores originales.
