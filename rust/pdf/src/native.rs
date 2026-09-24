//! The only native FFI boundary, linked into the sandboxed worker, never the broker.
use libc::{c_char, c_int, c_uint, c_void};
use pdf_view_backend::{Rect, Result, Word};
use std::{
    ffi::{CStr, CString},
    ptr,
};
type P = *mut c_void;
#[repr(C)]
struct Error {
    domain: c_uint,
    code: c_int,
    message: *mut c_char,
}
#[repr(C)]
#[derive(Clone, Copy)]
struct Rectangle {
    x1: f64,
    y1: f64,
    x2: f64,
    y2: f64,
}
#[repr(C)]
struct List {
    data: P,
    next: *mut List,
    prev: *mut List,
}
#[repr(C)]
struct AnnotMapping {
    area: Rectangle,
    annot: P,
}
#[repr(C)]
struct Color {
    red: u16,
    green: u16,
    blue: u16,
}
#[repr(C)]
struct Action {
    kind: c_int,
    title: *mut c_char,
    dest: *mut Dest,
}
#[repr(C)]
struct Dest {
    kind: c_int,
    page: c_int,
    left: f64,
    bottom: f64,
    right: f64,
    top: f64,
    zoom: f64,
    name: *mut c_char,
    flags: c_uint,
}
#[link(name = "poppler-glib")]
extern "C" {
    fn poppler_document_new_from_file(
        uri: *const c_char,
        password: *const c_char,
        error: *mut *mut Error,
    ) -> P;
    fn poppler_document_get_n_pages(doc: P) -> c_int;
    fn poppler_document_get_permissions(doc: P) -> c_uint;
    fn poppler_document_get_page(doc: P, index: c_int) -> P;
    fn poppler_document_find_dest(doc: P, name: *const c_char) -> *mut Dest;
    fn poppler_dest_free(dest: *mut Dest);
    fn poppler_page_get_size(page: P, w: *mut f64, h: *mut f64);
    fn poppler_page_get_text(page: P) -> *mut c_char;
    fn poppler_page_get_text_layout(
        page: P,
        rects: *mut *mut Rectangle,
        count: *mut c_uint,
    ) -> c_int;
    fn poppler_page_find_text(page: P, text: *const c_char) -> *mut List;
    fn poppler_rectangle_free(rect: P);
    fn poppler_page_render(page: P, cr: P);
    fn poppler_page_get_annot_mapping(page: P) -> *mut List;
    fn poppler_page_free_annot_mapping(list: P);
    fn poppler_annot_get_annot_type(annot: P) -> c_int;
    fn poppler_annot_get_contents(annot: P) -> *mut c_char;
    fn poppler_annot_get_color(annot: P) -> *mut Color;
    fn poppler_color_free(color: P);
    fn poppler_annot_get_rectangle(annot: P, rect: *mut Rectangle);
    fn poppler_index_iter_new(doc: P) -> P;
    fn poppler_index_iter_get_child(iter: P) -> P;
    fn poppler_index_iter_next(iter: P) -> c_int;
    fn poppler_index_iter_get_action(iter: P) -> *mut Action;
    fn poppler_index_iter_free(iter: P);
    fn poppler_action_free(action: *mut Action);
}
#[link(name = "gobject-2.0")]
extern "C" {
    fn g_object_unref(object: P);
}
#[link(name = "glib-2.0")]
extern "C" {
    fn g_free(p: P);
    fn g_error_free(p: *mut Error);
    fn g_list_free_full(p: *mut List, f: Option<unsafe extern "C" fn(P)>);
}
#[link(name = "cairo")]
extern "C" {
    fn cairo_image_surface_create(format: c_int, w: c_int, h: c_int) -> P;
    fn cairo_surface_destroy(surface: P);
    fn cairo_surface_status(surface: P) -> c_int;
    fn cairo_surface_flush(surface: P);
    fn cairo_image_surface_get_data(surface: P) -> *mut u8;
    fn cairo_image_surface_get_stride(surface: P) -> c_int;
    fn cairo_create(surface: P) -> P;
    fn cairo_destroy(cr: P);
    fn cairo_status(cr: P) -> c_int;
    fn cairo_set_source_rgb(cr: P, r: f64, g: f64, b: f64);
    fn cairo_paint(cr: P);
    fn cairo_scale(cr: P, x: f64, y: f64);
    fn cairo_translate(cr: P, x: f64, y: f64);
    fn cairo_rotate(cr: P, angle: f64);
}
#[link(name = "tesseract")]
extern "C" {
    fn TessBaseAPICreate() -> P;
    fn TessBaseAPIDelete(p: P);
    fn TessBaseAPIInit3(p: P, path: *const c_char, lang: *const c_char) -> c_int;
    fn TessBaseAPISetImage(p: P, data: *const u8, w: c_int, h: c_int, bpp: c_int, stride: c_int);
    fn TessBaseAPISetSourceResolution(p: P, ppi: c_int);
    fn TessBaseAPIRecognize(p: P, monitor: P) -> c_int;
    fn TessBaseAPIGetIterator(p: P) -> P;
    fn TessResultIteratorDelete(p: P);
    fn TessResultIteratorNext(p: P, level: c_int) -> c_int;
    fn TessResultIteratorGetUTF8Text(p: P, level: c_int) -> *mut c_char;
    fn TessResultIteratorGetPageIterator(p: P) -> P;
    fn TessPageIteratorBoundingBox(
        p: P,
        level: c_int,
        x1: *mut c_int,
        y1: *mut c_int,
        x2: *mut c_int,
        y2: *mut c_int,
    ) -> c_int;
    fn TessDeleteText(p: *mut c_char);
}
// Every owning native pointer has a destructor, including early error returns.
struct Owned(P, unsafe extern "C" fn(P));
impl Drop for Owned {
    fn drop(&mut self) {
        if !self.0.is_null() {
            unsafe {
                (self.1)(self.0);
            }
        }
    }
}
pub struct Document(Owned);
pub struct Page(Owned);
pub struct Raster {
    pub width: usize,
    pub height: usize,
    pub pixels: Vec<u8>,
}
unsafe fn string(p: *const c_char) -> String {
    if p.is_null() {
        String::new()
    } else {
        CStr::from_ptr(p).to_string_lossy().into_owned()
    }
}
fn cstring(s: &str) -> Result<CString> {
    CString::new(s).map_err(|_| "Texto con carácter nulo.".into())
}
impl Document {
    pub fn open(password: &str) -> Result<Self> {
        unsafe {
            let password = cstring(password)?;
            let mut error = ptr::null_mut();
            let doc = poppler_document_new_from_file(
                c"file:///document.pdf".as_ptr(),
                password.as_ptr(),
                &mut error,
            );
            if doc.is_null() {
                let locked = !error.is_null() && (*error).code == 1;
                if !error.is_null() {
                    g_error_free(error);
                }
                return Err(if locked {
                    "locked"
                } else {
                    "No se pudo leer el PDF."
                }
                .into());
            }
            let doc = Self(Owned(doc, g_object_unref));
            if !(1..=1000000).contains(&doc.pages()) {
                return Err("Número de páginas inválido.".into());
            }
            Ok(doc)
        }
    }
    pub fn pages(&self) -> i32 {
        unsafe { poppler_document_get_n_pages(self.0 .0) }
    }
    pub fn can_copy(&self) -> bool {
        unsafe { poppler_document_get_permissions(self.0 .0) & 4 != 0 }
    }
    pub fn page(&self, number: i32) -> Result<Page> {
        unsafe {
            if number < 1 || number > self.pages() {
                return Err("Página inválida.".into());
            }
            let p = poppler_document_get_page(self.0 .0, number - 1);
            if p.is_null() {
                Err("No se pudo leer la página.".into())
            } else {
                Ok(Page(Owned(p, g_object_unref)))
            }
        }
    }
    pub fn outline(&self) -> Vec<serde_json::Value> {
        unsafe fn walk(
            doc: P,
            iter: P,
            depth: usize,
            out: &mut Vec<serde_json::Value>,
            pages: i32,
        ) {
            if iter.is_null() {
                return;
            }
            let iter = Owned(iter, poppler_index_iter_free);
            if depth > 16 {
                return;
            }
            loop {
                if out.len() >= 2048 {
                    return;
                }
                let action = poppler_index_iter_get_action(iter.0);
                if !action.is_null() {
                    let mut page = 0;
                    // Only local goto actions: never launch files, URLs, scripts or remote destinations.
                    if (*action).kind == 2 && !(*action).dest.is_null() {
                        let dest = (*action).dest;
                        if (*dest).kind == 9 && !(*dest).name.is_null() {
                            let named = poppler_document_find_dest(doc, (*dest).name);
                            if !named.is_null() {
                                page = (*named).page;
                                poppler_dest_free(named);
                            }
                        } else {
                            page = (*dest).page;
                        }
                    }
                    if page < 0 || page > pages {
                        page = 0;
                    }
                    out.push(serde_json::json!({"title":string((*action).title).chars().take(512).collect::<String>(),"page":page,"depth":depth}));
                    poppler_action_free(action);
                }
                walk(
                    doc,
                    poppler_index_iter_get_child(iter.0),
                    depth + 1,
                    out,
                    pages,
                );
                if poppler_index_iter_next(iter.0) == 0 {
                    break;
                }
            }
        }
        let mut out = Vec::new();
        unsafe {
            walk(
                self.0 .0,
                poppler_index_iter_new(self.0 .0),
                0,
                &mut out,
                self.pages(),
            );
        }
        out
    }
}
impl Page {
    pub fn size(&self) -> Result<(f64, f64)> {
        let (mut w, mut h) = (0., 0.);
        unsafe {
            poppler_page_get_size(self.0 .0, &mut w, &mut h);
        }
        if !w.is_finite() || !h.is_finite() || w <= 0. || h <= 0. || w > 100000. || h > 100000. {
            return Err("Dimensiones de página inválidas.".into());
        }
        Ok((w, h))
    }
    pub fn words(&self, ocr: bool, language: &str) -> Result<Vec<Word>> {
        unsafe {
            let text = poppler_page_get_text(self.0 .0);
            let value = string(text);
            g_free(text.cast());
            if value.len() > 8 * 1024 * 1024 {
                return Err("Demasiado texto.".into());
            }
            let (mut rects, mut count) = (ptr::null_mut(), 0);
            poppler_page_get_text_layout(self.0 .0, &mut rects, &mut count);
            let allocation = Owned(rects.cast(), g_free);
            if count > 2 * 1024 * 1024 {
                return Err("Demasiado texto.".into());
            }
            let mut words: Vec<Word> = Vec::new();
            let mut current: Option<Word> = None;
            if !allocation.0.is_null() {
                for (i, c) in value.chars().take(count as usize).enumerate() {
                    if c.is_whitespace() {
                        if let Some(mut w) = current.take() {
                            w.space = true;
                            words.push(w);
                        }
                        continue;
                    }
                    let r = *rects.add(i);
                    let rect = Rect(r.x1, r.y1, (r.x2 - r.x1).max(0.), (r.y2 - r.y1).max(0.));
                    if !rect.valid() {
                        return Err("Coordenadas de texto inválidas.".into());
                    }
                    match &mut current {
                        Some(w) => {
                            w.text.push(c);
                            w.rect = w.rect.union(rect);
                        }
                        None => {
                            current = Some(Word {
                                text: c.to_string(),
                                rect,
                                space: false,
                            })
                        }
                    }
                    if current.as_ref().is_some_and(|w| w.text.len() > 16384)
                        || words.len() >= 50000
                    {
                        return Err("Demasiado texto.".into());
                    }
                }
            }
            if let Some(w) = current {
                words.push(w);
            }
            if words.is_empty() && ocr {
                return self.ocr(language);
            }
            Ok(words)
        }
    }
    pub fn search(&self, query: &str) -> Result<Vec<Rect>> {
        unsafe {
            let query = cstring(query)?;
            let list = poppler_page_find_text(self.0 .0, query.as_ptr());
            let mut node = list;
            let mut out = Vec::new();
            // Poppler search uses bottom-left coordinates; layout/rendering use top-left.
            let (_, height) = self.size()?;
            while !node.is_null() && out.len() < 2001 {
                let r = *((*node).data as *const Rectangle);
                out.push(Rect(r.x1, height - r.y2, r.x2 - r.x1, r.y2 - r.y1));
                node = (*node).next;
            }
            g_list_free_full(list, Some(poppler_rectangle_free));
            Ok(out)
        }
    }
    pub fn render(&self, dpi: f64, rotation: i32, region: Option<Rect>) -> Result<Raster> {
        unsafe {
            let (w, h) = self.size()?;
            let (rw, rh) = if rotation % 2 == 0 { (w, h) } else { (h, w) };
            let region = region.unwrap_or(Rect(0., 0., 1., 1.));
            let scale = dpi / 72.;
            let width = (rw * scale * region.2).round().max(1.) as usize;
            let height = (rh * scale * region.3).round().max(1.) as usize;
            if width > 4096 || height > 4096 {
                return Err("Imagen demasiado grande.".into());
            }
            let surface = Owned(
                cairo_image_surface_create(0, width as i32, height as i32),
                cairo_surface_destroy,
            );
            if cairo_surface_status(surface.0) != 0 {
                return Err("No se pudo crear la imagen.".into());
            }
            let cr = Owned(cairo_create(surface.0), cairo_destroy);
            cairo_set_source_rgb(cr.0, 1., 1., 1.);
            cairo_paint(cr.0);
            cairo_translate(
                cr.0,
                -(region.0 * rw * scale).round(),
                -(region.1 * rh * scale).round(),
            );
            cairo_scale(cr.0, scale, scale);
            match rotation {
                1 => cairo_translate(cr.0, h, 0.),
                2 => cairo_translate(cr.0, w, h),
                3 => cairo_translate(cr.0, 0., w),
                _ => {}
            }
            cairo_rotate(cr.0, f64::from(rotation) * std::f64::consts::FRAC_PI_2);
            poppler_page_render(self.0 .0, cr.0);
            cairo_surface_flush(surface.0);
            if cairo_status(cr.0) != 0 || cairo_surface_status(surface.0) != 0 {
                return Err("Falló el renderizado.".into());
            }
            let data = cairo_image_surface_get_data(surface.0);
            let stride = cairo_image_surface_get_stride(surface.0) as usize;
            if data.is_null() || stride < width * 4 {
                return Err("Imagen inválida.".into());
            }
            // Alpha is always 0xff (white background painted above); emit RGB to save
            // ~25% bytes in the PNG and base64 that cross the IPC boundary.
            let mut pixels = vec![0u8; width * height * 3];
            for y in 0..height {
                for x in 0..width {
                    let p = std::ptr::read_unaligned(data.add(y * stride + x * 4).cast::<u32>());
                    let dest = &mut pixels[(y * width + x) * 3..][..3];
                    dest.copy_from_slice(&[(p >> 16) as u8, (p >> 8) as u8, p as u8]);
                }
            }
            Ok(Raster {
                width,
                height,
                pixels,
            })
        }
    }
    fn ocr(&self, language: &str) -> Result<Vec<Word>> {
        unsafe {
            let (w, h) = self.size()?;
            let dpi = 220f64.min(2600. * 72. / w.max(h));
            let image = self.render(dpi, 0, None)?;
            let engine = Owned(TessBaseAPICreate(), TessBaseAPIDelete);
            let lang = cstring(language)?;
            if engine.0.is_null()
                || TessBaseAPIInit3(engine.0, c"/usr/share/tessdata".as_ptr(), lang.as_ptr()) != 0
            {
                return Err(
                    "Modelo OCR no disponible. Instala tesseract-data para el idioma elegido."
                        .into(),
                );
            }
            // render() now emits RGB (3 bytes/pixel); pass directly to Tesseract.
            TessBaseAPISetImage(
                engine.0,
                image.pixels.as_ptr(),
                image.width as i32,
                image.height as i32,
                3,
                (image.width * 3) as i32,
            );
            TessBaseAPISetSourceResolution(engine.0, dpi.round() as i32);
            if TessBaseAPIRecognize(engine.0, ptr::null_mut()) != 0 {
                return Err("Falló el OCR.".into());
            }
            let iter = Owned(TessBaseAPIGetIterator(engine.0), TessResultIteratorDelete);
            let mut words = Vec::new();
            if iter.0.is_null() {
                return Ok(words);
            }
            loop {
                let raw = TessResultIteratorGetUTF8Text(iter.0, 3);
                let text = string(raw).trim().to_owned();
                if !raw.is_null() {
                    TessDeleteText(raw);
                }
                let (mut x1, mut y1, mut x2, mut y2) = (0, 0, 0, 0);
                if TessPageIteratorBoundingBox(
                    TessResultIteratorGetPageIterator(iter.0),
                    3,
                    &mut x1,
                    &mut y1,
                    &mut x2,
                    &mut y2,
                ) != 0
                    && !text.is_empty()
                {
                    if words.len() >= 50000 || text.len() > 16384 {
                        return Err("Demasiado texto OCR.".into());
                    }
                    words.push(Word {
                        text,
                        rect: Rect(
                            x1 as f64 * 72. / dpi,
                            y1 as f64 * 72. / dpi,
                            (x2 - x1) as f64 * 72. / dpi,
                            (y2 - y1) as f64 * 72. / dpi,
                        ),
                        space: true,
                    });
                }
                if TessResultIteratorNext(iter.0, 3) == 0 {
                    break;
                }
            }
            Ok(words)
        }
    }
}

