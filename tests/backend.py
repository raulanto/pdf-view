"""Exercise the real Rust broker + sandbox, with dependency-free PDF fixtures."""
import base64
import ctypes as C
import json
import os
from pathlib import Path
import select
import shutil
import subprocess
import sys
import tempfile
import time
import zlib


def write_pdf(path, scan=False):
    objects = [b'<< /Type /Catalog /Pages 2 0 R /Outlines 8 0 R >>',
               b'<< /Type /Pages /Kids [3 0 R 5 0 R] /Count 2 >>',
               b'<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 7 0 R >> /XObject << /Im1 10 0 R >> >> /Contents 4 0 R >>',
               b'', b'<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 7 0 R >> >> /Contents 6 0 R >>', b'',
               b'<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
               b'<< /Type /Outlines /First 9 0 R /Last 9 0 R /Count 1 >>',
               b'<< /Title (Chapter Two) /Parent 8 0 R /Dest [5 0 R /Fit] >>']
    def stream(data, extra=b''):
        return b'<< /Length '+str(len(data)).encode()+b' '+extra+b' >>\nstream\n'+data+b'\nendstream'
    objects[3] = stream(b'q 450 0 0 100 60 620 cm /Im1 Do Q' if scan else b'BT /F1 24 Tf 60 700 Td (PDF View - Quickshell) Tj ET')
    objects[5] = stream(b'BT /F1 24 Tf 60 700 Td (Second page) Tj ET')
    pixels, width, height = scanned_pixels() if scan else (b'\xff\xff\xff', 1, 1)
    objects.append(stream(zlib.compress(pixels), f'/Type /XObject /Subtype /Image /Width {width} /Height {height} /ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /FlateDecode'.encode()))
    data = b'%PDF-1.4\n'
    offsets = [0]
    for i, obj in enumerate(objects, 1):
        offsets.append(len(data)); data += f'{i} 0 obj\n'.encode()+obj+b'\nendobj\n'
    start = len(data)
    data += f'xref\n0 {len(offsets)}\n0000000000 65535 f \n'.encode()
    data += b''.join(f'{o:010d} 00000 n \n'.encode() for o in offsets[1:])
    data += f'trailer\n<< /Size {len(offsets)} /Root 1 0 R >>\nstartxref\n{start}\n%%EOF\n'.encode()
    path.write_bytes(data)


def scanned_pixels():
    cairo = C.CDLL('libcairo.so.2')
    def function(name, result, *args):
        f = getattr(cairo, name); f.restype=result; f.argtypes=args; return f
    p, i, d = C.c_void_p, C.c_int, C.c_double
    surface = function('cairo_image_surface_create', p, i, i, i)(0, 900, 200)
    cr = function('cairo_create', p, p)(surface)
    color = function('cairo_set_source_rgb', None, p, d, d, d)
    color(cr, 1, 1, 1); function('cairo_paint', None, p)(cr); color(cr, 0, 0, 0)
    function('cairo_select_font_face', None, p, C.c_char_p, i, i)(cr, b'sans', 0, 0)
    function('cairo_set_font_size', None, p, d)(cr, 52)
    function('cairo_move_to', None, p, d, d)(cr, 35, 110)
    function('cairo_show_text', None, p, C.c_char_p)(cr, b'SCANNED DOCUMENT')
    function('cairo_surface_flush', None, p)(surface)
    data = function('cairo_image_surface_get_data', p, p)(surface)
    stride = function('cairo_image_surface_get_stride', i, p)(surface)
    raw = C.string_at(data, stride*200)
    rgb = bytearray()
    for y in range(200):
        for x in range(900):
            value = int.from_bytes(raw[y*stride+x*4:y*stride+x*4+4], sys.byteorder)
            rgb.extend(((value>>16)&255, (value>>8)&255, value&255))
    function('cairo_destroy', None, p)(cr); function('cairo_surface_destroy', None, p)(surface)
    return bytes(rgb), 900, 200


class Broker:
    def __init__(self, worker=None, pass_fds=()):
        env = dict(os.environ)
        env.pop('PDF_VIEW_WORKER', None)
        if worker: env['PDF_VIEW_WORKER'] = str(worker)
        self.process = subprocess.Popen([sys.argv[1]], stdin=subprocess.PIPE, stdout=subprocess.PIPE, env=env, pass_fds=pass_fds)
        self.serial = 0
    def send(self, op, kind=0, **fields):
        self.serial += 1
        request = dict(op=op, kind=kind, id=self.serial, page=1, rotation=0, dpi=144)
        request.update(fields)
        self.process.stdin.write(json.dumps(request).encode()+b'\n'); self.process.stdin.flush()
        return self.serial
    def receive(self, identifier, timeout=50):
        deadline = time.monotonic()+timeout
        while time.monotonic()<deadline:
            assert self.process.poll() is None, 'broker exited'
            if select.select([self.process.stdout], [], [], 0.2)[0]:
                result=json.loads(self.process.stdout.readline())
                if result['id']==identifier: return result['data']
        raise AssertionError('broker timeout')
    def call(self, op, **fields): return self.receive(self.send(op, **fields))
    def close(self):
        self.process.stdin.close(); self.process.wait(timeout=5)
        assert self.process.returncode==0


