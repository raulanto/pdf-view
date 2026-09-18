#!/usr/bin/env bash
# Optional renderer for local comparison. No system installation.
set -euo pipefail
project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
[[ "$(uname -m)" == x86_64 ]] || { echo 'Este archivo PDFium requiere Linux x86_64.' >&2; exit 1; }
mkdir -p "$project_dir/build/pdfium"
archive="$(mktemp)"
trap 'rm -f "$archive"' EXIT
curl --fail --location --proto '=https' --tlsv1.2 \
  'https://github.com/bblanchon/pdfium-binaries/releases/download/chromium%2F7881/pdfium-linux-x64.tgz' -o "$archive"
printf '%s  %s\n' '1470e21b8b4a3b4ad7f85684e2da11d94f3b69a86d81dee11b9b6709d927ac1d' "$archive" | sha256sum --check --status
tar -xzf "$archive" -C "$project_dir/build/pdfium"
echo "PDFium preparado en $project_dir/build/pdfium (incluye licencias)."