// PDFium is loaded only by the isolated worker. Poppler remains responsible for
// text/OCR and permissions so the rendering experiment preserves those contracts.
pub use pdfium_render::prelude::Pdfium;
use pdfium_render::prelude::{
    PdfBitmap, PdfBitmapFormat, PdfDocument, PdfPageRenderRotation, PdfRenderConfig,
};
pub fn load_pdfium() -> Result<Option<Pdfium>> {
    match std::env::var("PDF_VIEW_ENGINE")
        .as_deref()
        .unwrap_or("poppler")
    {
        "poppler" => Ok(None),
        "pdfium" => Pdfium::bind_to_library("/app/libpdfium.so")
            .map(|bindings| Some(Pdfium::new(bindings)))
            .map_err(|_| "No se pudo cargar la biblioteca PDFium compatible.".into()),
        _ => Err("Motor PDF desconocido.".into()),
    }
}
pub struct PdfiumDocument<'a>(PdfDocument<'a>);
impl<'a> PdfiumDocument<'a> {
    pub fn open(engine: &'a Pdfium, password: &str) -> Result<Self> {
        engine
            .load_pdf_from_file("/document.pdf", Some(password))
            .map(Self)
            .map_err(|_| "No se pudo abrir el documento con PDFium.".into())
    }
    pub fn render(
        &self,
        number: i32,
        dpi: f64,
        rotation: i32,
        region: Option<Rect>,
    ) -> Result<Raster> {
        let page = self
            .0
            .pages()
            .get(number - 1)
            .map_err(|_| "No se pudo abrir la página en PDFium.")?;
        let (w, h) = (
            f64::from(page.width().value),
            f64::from(page.height().value),
        );
        let (rw, rh) = if rotation % 2 == 0 { (w, h) } else { (h, w) };
        let r = region.unwrap_or(Rect(0., 0., 1., 1.));
        let width = (rw * dpi / 72. * r.2).round().max(1.) as usize;
        let height = (rh * dpi / 72. * r.3).round().max(1.) as usize;
        if width > 4096 || height > 4096 {
            return Err("Imagen demasiado grande.".into());
        }
        let angle = match rotation {
            1 => PdfPageRenderRotation::Degrees90,
            2 => PdfPageRenderRotation::Degrees180,
            3 => PdfPageRenderRotation::Degrees270,
            _ => PdfPageRenderRotation::None,
        };
        let config = PdfRenderConfig::new()
            .scale_page_by_factor((dpi / 72.) as f32)
            .rotate(angle, true)
            .set_origin(
                -(r.0 * rw * dpi / 72.).round() as i32,
                -(r.1 * rh * dpi / 72.).round() as i32,
            );
        let mut bitmap = PdfBitmap::empty(width as i32, height as i32, PdfBitmapFormat::BGRA)
            .map_err(|_| "No se pudo crear la imagen PDFium.")?;
        page.render_into_bitmap_with_config(&mut bitmap, &config)
            .map_err(|_| "Falló el renderizado PDFium.")?;
        let rgba = bitmap.as_rgba_bytes();
        if rgba.len() != width * height * 4 {
            return Err("Imagen PDFium inválida.".into());
        }
        let pixels = rgba
            .chunks_exact(4)
            .flat_map(|p| [p[0], p[1], p[2]])
            .collect();
        Ok(Raster {
            width,
            height,
            pixels,
        })
    }
}