def image(meta):
    assert 'error' not in meta, meta
    raw=base64.b64decode(meta['image'].split(',', 1)[1])
    assert raw[:8]==b'\x89PNG\r\n\x1a\n'
    assert int.from_bytes(raw[16:20], 'big')==meta['width']
    assert int.from_bytes(raw[20:24], 'big')==meta['height']


def underline_pixels(meta, rect, rgb):
    """Require a colored horizontal stroke under the word, not just PDF metadata."""
    cairo = C.CDLL('libcairo.so.2')
    def function(name, result, *args):
        f=getattr(cairo,name); f.restype=result; f.argtypes=args; return f
    p,i=C.c_void_p,C.c_int
    with tempfile.NamedTemporaryFile(suffix='.png') as png:
        png.write(base64.b64decode(meta['image'].split(',',1)[1])); png.flush()
        surface=function('cairo_image_surface_create_from_png',p,C.c_char_p)(os.fsencode(png.name))
    try:
        assert function('cairo_surface_status',i,p)(surface)==0
        stride=function('cairo_image_surface_get_stride',i,p)(surface)
        data=function('cairo_image_surface_get_data',p,p)(surface)
        raw=C.string_at(data,stride*meta['height'])
        scale=meta['width']/meta['pageWidth']
        x,y,w,h=rect
        left,right=round(x*scale),round((x+w)*scale)
        top,bottom=round((y+h*0.85)*scale),min(meta['height'],round((y+h)*scale)+1)
        coverage=0
        for row in range(top,bottom):
            matches=0
            for col in range(left,right):
                offset=row*stride+col*4
                pixel=int.from_bytes(raw[offset:offset+4],sys.byteorder)
                actual=((pixel>>16)&255,(pixel>>8)&255,pixel&255)
                matches+=all(abs(a-b)<=12 for a,b in zip(actual,rgb))
            coverage=max(coverage,matches)
        assert coverage>=(right-left)*0.8,('missing colored underline',rgb,coverage,right-left)
    finally:
        function('cairo_surface_destroy',None,p)(surface)


