#!/usr/bin/env bash
set -euo pipefail
project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
export QML_IMPORT_PATH="$project_dir/build/qml${QML_IMPORT_PATH:+:$QML_IMPORT_PATH}"
export PDF_VIEW_THEME_HELPER="$project_dir/build/rust/release/pdf-view-theme"
export QT_QUICK_CONTROLS_STYLE=Basic
export PDF_VIEW_WORKER="$project_dir/build/pdf-worker"
if [[ $# -gt 1 ]]; then echo 'Uso: scripts/run.sh [documento.pdf]' >&2; exit 2; fi
if [[ $# -eq 1 ]]; then
    export PDF_VIEW_DOCUMENT="$(python3 -c 'import pathlib,sys; print(pathlib.Path(sys.argv[1]).resolve().as_uri())' "$1")"
else
    unset PDF_VIEW_DOCUMENT
fi
exec quickshell --path "$project_dir/shell.qml"
