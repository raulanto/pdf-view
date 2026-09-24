#!/usr/bin/env bash
set -euo pipefail
project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
settings_test_dir="$(mktemp -d "$project_dir/build/settings-test-XXXXXX")"
trap 'rm -rf -- "$settings_test_dir"' EXIT
export PDF_VIEW_SETTINGS_FILE="$settings_test_dir/settings.json"
export PDF_VIEW_TEST_FIXTURE="$project_dir/build/smoke.pdf"
ctest --test-dir "$project_dir/build" --output-on-failure
export PDF_VIEW_THEME_HELPER="$project_dir/build/rust/release/pdf-view-theme"
export QT_QUICK_CONTROLS_STYLE=Basic
export PDF_VIEW_BACKEND="$project_dir/build/rust/release/pdf-view-backend"
export PDF_VIEW_WORKER="$project_dir/build/rust/release/pdf-worker"
export PDF_VIEW_DOCUMENT="$(python3 -c 'import pathlib,os; print(pathlib.Path(os.environ["PDF_VIEW_TEST_FIXTURE"]).as_uri())')"
export PDF_VIEW_SCREENSHOT="$project_dir/build/smoke.png"
if [[ "${PDF_VIEW_TEST_THEME:-0}" == 1 ]]; then
    export PDF_VIEW_THEME_FILE="$project_dir/build/test-colors.toml"
    cp /usr/share/omarchy/themes/tokyo-night/colors.toml "$PDF_VIEW_THEME_FILE"
fi
export QT_QPA_PLATFORM="${QT_QPA_PLATFORM:-wayland}"
timeout 45s quickshell --path "$project_dir/smoke.qml" --no-color 2>&1 | tee "$project_dir/build/smoke.log"
grep -q "SMOKE PASSED" "$project_dir/build/smoke.log"

if grep -Eq "Binding loop|ReferenceError|TypeError|is not a type|Cannot assign" "$project_dir/build/smoke.log"; then exit 1; fi

if [[ "${PDF_VIEW_TEST_THEME:-0}" != 1 ]]; then
    timeout 60s quickshell --path "$project_dir/interaction.qml" --no-color 2>&1 | tee "$project_dir/build/interaction.log"
    grep -q "INTERACTION PASSED" "$project_dir/build/interaction.log"
    if grep -Eq "INTERACTION FAILED|Binding loop|ReferenceError|TypeError|is not a type|Cannot assign" "$project_dir/build/interaction.log"; then exit 1; fi
fi