with tempfile.TemporaryDirectory() as directory:
    root=Path(directory); pdf=root/'sample # á space.pdf'; write_pdf(pdf)
    output=os.environ.get('PDF_VIEW_TEST_FIXTURE')
    if output: shutil.copyfile(pdf, output)
    broker=Broker()
    try:
        broker.process.stdin.write(b'[]\nnull\n'); broker.process.stdin.flush()
        assert 'error' in broker.call('open', url='https://example.com/test.pdf')
        fifo=root/'pipe.pdf'; os.mkfifo(fifo)
        assert 'error' in broker.call('open',url=fifo.as_uri())
        bad=root/'invalid.pdf'; bad.write_text('not a PDF')
        assert 'error' in broker.call('open', url=bad.as_uri())
        first=broker.call('open', url=pdf.as_uri()); image(first)
        assert first['pages']==2 and first['canCopy']
        assert first['outline']==[dict(title='Chapter Two', page=2, depth=0)]
        assert 'Quickshell' in ' '.join(w['text'] for w in first['words'])
        quick=broker.call('render', dpi=54, text=False, outline=False, ocr=True, language='missingmodel')
        image(quick); assert quick['words']==[] and 'outline' not in quick
        text_page=broker.call('text',kind=2,outline=True)
        assert 'image' not in text_page and text_page['words']==first['words']
        assert text_page['outline']==first['outline']
        word=next(w for w in first['words'] if w['text']=='Quickshell')
        for rotation in range(4):
            page=broker.call('render', page=2, rotation=rotation, dpi=500); image(page)
            assert page['rotation']==rotation
            assert (page['width']>page['height'])==(rotation%2==1)
        matches=broker.call('search',kind=1,query='quickshell')['matches']
        assert len(matches)==1 and matches[0]['page']==1
        # Search highlights and text selection must share top-left coordinates.
        a,b=matches[0]['rect'],word['rect']
        assert abs(a[1]-b[1])<10, (a,b)
        thumbnail=broker.call('thumbnail',kind=2,page=2,dpi=72); image(thumbnail)
        assert max(thumbnail['width'],thumbnail['height'])<=220
        region=broker.call('region',kind=2,dpi=288,rotation=1,region=[0.1,0.1,0.2,0.2]); image(region)
        text=broker.call('extract',kind=2,first=1,last=2)['text']
        assert 'Quickshell' in text and 'Second page' in text
        assert broker.call('extract',kind=2,first=1,last=1,firstWord=3,lastWord=3)['text']=='Quickshell'
        assert 'error' in broker.call('extract',kind=2,first=1,last=102)
        assert 'error' in broker.call('render',language='../eng')
        # Repeated renders return the same validated response.
        cached=broker.call('render',page=1)
        assert broker.call('render',page=1)==cached
        # A pathname replacement cannot switch the already-open document.
        old=root/'original.pdf'; pdf.rename(old); pdf.write_text('replacement')
        assert broker.call('render',page=2)['pages']==2
        broker.send('search',kind=1,query='missing')
        broker.send('cancel',kind=1)
        assert broker.call('open',url=old.as_uri())['pages']==2
        scan=root/'scan.pdf'; write_pdf(scan,True)
        assert broker.call('open',url=scan.as_uri())['words']==[]
        scanned=broker.call('render',ocr=True,language='eng'); image(scanned)
        assert 'SCANNED' in ' '.join(w['text'] for w in scanned['words'])
        assert len(broker.call('search',kind=1,query='scanned document',ocr=True)['matches'])==1
        assert 'SCANNED' in broker.call('extract',kind=2,first=1,last=1,ocr=True)['text']
        assert 'error' in broker.call('render',ocr=True,language='missingmodel')
        if shutil.which('qpdf'):
            encrypted=root/'protected.pdf'
            subprocess.run(['qpdf','--encrypt','secret','owner','256','--',str(old),str(encrypted)],check=True)
            assert broker.call('open',url=encrypted.as_uri())['locked']
            assert broker.call('unlock',password='wrong')['locked']
            image(broker.call('unlock',password='secret'))
            assert broker.call('unlock',password='wrong')['locked']
            restricted=root/'restricted.pdf'
            subprocess.run(['qpdf','--encrypt','secret','owner','256','--extract=n','--',str(old),str(restricted)],check=True)
            assert broker.call('open',url=restricted.as_uri())['locked']
            denied=broker.call('unlock',password='secret'); assert not denied['canCopy'] and denied['words']==[]
            assert 'error' in broker.call('extract',kind=2,first=1,last=1)
        else: print('SKIP: qpdf password/copy permission checks')
    finally: broker.close()
    if os.environ.get('PDF_VIEW_ENGINE')!='poppler' and (os.environ.get('PDF_VIEW_PDFIUM') or os.environ.get('PDF_VIEW_ENGINE')=='pdfium'):
        editable=root/'annotations.pdf'; write_pdf(editable)
        editor=Broker()
        original=editable.read_bytes()
        try:
            image(editor.call('open',url=editable.as_uri()))
            metadata=editor.call('text',kind=2)
            assert metadata['canAnnotate'] and metadata['annotations']==[]
            rect=metadata['words'][0]['rect']
            for invalid_color in ['red','#12fffff','#xxxxxx',12]:
                assert 'error' in editor.call('save',kind=2,annotation='underline',rects=[rect],note='',color=invalid_color)
                assert editable.read_bytes()==original
            rejected=editor.call('save',kind=2,annotation='underline',rects=[[-10,0,10,10]],note='')
            assert 'error' in rejected and editable.read_bytes()==original,rejected
            saved=editor.call('save',kind=2,annotation='underline',rects=[rect],note='',color='#397ed0')
            assert saved.get('saved'),saved
        finally: editor.close()
        editor=Broker()
        try:
            image(editor.call('open',url=editable.as_uri()))
            metadata=editor.call('text',kind=2)
            assert [a['kind'] for a in metadata['annotations']]==['underline'],metadata
            assert metadata['annotations'][0]['color']=='#397ed0',metadata
            underline_pixels(editor.call('render'),rect,(57,126,208))
            image(editor.call('thumbnail',kind=2,page=1))
            reread=editor.call('text',kind=2)
            assert reread['annotations']==metadata['annotations'],reread
            saved=editor.call('save',kind=2,annotation='note',rects=[[24,24,20,20]],note='Nota española\nPersistencia al reabrir')
            assert saved.get('saved'),saved
            image(editor.call('open',url=editable.as_uri()))
            metadata=editor.call('text',kind=2)
            assert any(a['text']=='Nota española\nPersistencia al reabrir' for a in metadata['annotations']),metadata
            assert any(a['kind']=='underline' for a in metadata['annotations'])
            other_rect=metadata['words'][-1]['rect']
            assert editor.call('save',kind=2,annotation='underline',rects=[other_rect],note='',color='#dc4c64').get('saved')
            editor.call('open',url=editable.as_uri())
            assert editor.call('save',kind=2,annotation='remove_underline',rects=[rect],note='').get('saved')
            editor.call('open',url=editable.as_uri())
            remaining=editor.call('text',kind=2)['annotations']
            assert [a['kind'] for a in remaining]==['note','underline'],remaining
            assert remaining[1]['color']=='#dc4c64'
            before=editable.read_bytes()
            assert 'error' in editor.call('save',kind=2,annotation='remove_underline',rects=[rect],note='')
            assert editable.read_bytes()==before
            before=editable.read_bytes()
            editable.chmod(0o444)
            assert 'error' in editor.call('save',kind=2,annotation='note',rects=[[24,24,20,20]],note='Denied')
            assert editable.read_bytes()==before
            editable.chmod(0o644)
            image(editor.call('open',url=editable.as_uri()))
            with editable.open('ab') as modified: modified.write(b'\n% external modification\n')
            before=editable.read_bytes()
            assert 'error' in editor.call('save',kind=2,annotation='note',rects=[[24,24,20,20]],note='Changed in place')
            assert editable.read_bytes()==before
            image(editor.call('open',url=editable.as_uri()))
            replacement=root/'changed.pdf'; write_pdf(replacement); replacement.replace(editable)
            before=editable.read_bytes()
            assert 'error' in editor.call('save',kind=2,annotation='note',rects=[[24,24,20,20]],note='Stale')
            assert editable.read_bytes()==before
            if shutil.which('qpdf'):
                editor.call('open',url=encrypted.as_uri()); editor.call('unlock',password='secret')
                protected=encrypted.read_bytes()
                assert 'error' in editor.call('save',kind=2,annotation='note',rects=[[24,24,20,20]],note='Protected')
                assert encrypted.read_bytes()==protected
            assert not list(root.glob('.pdf-view-*.tmp'))
        finally: editor.close()
        for color in ['#e69600','#dc4c64','#2a9968','#397ed0','#9561c9','#242424']:
            colored=root/('ink-'+color[1:]+'.pdf'); write_pdf(colored)
            editor=Broker()
            try:
                clean=editor.call('open',url=colored.as_uri())
                words=editor.call('text',kind=2)['words']
                assert editor.call('save',kind=2,annotation='underline',rects=[w['rect'] for w in words],color=color,note='').get('saved')
                rendered=editor.call('open',url=colored.as_uri())
                for word in words:
                    underline_pixels(rendered,word['rect'],tuple(bytes.fromhex(color[1:])))
                assert editor.call('save',kind=2,annotation='remove_underline',rects=[words[0]['rect']],note='').get('saved')
                erased=editor.call('open',url=colored.as_uri())
                assert erased['image']==clean['image'], 'underline still visible after removal'
                assert editor.call('text',kind=2)['annotations']==[]
            finally: editor.close()
        print('Annotations persisted: underline, Unicode notes, reopen; invalid edits, protected/read-only/changed files preserved')
    worker=root/'worker'
    shutil.copyfile(Path(sys.argv[1]).with_name('pdf-worker'),worker);worker.chmod(0o700)
    cached_broker=Broker(worker)
    try:
        image(cached_broker.call('open',url=old.as_uri()))
        cached=cached_broker.call('render',page=1)
        worker.rename(root/'disabled-worker')
        assert cached_broker.call('render',page=1)==cached
        image(cached_broker.call('render',page=2))  # live worker retains its document
        assert 'error' in cached_broker.call('open',url=old.as_uri())
    finally: cached_broker.close()
    hanging=root/'hanging-worker'
    hanging.write_text('#!/usr/bin/python3\nimport sys,time\nsys.stdin.readline()\ntime.sleep(60)\n')
    hanging.chmod(0o700)
    stalled=Broker(hanging)
    stalled.send('open',url=old.as_uri())
    time.sleep(0.15)
    started=time.monotonic()
    stalled.send('cancel')
    assert 'error' in stalled.call('open',url='https://example.com/rejected')
    stalled.close()
    assert time.monotonic()-started<2, 'cancellation blocked behind worker output'
    private=root/'private-descriptor';private.write_text('must not reach the worker')
    with private.open('rb') as secret:
        probe=Broker(Path(sys.argv[1]).with_name('sandbox-probe'),pass_fds=(secret.fileno(),))
        try: assert probe.call('open',url=old.as_uri())['error']=='sandbox verified'
        finally: probe.close()
print('Rust integration passed: rendering, rotation, search geometry, outline, OCR, ranges, passwords, copy permissions, cancellation, descriptor isolation and sandbox')