use pdfium_render::prelude::{
    PdfColor, PdfPageAnnotationCommon, PdfPageAnnotationType, PdfPoints, PdfQuadPoints, PdfRect,
    PdfSecurityHandlerRevision,
};
use serde_json::{json, Value};
impl PdfiumDocument<'_> {
    pub fn can_annotate(&self) -> bool {
        matches!(
            self.0.permissions().security_handler_revision(),
            Ok(PdfSecurityHandlerRevision::Unprotected)
        ) && self.0.signatures().is_empty()
            && self
                .0
                .permissions()
                .can_add_or_modify_text_annotations()
                .unwrap_or(false)
    }
}
impl Page {
    fn annotation_color(&self, index: usize) -> Result<PdfColor> {
        // SAFETY: the mapping owns each annotation; color is separately allocated
        // by Poppler and released before the mapping, including early returns.
        unsafe {
            let mappings = Owned(
                poppler_page_get_annot_mapping(self.0 .0).cast(),
                poppler_page_free_annot_mapping,
            );
            let mut node = mappings.0.cast::<List>();
            for _ in 0..index {
                if node.is_null() {
                    return Err("Anotación inválida.".into());
                }
                node = (*node).next;
            }
            if node.is_null() {
                return Err("Anotación inválida.".into());
            }
            let mapping = &*((*node).data.cast::<AnnotMapping>());
            let color = Owned(
                poppler_annot_get_color(mapping.annot).cast(),
                poppler_color_free,
            );
            if color.0.is_null() {
                return Ok(PdfColor::BLACK);
            }
            let c = &*color.0.cast::<Color>();
            let [r, g, b] = [c.red, c.green, c.blue].map(|v| ((u32::from(v) + 128) / 257) as u8);
            Ok(PdfColor::new(r, g, b, 255))
        }
    }
    pub fn annotations(&self) -> Result<Vec<Value>> {
        let (_, height) = self.size()?;
        let mut notes = Vec::new();
        // Read metadata with Poppler: pdfium-render 0.9.4 casts an annotation
        // to a page object when stroke_color() encounters an appearance stream.
        // That invalid handle crashes after rendering some annotations.
        // SAFETY: mapping owns its annotations until the list is freed; returned
        // contents and colors have independent ownership and matching destructors.
        unsafe {
            let mappings = Owned(
                poppler_page_get_annot_mapping(self.0 .0).cast(),
                poppler_page_free_annot_mapping,
            );
            let mut node = mappings.0.cast::<List>();
            for _ in 0..256 {
                if node.is_null() {
                    break;
                }
                let mapping = &*((*node).data.cast::<AnnotMapping>());
                node = (*node).next;
                let kind = match poppler_annot_get_annot_type(mapping.annot) {
                    1 => "note",
                    9 => "highlight",
                    10 => "underline",
                    _ => continue,
                };
                let mut r = mapping.area;
                poppler_annot_get_rectangle(mapping.annot, &mut r);
                let contents = Owned(poppler_annot_get_contents(mapping.annot).cast(), g_free);
                let color = Owned(
                    poppler_annot_get_color(mapping.annot).cast(),
                    poppler_color_free,
                );
                let rgb = if color.0.is_null() {
                    [0, 0, 0]
                } else {
                    let c = &*color.0.cast::<Color>();
                    [c.red, c.green, c.blue].map(|v| (u32::from(v) + 128) / 257)
                };
                notes.push(
                    json!({"kind":kind,"color":format!("#{:02x}{:02x}{:02x}",rgb[0],rgb[1],rgb[2]),
                    "text":string(contents.0.cast()).chars().take(4000).collect::<String>(),
                    "rect":[r.x1,height-r.y2,r.x2-r.x1,r.y2-r.y1]}),
                );
            }
        }
        Ok(notes)
    }
}

