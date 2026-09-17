#!/usr/bin/env bash
set -euo pipefail
project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
export PDF_VIEW_TEST_FIXTURE="$project_dir/build/smoke.pdf"
ctest --test-dir "$project_dir/build" --output-on-failure
export QML_IMPORT_PATH="$project_dir/build/qml${QML_IMPORT_PATH:+:$QML_IMPORT_PATH}"
export PDF_VIEW_THEME_HELPER="$project_dir/build/rust/release/pdf-view-theme"
export QT_QUICK_CONTROLS_STYLE=Basic
export PDF_VIEW_WORKER="$project_dir/build/pdf-worker"
export PDF_VIEW_DOCUMENT="$(python3 -c 'import pathlib,os; print(pathlib.Path(os.environ["PDF_VIEW_TEST_FIXTURE"]).as_uri())')"
export PDF_VIEW_SCREENSHOT="$project_dir/build/smoke.png"
if [[ "${PDF_VIEW_TEST_THEME:-0}" == 1 ]]; then
    export PDF_VIEW_THEME_FILE="$project_dir/build/test-colors.toml"
    cp /usr/share/omarchy/themes/tokyo-night/colors.toml "$PDF_VIEW_THEME_FILE"
fi
export QT_QPA_PLATFORM="${QT_QPA_PLATFORM:-wayland}"
timeout 25s quickshell --path "$project_dir/smoke.qml" --no-color 2>&1 | tee "$project_dir/build/smoke.log"
grep -q "SMOKE PASSED" "$project_dir/build/smoke.log"
