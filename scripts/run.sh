#!/usr/bin/env bash
set -euo pipefail
project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
export PDF_VIEW_THEME_HELPER="$project_dir/build/rust/release/pdf-view-theme"
export QT_QUICK_CONTROLS_STYLE=Basic
export PDF_VIEW_BACKEND="$project_dir/build/rust/release/pdf-view-backend"
if [[ -z "${PDF_VIEW_PDFIUM:-}" && -f "$project_dir/build/pdfium/lib/libpdfium.so" ]]; then
    export PDF_VIEW_PDFIUM="$project_dir/build/pdfium/lib/libpdfium.so"
fi
export PDF_VIEW_WORKER="$project_dir/build/rust/release/pdf-worker"
if [[ $# -gt 1 ]]; then echo 'Uso: scripts/run.sh [documento.pdf]' >&2; exit 2; fi
if [[ $# -eq 1 ]]; then
    export PDF_VIEW_DOCUMENT="$(python3 -c 'import pathlib,sys; print(pathlib.Path(sys.argv[1]).resolve().as_uri())' "$1")"
else
    unset PDF_VIEW_DOCUMENT
fi
exec quickshell --path "$project_dir/shell.qml"