pub fn export_annotation(engine: &Pdfium, v: &Value) -> Result<Vec<u8>> {
    let document = PdfiumDocument::open(engine, v["password"].as_str().unwrap_or(""))?;
    if !document.can_annotate() {
        return Err("No se pueden anotar PDFs protegidos o firmados en esta versión.".into());
    }
    let value = match v.get("color") {
        None => "#e69600",
        Some(color) => color.as_str().ok_or("Color inválido.")?,
    };
    let [red, green, blue] = pdf_view_backend::annotation_rgb(value)?;
    let ink = PdfColor::new(red, green, blue, 255);
    let number = pdf_view_backend::integer(v, "page", 0);
    let kind = v["annotation"].as_str().unwrap_or("");
    let text = v["note"].as_str().unwrap_or("");
    let rects: Vec<Rect> =
        serde_json::from_value(v["rects"].clone()).map_err(|_| "Selección inválida.")?;
    if number < 1
        || number > i64::from(document.0.pages().len())
        || !["note", "underline", "remove_underline"].contains(&kind)
        || text.chars().count() > 4000
        || rects.is_empty()
        || rects.len() > 128
        || (kind == "note" && text.trim().is_empty())
    {
        return Err("Anotación inválida (máximo 128 palabras y 4000 caracteres).".into());
    }
    {
        let mut page = document
            .0
            .pages()
            .get(number as i32 - 1)
            .map_err(|_| "Página inválida.")?;
        let (w, h) = (
            f64::from(page.width().value),
            f64::from(page.height().value),
        );
        if rects.iter().any(|r| {
            !r.valid()
                || r.0 < 0.
                || r.1 < 0.
                || r.2 <= 0.
                || r.3 <= 0.
                || r.0 + r.2 > w + 1.
                || r.1 + r.3 > h + 1.
        }) {
            return Err("Coordenadas fuera de la página.".into());
        }
        let bounds = |r: Rect| {
            PdfRect::new(
                PdfPoints::new((h - r.1 - r.3) as f32),
                PdfPoints::new(r.0 as f32),
                PdfPoints::new((h - r.1) as f32),
                PdfPoints::new((r.0 + r.2) as f32),
            )
        };
        if kind == "remove_underline" {
            let source = Document::open(v["password"].as_str().unwrap_or(""))?;
            let source_page = source.page(number as i32)?;
            let annotations = page.annotations_mut();
            if annotations.len() > 256 {
                return Err("La página supera el límite de 256 anotaciones para borrar.".into());
            }
            let mut removed = false;
            // Delete backwards so remaining annotation indices stay valid.
            for index in (0..annotations.len()).rev() {
                let annotation = annotations.get(index).map_err(|_| "Anotación inválida.")?;
                if annotation.annotation_type() != PdfPageAnnotationType::Underline {
                    continue;
                }
                let points = annotation.attachment_points();
                if points.len() > 128 {
                    return Err("El subrayado supera 128 segmentos.".into());
                }
                let mut changed = false;
                let mut remaining = Vec::new();
                for point in 0..points.len() {
                    let area = points
                        .get(point)
                        .map_err(|_| "Geometría de subrayado inválida.")?
                        .to_rect();
                    let mut pieces = vec![area];
                    for r in &rects {
                        let cut = bounds(*r);
                        let cy = (cut.bottom().value + cut.top().value) / 2.;
                        let mut next = Vec::new();
                        for piece in pieces {
                            if cy < piece.bottom().value
                                || cy > piece.top().value
                                || cut.right().value <= piece.left().value
                                || cut.left().value >= piece.right().value
                            {
                                next.push(piece);
                                continue;
                            }
                            changed = true;
                            if cut.left().value - piece.left().value > 0.1 {
                                next.push(PdfRect::new(
                                    piece.bottom(),
                                    piece.left(),
                                    piece.top(),
                                    cut.left(),
                                ));
                            }
                            if piece.right().value - cut.right().value > 0.1 {
                                next.push(PdfRect::new(
                                    piece.bottom(),
                                    cut.right(),
                                    piece.top(),
                                    piece.right(),
                                ));
                            }
                        }
                        pieces = next;
                    }
                    remaining.extend(pieces);
                    if remaining.len() > 128 {
                        return Err("La selección produciría más de 128 segmentos.".into());
                    }
                }
                if changed {
                    let color = source_page.annotation_color(index)?;
                    let contents = annotation.contents();
                    let creator = annotation.creator();
                    annotations
                        .delete_annotation(annotation)
                        .map_err(|_| "No se pudo quitar el subrayado.")?;
                    if !remaining.is_empty() {
                        let result =
                            (|| -> std::result::Result<(), pdfium_render::prelude::PdfiumError> {
                                let mut replacement = annotations.create_underline_annotation()?;
                                let left = remaining
                                    .iter()
                                    .map(|r| r.left().value)
                                    .fold(f32::INFINITY, f32::min);
                                let right = remaining
                                    .iter()
                                    .map(|r| r.right().value)
                                    .fold(f32::NEG_INFINITY, f32::max);
                                let bottom = remaining
                                    .iter()
                                    .map(|r| r.bottom().value)
                                    .fold(f32::INFINITY, f32::min);
                                let top = remaining
                                    .iter()
                                    .map(|r| r.top().value)
                                    .fold(f32::NEG_INFINITY, f32::max);
                                replacement
                                    .set_position(PdfPoints::new(left), PdfPoints::new(bottom))?;
                                replacement.set_width(PdfPoints::new(right - left))?;
                                replacement.set_height(PdfPoints::new(top - bottom))?;
                                replacement.set_stroke_color(color)?;
                                if let Some(text) = contents {
                                    replacement.set_contents(&text)?;
                                }
                                if let Some(name) = creator {
                                    replacement.set_creator(&name)?;
                                }
                                for r in remaining {
                                    replacement
                                        .attachment_points_mut()
                                        .create_attachment_point_at_end(PdfQuadPoints::new(
                                            r.left(),
                                            r.top(),
                                            r.right(),
                                            r.top(),
                                            r.left(),
                                            r.bottom(),
                                            r.right(),
                                            r.bottom(),
                                        ))?;
                                }
                                Ok(())
                            })();
                        result.map_err(|_| "No se pudo conservar el resto del subrayado.")?;
                    }
                    removed = true;
                }
            }
            if !removed {
                return Err("No hay subrayados guardados en la selección.".into());
            }
        } else {
            let result = (|| -> std::result::Result<(), pdfium_render::prelude::PdfiumError> {
                if kind == "note" {
                    let r = bounds(rects[0]);
                    let mut a = page.annotations_mut().create_text_annotation(text)?;
                    a.set_position(r.left(), r.bottom())?;
                    a.set_width(PdfPoints::new(20.))?;
                    a.set_height(PdfPoints::new(20.))?;
                    a.set_stroke_color(ink)?;
                } else {
                    let union = rects.iter().copied().reduce(|a, b| a.union(b)).unwrap();
                    let r = bounds(union);
                    let mut a = page.annotations_mut().create_underline_annotation()?;
                    a.set_position(r.left(), r.bottom())?;
                    a.set_width(r.width())?;
                    a.set_height(r.height())?;
                    a.set_stroke_color(ink)?;
                    for rect in rects {
                        let r = bounds(rect);
                        // Text markup uses Z order (top-left, top-right, bottom-left,
                        // bottom-right), not PdfRect's counter-clockwise polygon order.
                        let quad = PdfQuadPoints::new(
                            r.left(),
                            r.top(),
                            r.right(),
                            r.top(),
                            r.left(),
                            r.bottom(),
                            r.right(),
                            r.bottom(),
                        );
                        a.attachment_points_mut()
                            .create_attachment_point_at_end(quad)?;
                    }
                }
                Ok(())
            })();
            result.map_err(|_| "No se pudo crear la anotación.")?;
        }
    }
    struct BoundedPdf(Vec<u8>);
    impl std::io::Write for BoundedPdf {
        fn write(&mut self, bytes: &[u8]) -> std::io::Result<usize> {
            if self.0.len() + bytes.len() > 256 * 1024 * 1024 {
                return Err(std::io::Error::other("PDF demasiado grande"));
            }
            self.0.extend_from_slice(bytes);
            Ok(bytes.len())
        }
        fn flush(&mut self) -> std::io::Result<()> {
            Ok(())
        }
    }
    let mut output = BoundedPdf(Vec::new());
    document
        .0
        .save_to_writer(&mut output)
        .map_err(|_| "No se pudo guardar el PDF (máximo 256 MiB).")?;
    let checked = engine
        .load_pdf_from_byte_slice(&output.0, None)
        .map_err(|_| "El PDF guardado no se pudo verificar.")?;
    if checked.pages().len() != document.0.pages().len() {
        return Err("El PDF guardado perdió páginas.".into());
    }
    drop(checked);
    Ok(output.0)
}
