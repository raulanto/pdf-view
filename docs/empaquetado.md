# Empaquetado Arch

[Índice de documentación](README.md)

```bash
./scripts/source-package.sh
cd build/package
makepkg --force --noconfirm
# Instalación opcional:
sudo pacman -U pdf-view-0.5.0-1-x86_64.pkg.tar.zst
```

Instala `pdf-view`, tres ejecutables Rust, archivos QML, icono y entrada de escritorio con soporte PDF. No cambia la asociación predeterminada. El PKGBUILD es para uso local: el autor debe elegir una licencia antes de publicar el proyecto o enviarlo a AUR.

## Cómo se produce el paquete

1. `scripts/source-package.sh` reúne las fuentes y documentación en `build/package/`.
2. Calcula el SHA-256 del archivo fuente y genera allí el PKGBUILD a partir de `packaging/PKGBUILD`.
3. `makepkg` verifica el archivo y ejecuta preparación, compilación e instalación en su directorio de empaquetado.
4. El resultado es un `.pkg.tar.zst`; construirlo no lo instala en el sistema.

`packaging/pdf-view.in` es el lanzador instalado. `scripts/run.sh` es el lanzador del árbol de desarrollo; ambos deben apuntar a sus respectivas rutas de servicios y QML.

## Contenido esperado

- Ejecutable `pdf-view` en `usr/bin`.
- Servicios `pdf-view-backend`, `pdf-worker` y `pdf-view-theme` en `usr/lib/pdf-view` para el paquete Arch.
- Interfaz en `usr/share/pdf-view`.
- Entrada `.desktop`, icono y documentación en las rutas correspondientes de `usr/share`.
- Sin puente Qt/C++ propio, sonda de pruebas ni cachés de compilación.

Para inspeccionar el archivo sin instalarlo:

```bash
pacman -Qip build/package/pdf-view-0.5.0-1-x86_64.pkg.tar.zst
bsdtar -tf build/package/pdf-view-0.5.0-1-x86_64.pkg.tar.zst
```

Estos dos comandos se ejecutan desde la raíz del repositorio, después de regresar del directorio `build/package`.

## Versionado

Al cambiar la versión, revisa CMake, PKGBUILD, el script de archivo fuente, el paquete Cargo afectado y los ejemplos de documentación. El servicio de temas tiene una versión independiente. Regenera el paquete después del último cambio que deba distribuirse; no edites el archivo generado como sustituto de editar las fuentes.

El PKGBUILD también descarga PDFium 7881 Linux x86_64 con SHA-256 fijado. Instala `libpdfium.so` junto a `pdf-worker` y sus licencias en `/usr/share/licenses/pdf-view/pdfium`. El broker selecciona esa biblioteca por defecto; `PDF_VIEW_ENGINE=poppler` permite comparar. Para una instalación CMake, `PDFIUM_ROOT` señala el archivo extraído (por defecto `build/pdfium`). La licencia del código propio sigue pendiente de decisión del autor.
