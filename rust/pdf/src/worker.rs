mod native;
use native::Document;
use pdf_view_backend::*;
use serde_json::{json, Value};
use std::io::BufRead;
fn run(
    doc_slot: &mut Option<Document>,
    current_pass: &mut String,
    v: &Value,
) -> Result<(Value, Vec<u8>)> {
    let op = v["op"].as_str().unwrap_or("");
    let ocr = v["ocr"].as_bool().unwrap_or(false);
    let lang = v["language"].as_str().unwrap_or("eng");
    if !language_valid(lang) {
        return Err("Idioma OCR inválido.".into());
    }
    let password = v["password"].as_str().unwrap_or("");
    if password.len() > 4096 {
        return Err("Contraseña demasiado larga.".into());
    }
    if doc_slot.is_none() || password != current_pass {
        *doc_slot = None;
        *doc_slot = Some(Document::open(password)?);
        *current_pass = password.to_string();
    }
    let doc = doc_slot.as_ref().unwrap();
    if op == "extract" {
        if !doc.can_copy() {
            return Err("El documento no permite copiar texto.".into());
        }
        let first = integer(v, "first", 0);
        let last = integer(v, "last", 0);
        if first < 1 || last < first || last > doc.pages() as i64 || last - first >= 100 {
            return Err("Selecciona un rango de hasta 100 páginas.".into());
        }
        let mut text = String::new();
        for page in first..=last {
            let words = doc.page(page as i32)?.words(ocr, lang)?;
            let start = if page == first {
                integer(v, "firstWord", 0)
            } else {
                0
            };
            let end = if page == last {
                integer(v, "lastWord", words.len() as i64 - 1)
            } else {
                words.len() as i64 - 1
            };
            if start < 0
                || end < -1
                || start > words.len() as i64
                || end >= words.len() as i64
                || start > end + 1
            {
                return Err("Selección inválida.".into());
            }
            if page > first {
                text.push_str("\n\n");
            }
            text.push_str(&joined(&words[start as usize..(end + 1) as usize]));
            if text.chars().count() > 2 * 1024 * 1024 {
                return Err("La selección supera 2 Mi caracteres.".into());
            }
        }
        return Ok((json!({"text":text}), vec![]));
    }
    if op == "search" {
        let query = v["query"].as_str().unwrap_or("");
        if query.is_empty() || query.chars().count() > 256 {
            return Err("Consulta inválida.".into());
        }
        let mut matches = Vec::new();
        let mut truncated = false;
        for page in 1..=doc.pages() {
            let p = doc.page(page)?;
            let mut found = p.search(query)?;
            if ocr && doc.can_copy() && p.words(false, lang)?.is_empty() {
                let words = p.words(true, lang)?;
                let mut text = String::new();
                let mut starts = Vec::new();
                for word in &words {
                    let start = text.len();
                    text.push_str(&word.text.to_lowercase());
                    starts.push((start, text.len()));
                    text.push(' ');
                }
                for (at, matched) in text.match_indices(&query.to_lowercase()) {
                    let mut rect: Option<Rect> = None;
                    for (i, (start, end)) in starts.iter().enumerate() {
                        if *start < at + matched.len() && *end > at {
                            rect = Some(rect.map_or(words[i].rect, |r| r.union(words[i].rect)));
                        }
                    }
                    if let Some(r) = rect {
                        found.push(r);
                    }
                    if found.len() > 2000 {
                        break;
                    }
                }
            }
            for rect in found {
                if matches.len() == 2000 {
                    truncated = true;
                    break;
                }
                matches.push(json!({"page":page,"rect":rect}));
            }
            if truncated {
                break;
            }
        }
        return Ok((json!({"matches":matches,"truncated":truncated}), vec![]));
    }
    if !["render", "thumbnail", "region"].contains(&op) {
        return Err("Operación desconocida.".into());
    }
    let number = integer(v, "page", 1);
    let rotation = integer(v, "rotation", 0);
    let requested = number_f64(v);
    if number < 1
        || number > doc.pages() as i64
        || !(0..=3).contains(&rotation)
        || !(18.0..=768.0).contains(&requested)
    {
        return Err("Petición de renderizado inválida.".into());
    }
    let page = doc.page(number as i32)?;
    let (w, h) = page.size()?;
    let dpi = if op == "region" {
        requested
    } else {
        requested.min(if op == "thumbnail" { 220. } else { 2000. } * 72. / w.max(h))
    };
    let region = if op == "region" {
        let r: Rect =
            serde_json::from_value(v["region"].clone()).map_err(|_| "Región inválida.")?;
        if !r.valid()
            || r.0 < 0.
            || r.1 < 0.
            || r.2 <= 0.
            || r.3 <= 0.
            || r.0 + r.2 > 1.001
            || r.1 + r.3 > 1.001
        {
            return Err("Región inválida.".into());
        }
        Some(r)
    } else {
        None
    };
    let image = page.render(dpi, rotation as i32, region)?;
    if op == "region" && (image.width > 2048 || image.height > 2048) {
        return Err("Región demasiado grande.".into());
    }
    let words = if op == "render" && doc.can_copy() {
        page.words(ocr, lang)?
    } else {
        vec![]
    };
    let mut meta = json!({"width":image.width,"height":image.height,"pages":doc.pages(),"page":number,"rotation":rotation,
        "pageWidth":w,"pageHeight":h,"canCopy":doc.can_copy(),"words":words});
    if v["outline"].as_bool() == Some(true) {
        meta["outline"] = json!(doc.outline());
    }
    Ok((meta, image.pixels))
}
fn number_f64(v: &Value) -> f64 {
    number(v, "dpi", 144.)
}
fn main() {
    for (resource, limit) in [
        (libc::RLIMIT_AS, 1024 * 1024 * 1024),
        (libc::RLIMIT_CPU, 30),
        (libc::RLIMIT_CORE, 0),
    ] {
        let r = libc::rlimit {
            rlim_cur: limit,
            rlim_max: limit,
        };
        if unsafe { libc::setrlimit(resource, &r) } != 0 {
            std::process::exit(10);
        }
    }
    let stdin = std::io::stdin();
    let mut input = std::io::BufReader::new(stdin.lock());
    let mut doc_slot: Option<Document> = None;
    let mut current_pass = String::new();
    loop {
        let mut line = Vec::new();
        let n = match input.read_until(b'\n', &mut line) {
            Ok(n) => n,
            Err(_) => break,
        };
        if n == 0 {
            break;
        }
        if n > 16384 {
            let (meta, pixels) = (json!({"error":"Petición demasiado grande."}), vec![]);
            if write_frame(&meta, &pixels).is_err() {
                std::process::exit(7);
            }
            continue;
        }
        let req: Value =
            match serde_json::from_slice::<Value>(&line[..line.len().saturating_sub(1)]) {
                Ok(v) if v.is_object() => v,
                _ => continue,
            };
        let result = run(&mut doc_slot, &mut current_pass, &req);
        let (meta, pixels) = match result {
            Ok(r) => r,
            Err(e) if e == "locked" => (json!({"locked":true}), vec![]),
            Err(e) => (
                json!({"error":e.chars().take(256).collect::<String>()}),
                vec![],
            ),
        };
        if write_frame(&meta, &pixels).is_err() {
            std::process::exit(7);
        }
    }
}
