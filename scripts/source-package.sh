#!/usr/bin/env bash
set -euo pipefail
project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
python3 - "$project_dir" <<'PY'
from pathlib import Path
import hashlib, sys, tarfile
root=Path(sys.argv[1])
output=root/'build/package'
output.mkdir(parents=True,exist_ok=True)
archive=output/'pdf-view-0.4.0.tar.gz'
with tarfile.open(archive,'w:gz') as tar:
    for name in ['CMakeLists.txt','README.md','shell.qml','qml','src','rust','packaging','tests','scripts']:
        def include(info):
            return None if any(p in ('target','__pycache__') for p in Path(info.name).parts) else info
        tar.add(root/name,arcname='pdf-view-0.4.0/'+name,filter=include)
digest=hashlib.sha256(archive.read_bytes()).hexdigest()
(output/'PKGBUILD').write_text((root/'packaging/PKGBUILD').read_text().replace('SOURCE_SHA256',digest))
print(output)
PY
