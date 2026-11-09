#[cfg(not(target_os = "windows"))]
use base64::Engine;
#[cfg(not(target_os = "windows"))]
use std::{io::Read, time::Duration};

#[cfg(not(target_os = "windows"))]
pub fn fetch(bus: String) -> Result<Option<String>, String> {
    let snapshots = crate::player::players(Some(bus))?;
    let Some(uri) = snapshots.first().and_then(|s| s.artwork.as_ref()) else {
        return Ok(None);
    };
    let url = reqwest::Url::parse(uri).map_err(|e| e.to_string())?;
    let mut bytes = Vec::new();
    if url.scheme() == "https" {
        let host = url.host_str().unwrap_or("");
        // Known artwork CDNs only. Never proxy loopback, arbitrary local files or LAN services.
        let allowed = [
            "scdn.co",
            "spotifycdn.com",
            "mzstatic.com",
            "dzcdn.net",
            "ytimg.com",
            "lastfm.freetls.fastly.net",
        ];
        if !allowed
            .iter()
            .any(|h| host == *h || host.ends_with(&format!(".{h}")))
        {
            return Ok(None);
        }
        let client = reqwest::blocking::Client::builder()
            .timeout(Duration::from_secs(8))
            .redirect(reqwest::redirect::Policy::none())
            .build()
            .map_err(|e| e.to_string())?;
        let response = client
            .get(url)
            .send()
            .and_then(reqwest::blocking::Response::error_for_status)
            .map_err(|e| e.to_string())?;
        response
            .take(5_000_001)
            .read_to_end(&mut bytes)
            .map_err(|e| e.to_string())?;
    } else if url.scheme() == "file" {
        let path = url
            .to_file_path()
            .map_err(|_| "Invalid artwork file URL")?
            .canonicalize()
            .map_err(|e| e.to_string())?;
        let cache = std::env::var_os("XDG_CACHE_HOME")
            .map(std::path::PathBuf::from)
            .or_else(|| {
                std::env::var_os("HOME").map(|h| std::path::PathBuf::from(h).join(".cache"))
            });
        if !cache.is_some_and(|c| path.starts_with(c)) {
            return Ok(None);
        }
        std::fs::File::open(path)
            .map_err(|e| e.to_string())?
            .take(5_000_001)
            .read_to_end(&mut bytes)
            .map_err(|e| e.to_string())?;
    } else {
        return Ok(None);
    }
    if bytes.len() > 5_000_000 {
        return Ok(None);
    }
    let mime = if bytes.starts_with(b"\x89PNG\r\n\x1a\n") {
        "image/png"
    } else if bytes.starts_with(&[0xff, 0xd8, 0xff]) {
        "image/jpeg"
    } else if bytes.starts_with(b"RIFF") && bytes.get(8..12) == Some(b"WEBP") {
        "image/webp"
    } else {
        return Ok(None);
    };
    Ok(Some(format!(
        "data:{mime};base64,{}",
        base64::engine::general_purpose::STANDARD.encode(bytes)
    )))
}

#[cfg(target_os = "windows")]
pub use crate::windows::player::artwork as fetch;
