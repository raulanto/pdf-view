"""Integration tests against the running Rust service; no desktop files are modified."""
import json
import os
from pathlib import Path
import select
import subprocess
import sys
import tempfile
import time


def wait_for(process, predicate):
    deadline = time.monotonic() + 6
    while time.monotonic() < deadline:
        if select.select([process.stdout], [], [], 0.2)[0]:
            line = process.stdout.readline()
            assert line, "theme service exited"
            state = json.loads(line)
            if predicate(state):
                return state
    raise AssertionError("theme update timed out")


def palette(bg):
    return f"background='{bg}'\nforeground='#112233'\naccent='#abcdef'\n"


with tempfile.TemporaryDirectory() as tmp:
    root = Path(tmp)
    current = root / 'current'
    current.mkdir()
    theme = current / 'theme'
    target = theme / 'colors.toml'
    env = dict(os.environ, PDF_VIEW_THEME_FILE=str(target))
    process = subprocess.Popen([sys.argv[1]], env=env, stdout=subprocess.PIPE, text=True, bufsize=1)
    try:
        wait_for(process, lambda s: s['status'] == 'fallback')
        theme.mkdir()
        target.write_text(palette('#ffffff'))
        wait_for(process, lambda s: s['palette']['background'] == '#ffffff')
        target.write_text("background='incomplete'")
        state = wait_for(process, lambda s: s['status'] == 'retained')
        assert state['palette']['background'] == '#ffffff'
        target.write_text(palette('#123456'))
        wait_for(process, lambda s: s['palette']['background'] == '#123456')
        theme.rename(current / 'old')
        theme.mkdir()
        target.write_text(palette('#654321'))
        wait_for(process, lambda s: s['palette']['background'] == '#654321')
        target.unlink()
        state = wait_for(process, lambda s: s['status'] == 'retained')
        assert state['palette']['background'] == '#654321'
        theme.rmdir()
        theme.symlink_to(current / 'old', target_is_directory=True)
        wait_for(process, lambda s: s['palette']['background'] == '#123456')
        (current / 'old/colors.toml').write_text(palette('#abcdef'))
        wait_for(process, lambda s: s['palette']['background'] == '#abcdef')
    finally:
        process.terminate()
        process.wait(timeout=5)
print('Theme reload: fallback, invalid file, recovery, directory replacement and symlink passed')
