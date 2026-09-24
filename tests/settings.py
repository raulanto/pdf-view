"""Preferences use an isolated location; never change the desktop configuration."""
import json, os, subprocess, sys, tempfile
from pathlib import Path
with tempfile.TemporaryDirectory() as directory:
    path=Path(directory)/'settings.json'
    env=dict(os.environ,PDF_VIEW_SETTINGS_FILE=str(path))
    def call(op,settings=None):
        p=subprocess.run([sys.argv[1],'--settings'],input=json.dumps(dict(id=1,op=op,settings=settings))+'\n',text=True,capture_output=True,env=env,check=True)
        return json.loads(p.stdout)['data']
    settings=call('load')['settings']
    settings['keys']['open']='alt+o'; settings['scrollStep']=180
    assert call('save',settings)['settings']['keys']['open']=='Alt+O'
    assert call('load')['settings']['scrollStep']==180
    original=path.read_bytes()
    settings['keys']['open']='Ctrl+F'
    assert 'error' in call('save',settings)
    assert path.read_bytes()==original
    path.write_text('{broken')
    assert 'error' in call('load')
    path.unlink(); path.symlink_to('/dev/zero')
    assert 'error' in call('load')
print('Settings: persistence, canonical shortcuts, duplicates, damaged files and symlinks checked')
