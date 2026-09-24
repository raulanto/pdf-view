//! Local preferences; separate mode of the broker, without documents or workers.
use serde_json::{json, Value};
use std::{
    collections::BTreeSet,
    fs::{self, File, OpenOptions},
    io::{self, BufRead, Read, Write},
    os::unix::fs::OpenOptionsExt,
    path::PathBuf,
};
const LIMIT: u64 = 16384;
const ACTIONS: &[(&str, &str, &str)] = &[
    ("open", "Abrir PDF", "Ctrl+O"),
    ("search", "Buscar", "Ctrl+F"),
    ("focus", "Modo lectura", "Ctrl+E"),
    ("next", "Página siguiente", "PgDown"),
    ("previous", "Página anterior", "PgUp"),
    ("first", "Primera página", "Ctrl+Home"),
    ("last", "Última página", "Ctrl+End"),
    ("zoomIn", "Aumentar zoom", "Ctrl++"),
    ("zoomOut", "Reducir zoom", "Ctrl+-"),
    ("fit", "Ajustar página", "Ctrl+0"),
    ("rotate", "Rotar página", "Ctrl+R"),
    ("copy", "Copiar selección", "Ctrl+C"),
    ("selectAll", "Seleccionar todo", "Ctrl+A"),
    ("nextMatch", "Siguiente coincidencia", "F3"),
    ("previousMatch", "Coincidencia anterior", "Shift+F3"),
    ("annotate", "Cinta de anotación", "Ctrl+Shift+A"),
    ("settings", "Configuración", "Ctrl+,"),
];
fn defaults() -> Value {
    let keys: serde_json::Map<String, Value> = ACTIONS
        .iter()
        .map(|(id, _, key)| (id.to_string(), json!(key)))
        .collect();
    json!({"fit":"page","zoom":100,"smooth":true,"scrollStep":100,"uiScale":100,
        "ocr":false,"language":"eng","color":"#e69600","selectionToolbar":true,"sidebar":true,"keys":keys})
}
fn canonical_key(input: &str) -> Result<String, String> {
    if input.is_empty() || input.len() > 48 {
        return Err("Atajo vacío o demasiado largo.".into());
    }
    let input = input.trim();
    let (prefix, key) = if let Some(prefix) = input.strip_suffix("++") {
        (prefix, "+")
    } else {
        input.rsplit_once('+').unwrap_or(("", input))
    };
    let mut mods = BTreeSet::new();
    if !prefix.is_empty() {
        for part in prefix.split('+') {
            let part = part.to_ascii_lowercase();
            if !["ctrl", "alt", "shift", "meta"].contains(&part.as_str()) || !mods.insert(part) {
                return Err("Modificadores inválidos; usa Ctrl, Alt, Shift o Meta.".into());
            }
        }
    }
    let key = key.to_ascii_uppercase();
    let named = match key.as_str() {
        "PGDOWN" => "PgDown",
        "PGUP" => "PgUp",
        "HOME" => "Home",
        "END" => "End",
        "SPACE" => "Space",
        "LEFT" => "Left",
        "RIGHT" => "Right",
        "UP" => "Up",
        "DOWN" => "Down",
        _ => &key,
    };
    let function = key
        .strip_prefix('F')
        .and_then(|v| v.parse::<u8>().ok())
        .is_some_and(|v| (1..=12).contains(&v));
    let character = key.len() == 1
        && (key.as_bytes()[0].is_ascii_alphanumeric() || ["+", "-", ","].contains(&key.as_str()));
    if !(function
        || [
            "PgDown", "PgUp", "Home", "End", "Space", "Left", "Right", "Up", "Down",
        ]
        .contains(&named)
        || character)
        || (character || named == "Space")
            && !mods.contains("ctrl")
            && !mods.contains("alt")
            && !mods.contains("meta")
    {
        return Err("Usa una tecla de navegación, F1–F12 o Ctrl/Alt/Meta con una letra, número, +, - o coma. Esc queda reservado.".into());
    }
    let mut result = String::new();
    for (id, label) in [
        ("ctrl", "Ctrl"),
        ("alt", "Alt"),
        ("shift", "Shift"),
        ("meta", "Meta"),
    ] {
        if mods.contains(id) {
            result.push_str(label);
            result.push('+');
        }
    }
    result.push_str(named);
    Ok(result)
}
fn validate(mut value: Value) -> Result<Value, String> {
    let base = defaults();
    if value
        .as_object()
        .is_none_or(|v| v.len() != base.as_object().unwrap().len())
        || base
            .as_object()
            .unwrap()
            .keys()
            .any(|k| value.get(k).is_none())
    {
        return Err("Formato de configuración inválido.".into());
    }
    for (name, min, max) in [
        ("zoom", 25, 400),
        ("scrollStep", 20, 400),
        ("uiScale", 75, 150),
    ] {
        if value[name].as_u64().is_none_or(|n| n < min || n > max) {
            return Err(format!("{name}: valor fuera de rango ({min}–{max})."));
        }
    }
    for name in ["smooth", "ocr", "selectionToolbar", "sidebar"] {
        if !value[name].is_boolean() {
            return Err("Opción inválida.".into());
        }
    }
    if !["page", "width", "manual"].contains(&value["fit"].as_str().unwrap_or(""))
        || !pdf_view_backend::language_valid(value["language"].as_str().unwrap_or(""))
    {
        return Err("Ajuste o idioma OCR inválido.".into());
    }
    pdf_view_backend::annotation_rgb(value["color"].as_str().unwrap_or(""))?;
    let keys = value["keys"].as_object_mut().ok_or("Atajos inválidos.")?;
    if keys.len() != ACTIONS.len() {
        return Err("Lista de atajos incompleta.".into());
    }
    let mut used = BTreeSet::new();
    for (id, label, _) in ACTIONS {
        let key = canonical_key(
            keys.get(*id)
                .and_then(Value::as_str)
                .ok_or("Atajo inválido.")?,
        )?;
        if !used.insert(key.clone()) {
            return Err(format!("Atajo duplicado: {key} ({label})."));
        }
        keys.insert(id.to_string(), json!(key));
    }
    Ok(value)
}
fn path() -> io::Result<PathBuf> {
    if let Some(p) = std::env::var_os("PDF_VIEW_SETTINGS_FILE") {
        return Ok(p.into());
    }
    let dir = std::env::var_os("XDG_CONFIG_HOME")
        .map(PathBuf::from)
        .filter(|p| p.is_absolute())
        .or_else(|| std::env::var_os("HOME").map(|h| PathBuf::from(h).join(".config")))
        .ok_or_else(|| io::Error::other("No se encontró el directorio de configuración."))?;
    Ok(dir.join("pdf-view/settings.json"))
}
fn load(path: &PathBuf) -> Result<Value, String> {
    let file = match OpenOptions::new()
        .read(true)
        .custom_flags((rustix::fs::OFlags::NOFOLLOW | rustix::fs::OFlags::NONBLOCK).bits() as i32)
        .open(path)
    {
        Ok(f) => f,
        Err(e) if e.kind() == io::ErrorKind::NotFound => return Ok(defaults()),
        Err(_) => return Err("No se pudo leer la configuración.".into()),
    };
    if !file
        .metadata()
        .map_err(|_| "No se pudo consultar la configuración.")?
        .is_file()
    {
        return Err("La configuración no es un archivo regular.".into());
    }
    let mut bytes = Vec::new();
    file.take(LIMIT + 1)
        .read_to_end(&mut bytes)
        .map_err(|_| "No se pudo leer la configuración.")?;
    if bytes.len() > LIMIT as usize {
        return Err("La configuración supera 16 KiB.".into());
    }
    validate(serde_json::from_slice(&bytes).map_err(|_| {
        "El archivo de configuración está dañado; puedes restaurar los valores iniciales."
    })?)
}
fn save(path: &PathBuf, value: &Value) -> io::Result<()> {
    let parent = path
        .parent()
        .ok_or_else(|| io::Error::other("Ruta inválida"))?;
    fs::create_dir_all(parent)?;
    let temp = parent.join(format!(".settings-{}.tmp", std::process::id()));
    let mut file = OpenOptions::new()
        .write(true)
        .create_new(true)
        .mode(0o600)
        .open(&temp)?;
    let result = (|| {
        file.write_all(&serde_json::to_vec_pretty(value)?)?;
        file.sync_all()?;
        fs::rename(&temp, path)?;
        File::open(parent)?.sync_all()
    })();
    if result.is_err() {
        let _ = fs::remove_file(temp);
    }
    result
}
pub fn run() -> io::Result<()> {
    let path = path()?;
    let mut input = io::stdin().lock();
    loop {
        let mut line = Vec::new();
        let n = input
            .by_ref()
            .take(LIMIT + 1)
            .read_until(b'\n', &mut line)?;
        if n == 0 || n > LIMIT as usize {
            break;
        }
        let request: Value = match serde_json::from_slice(&line) {
            Ok(v) => v,
            Err(_) => continue,
        };
        let result = match request["op"].as_str() {
            Some("load") => load(&path),
            Some("save") => validate(request["settings"].clone()).and_then(|v| {
                save(&path, &v)
                    .map(|()| v)
                    .map_err(|_| "No se pudo guardar la configuración.".into())
            }),
            _ => Err("Operación de configuración inválida.".into()),
        };
        let data = match result {
            Ok(value) => json!({"settings":value}),
            Err(error) => json!({"error":error}),
        };
        let actions: Vec<_> = ACTIONS
            .iter()
            .map(|(id, label, _)| json!({"id":id,"label":label}))
            .collect();
        let response =
            json!({"id":request["id"],"data":data,"defaults":defaults(),"actions":actions});
        let mut out = io::stdout().lock();
        writeln!(out, "{response}")?;
        out.flush()?;
    }
    Ok(())
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn validates_shortcuts_and_ranges() {
        assert!(validate(defaults()).is_ok());
        assert_eq!(canonical_key("shift+ctrl+a").unwrap(), "Ctrl+Shift+A");
        for key in ["A", "Shift+A", "Escape", "Ctrl+Ctrl+A", "Ctrl+Unknown"] {
            assert!(canonical_key(key).is_err());
        }
        let mut v = defaults();
        v["keys"]["open"] = json!("Ctrl+F");
        assert!(validate(v).is_err());
        let mut v = defaults();
        v["uiScale"] = json!(500);
        assert!(validate(v).is_err());
    }
}
