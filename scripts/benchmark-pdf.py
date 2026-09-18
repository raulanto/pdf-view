#!/usr/bin/env python3
"""Compare broker latency, including sandbox startup and PNG transport (not display time)."""
import argparse
import json
import os
from pathlib import Path
import statistics
import subprocess
import time

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('pdf', type=Path)
parser.add_argument('--pdfium', type=Path, required=True)
parser.add_argument('--runs', type=int, default=5)
args = parser.parse_args()
root = Path(__file__).resolve().parent.parent
if not 1 <= args.runs <= 100:
    parser.error('--runs must be between 1 and 100')
for engine in ('poppler', 'pdfium'):
    timings = {name: [] for name in ('first_preview_ms', 'refinement_ms', 'cache_ms')}
    for _ in range(args.runs):
        env = dict(os.environ, PDF_VIEW_ENGINE=engine, PDF_VIEW_PDFIUM=str(args.pdfium.resolve()))
        with subprocess.Popen([str(root/'build/rust/release/pdf-view-backend')],
                              stdin=subprocess.PIPE, stdout=subprocess.PIPE, env=env) as process:
            try:
                for index, name in enumerate(timings):
                    request = dict(id=index+1, kind=0, op='open' if index==0 else 'render',
                                   page=1, rotation=0, dpi=54 if index==0 else 144,
                                   text=False, outline=False, url=args.pdf.resolve().as_uri())
                    started = time.perf_counter()
                    process.stdin.write(json.dumps(request).encode()+b'\n'); process.stdin.flush()
                    result = json.loads(process.stdout.readline())['data']
                    if 'image' not in result:
                        raise RuntimeError(result.get('error', 'No image received'))
                    timings[name].append((time.perf_counter()-started)*1000)
            finally:
                process.stdin.close()
                process.wait(timeout=5)
    print(json.dumps(dict(engine=engine, runs=args.runs,
                          median={name: round(statistics.median(values), 2) for name, values in timings.items()})))
