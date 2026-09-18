# Documentación de PDF View

PDF View es un visor PDF local para Arch Linux y Omarchy. La interfaz está hecha en Quickshell/QML y sus servicios en Rust. Permite leer, buscar, seleccionar y copiar texto, navegar por miniaturas e índice y usar OCR local, sin modificar el documento original.

## Guías

| Documento | Contenido |
|---|---|
| [Uso](uso.md) | Controles, atajos, OCR y colores de Omarchy |
| [Rendimiento y motores](rendimiento.md) | PDFium, carga progresiva y comparación reproducible |
| [Arquitectura](arquitectura.md) | Componentes, flujo de documentos, IPC y caché |
| [Desarrollo](desarrollo.md) | Dependencias, compilación, iteración y variables de entorno |
| [Seguridad y límites](seguridad.md) | Aislamiento, validación, presupuestos y limitaciones conocidas |
| [Pruebas y diagnóstico](pruebas.md) | Suites, pruebas visuales y problemas habituales |
| [Empaquetado Arch](empaquetado.md) | PKGBUILD, contenido instalado y versionado |

Para empezar a usar el visor, consulta Uso. Para compilarlo o modificarlo, empieza por Desarrollo y las reglas de [AGENTS.md](../AGENTS.md).

## Alcance

El visor trabaja con archivos locales y es de solo lectura. Zoom, rotación y OCR no guardan cambios en el PDF. No incluye edición, firmas, anotaciones persistentes, cuentas ni sincronización remota. PDFium, Poppler, Cairo, Tesseract y Quickshell/Qt siguen siendo bibliotecas externas; el backend propio está escrito en Rust.

Esta documentación describe la versión 0.5.0. Actualiza la guía del área afectada cuando cambien contratos, comandos o límites; evita duplicar esos detalles en varias guías.

[Volver al README del proyecto](../README.md)
