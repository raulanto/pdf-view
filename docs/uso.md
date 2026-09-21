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

La selección respeta el permiso de copia del documento. El orden de lectura depende de Poppler o Tesseract. La búsqueda es insensible a mayúsculas, resalta coincidencias y navega a su página. Zoom, rotación, selección y OCR no modifican el original; las acciones de anotar sí guardan el PDF. Los índices pueden contener títulos sin destino; la aplicación no ejecuta enlaces externos, acciones ni JavaScript.

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

## Notas y subrayados persistentes

- **Subrayar:** selecciona palabras de la página actual y pulsa `subrayar`. La acción guarda inmediatamente el subrayado dentro del PDF abierto.
- **Notas:** pulsa `notas`, escribe el texto y pulsa `guardar nota`. Si hay selección, la nota se sitúa junto a ella; si no, se coloca en la parte superior de la página.
- **Reabrir:** los subrayados aparecen en la página y el botón `notas` muestra las notas guardadas de la página actual. Se usan anotaciones PDF estándar, no archivos auxiliares exclusivos del visor.

Durante la escritura se muestra `GUARDANDO`; al finalizar aparece `Anotación guardada en el PDF.`. El visor recarga el documento automáticamente. Si falla una nota, el diálogo conserva el texto para corregir el problema y reintentar. No hay un paso adicional de guardar ni borradores persistentes. La edición y eliminación de anotaciones existentes todavía no están implementadas.

Se requiere PDFium, permiso de escritura en el archivo y en su carpeta. Esta versión no anota documentos cifrados ni firmados, para no alterar su protección o invalidar firmas. Límites: 128 palabras por subrayado, 4000 caracteres por nota (también sujeto al límite IPC), salida de 256 MiB; se muestran hasta 256 anotaciones de la página. La selección entre páginas sigue sirviendo para copiar, pero los subrayados se crean página por página.

### Cinta rápida y colores

Haz clic izquierdo sobre una palabra, o arrastra para seleccionar varias: al soltar aparece una cinta junto a la selección. Elige **ámbar, rojo, verde, azul, violeta o negro**, y pulsa **subrayar**, **+ nota** o **copiar**. Elegir un color no modifica el PDF; subrayar o guardar la nota sí lo hace. El color permanece en el PDF al reabrirlo y se conserva como elección durante la sesión del visor.

La cinta también se abre con **anotar ▾** o **Ctrl+Shift+A** sobre una selección. Usa Tab para recorrer sus controles y Espacio para activarlos. Esc, un clic fuera o desplazar el documento la cierran. La paleta del diálogo de notas es la misma. En documentos sin permiso para anotar solo queda disponible copiar.

### Quitar subrayados

Selecciona con clic izquierdo texto subrayado y pulsa **quitar subrayado**. Se elimina del PDF cada subrayado que contiene alguna palabra seleccionada, aunque esa marca abarque más palabras. Las notas y otros subrayados quedan intactos. Si no hay marcas guardadas en la selección, se muestra un mensaje sin modificar el archivo.
