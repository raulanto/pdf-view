use serde_json::Value;
use std::collections::VecDeque;

pub struct Cache {
    pub entries: VecDeque<(String, Value, usize)>,
    pub bytes: usize,
}

impl Cache {
    pub fn get(&mut self, key: &str) -> Option<Value> {
        let i = self.entries.iter().position(|e| e.0 == key)?;
        let e = self.entries.remove(i)?;
        let value = e.1.clone();
        self.entries.push_back(e);
        Some(value)
    }
    pub fn put(&mut self, key: String, value: Value) {
        let size = value.to_string().len() + key.len();
        if size > 96 * 1024 * 1024 {
            return;
        }
        while self.bytes + size > 96 * 1024 * 1024 {
            if let Some(e) = self.entries.pop_front() {
                self.bytes -= e.2;
            } else {
                break;
            }
        }
        self.bytes += size;
        self.entries.push_back((key, value, size));
    }
    pub fn clear(&mut self) {
        self.entries.clear();
        self.bytes = 0;
    }
}
