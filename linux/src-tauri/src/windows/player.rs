//! Windows System Media Transport Controls. The session ID is intentionally not
//! used as a PID: packaged AppUserModelIDs and browser sessions are not processes.
use crate::player::Snapshot;
use base64::Engine;
use windows::Media::Control::{
    GlobalSystemMediaTransportControlsSession as Session,
    GlobalSystemMediaTransportControlsSessionManager as Manager,
    GlobalSystemMediaTransportControlsSessionPlaybackStatus as Status,
};
use windows::Storage::Streams::{Buffer, DataReader, InputStreamOptions};

fn manager() -> Result<Manager, String> {
    Manager::RequestAsync()
        .and_then(|op| op.get())
        .map_err(|e| format!("Windows media sessions are unavailable: {e}"))
}
fn session(bus: &str) -> Result<Session, String> {
    let matches: Vec<_> = manager()?
        .GetSessions()
        .map_err(|e| e.to_string())?
        .into_iter()
        .filter(|s| {
            s.SourceAppUserModelId()
                .is_ok_and(|id| id.to_string() == bus)
        })
        .collect();
    if matches.len() > 1 {
        return Err("This player publishes multiple Windows sessions with the same identity. Close extra browser tabs or player windows, then reconnect; Afterglow will not guess which session to control.".into());
    }
    matches
        .into_iter()
        .next()
        .ok_or_else(|| "This player has disconnected. Refresh players.".into())
}
pub fn players(selected: Option<String>) -> Result<Vec<Snapshot>, String> {
    let _apartment = super::Apartment::new()?;
    let sessions: Vec<_> = manager()?
        .GetSessions()
        .map_err(|e| e.to_string())?
        .into_iter()
        .filter_map(|session| {
            session
                .SourceAppUserModelId()
                .ok()
                .map(|id| (id.to_string(), session))
        })
        .collect();
    // Count identities before requesting metadata. A broken duplicate session is
    // still ambiguous and must not make its healthy neighbor look uniquely safe.
    let identities = identity_counts(sessions.iter().map(|(id, _)| id.as_str()));
    if selected
        .as_ref()
        .is_some_and(|id| identities.get(id).is_some_and(|count| *count > 1))
    {
        return Err("Multiple Windows media sessions share this player identity. Close extra browser tabs or player windows, then reconnect.".into());
    }
    let ambiguous = identities.values().any(|count| *count > 1);
    let mut output = Vec::new();
    for (bus, session) in sessions {
        if identities[&bus] != 1 || selected.as_ref().is_some_and(|id| *id != bus) {
            continue;
        }
        let result = (|| -> windows::core::Result<Snapshot> {
            let metadata = session.TryGetMediaPropertiesAsync()?.get()?;
            let playback = session.GetPlaybackInfo()?;
            let timeline = session.GetTimelineProperties()?;
            let start = timeline.StartTime()?.Duration as f64 / 10_000_000.0;
            let duration = (timeline.EndTime()?.Duration as f64 / 10_000_000.0 - start).max(0.0);
            let rate = playback
                .PlaybackRate()
                .and_then(|r| r.Value())
                .unwrap_or(1.0);
            let rate = if rate.is_finite() && rate > 0.0 {
                rate
            } else {
                1.0
            };
            let playing = playback.PlaybackStatus()? == Status::Playing;
            let position = timeline.Position()?.Duration as f64 / 10_000_000.0 - start;
            // SMTC Position is sampled at LastUpdatedTime, not at our query time.
            let unix = std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap_or_default()
                .as_secs_f64();
            let updated =
                timeline.LastUpdatedTime()?.UniversalTime as f64 / 10_000_000.0 - 11_644_473_600.0;
            let position = sampled_position(position, duration, updated, unix, playing, rate);
            let lower = bus.to_lowercase();
            let identity = if lower.contains("spotify") {
                "Spotify".into()
            } else if lower.contains("applemusic") || lower.contains("apple.music") {
                "Apple Music".into()
            } else {
                bus.clone()
            };
            Ok(Snapshot {
                bus,
                identity,
                title: metadata.Title()?.to_string(),
                artist: metadata.Artist()?.to_string(),
                album: metadata.AlbumTitle()?.to_string(),
                duration,
                position,
                playing,
                rate,
                artwork: None,
                can_seek: playback.Controls()?.IsPlaybackPositionEnabled()?,
            })
        })();
        if let Ok(snapshot) = result {
            output.push(snapshot);
        }
    }
    if ambiguous && output.is_empty() {
        return Err("Multiple Windows media sessions share a player identity. Close extra browser tabs or player windows, then refresh. Afterglow will not control an ambiguous session.".into());
    }
    Ok(output)
}
pub fn control(bus: String, action: String, position: Option<f64>) -> Result<(), String> {
    let _apartment = super::Apartment::new()?;
    let session = session(&bus)?;
    let operation = match action.as_str() {
        "toggle" => session.TryTogglePlayPauseAsync(),
        "next" => session.TrySkipNextAsync(),
        "previous" => session.TrySkipPreviousAsync(),
        "stop" => session.TryStopAsync(),
        "seek" => {
            let position = position
                .filter(|p| p.is_finite() && (0.0..=86_400.0).contains(p))
                .ok_or("Invalid playback position.")?;
            let start = session
                .GetTimelineProperties()
                .and_then(|t| t.StartTime())
                .map_err(|e| e.to_string())?
                .Duration;
            session.TryChangePlaybackPositionAsync(start + (position * 10_000_000.0) as i64)
        }
        _ => return Err("Unknown player command.".into()),
    }
    .map_err(|e| e.to_string())?;
    if operation.get().map_err(|e| e.to_string())? {
        Ok(())
    } else {
        Err("The player does not support this command in its current state.".into())
    }
}
pub fn artwork(bus: String) -> Result<Option<String>, String> {
    let _apartment = super::Apartment::new()?;
    let properties = session(&bus)?
        .TryGetMediaPropertiesAsync()
        .and_then(|op| op.get())
        .map_err(|e| e.to_string())?;
    let Ok(reference) = properties.Thumbnail() else {
        return Ok(None);
    };
    let stream = reference
        .OpenReadAsync()
        .and_then(|op| op.get())
        .map_err(|e| e.to_string())?;
    let length = stream.Size().map_err(|e| e.to_string())?;
    if length == 0 || length > 5_000_000 {
        return Ok(None);
    }
    let buffer = Buffer::Create(length as u32).map_err(|e| e.to_string())?;
    let buffer = stream
        .ReadAsync(&buffer, length as u32, InputStreamOptions::None)
        .and_then(|op| op.get())
        .map_err(|e| e.to_string())?;
    let mut bytes = vec![0; buffer.Length().map_err(|e| e.to_string())? as usize];
    DataReader::FromBuffer(&buffer)
        .and_then(|r| r.ReadBytes(&mut bytes))
        .map_err(|e| e.to_string())?;
    let mime = if bytes.starts_with(b"\x89PNG\r\n\x1a\n") {
        "image/png"
    } else if bytes.starts_with(&[0xff, 0xd8, 0xff]) {
        "image/jpeg"
    } else {
        return Ok(None);
    };
    Ok(Some(format!(
        "data:{mime};base64,{}",
        base64::engine::general_purpose::STANDARD.encode(bytes)
    )))
}

fn identity_counts<'a>(
    ids: impl Iterator<Item = &'a str>,
) -> std::collections::HashMap<String, usize> {
    let mut counts = std::collections::HashMap::new();
    for id in ids {
        *counts.entry(id.to_owned()).or_insert(0) += 1;
    }
    counts
}
fn sampled_position(
    position: f64,
    duration: f64,
    updated: f64,
    now: f64,
    playing: bool,
    rate: f64,
) -> f64 {
    let elapsed = if playing && updated > 0.0 {
        (now - updated).max(0.0)
    } else {
        0.0
    };
    let position = (position + elapsed * rate).max(0.0);
    if duration > 0.0 {
        position.min(duration)
    } else {
        position
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn smtc_positions_extrapolate_only_playing_and_stay_in_track_bounds() {
        assert_eq!(
            sampled_position(10.0, 120.0, 1000.0, 1005.0, true, 2.0),
            20.0
        );
        assert_eq!(
            sampled_position(10.0, 120.0, 1000.0, 1005.0, false, 2.0),
            10.0
        );
        assert_eq!(
            sampled_position(118.0, 120.0, 1000.0, 1005.0, true, 1.0),
            120.0
        );
        assert_eq!(
            sampled_position(10.0, 120.0, 1006.0, 1005.0, true, 1.0),
            10.0
        );
        assert_eq!(sampled_position(-2.0, 120.0, 0.0, 1005.0, true, 1.0), 0.0);
    }
    #[test]
    fn raw_identity_duplicates_are_ambiguous_before_metadata_reads() {
        let counts = identity_counts(["Spotify.exe", "browser", "browser"].into_iter());
        assert_eq!(counts["Spotify.exe"], 1);
        assert_eq!(counts["browser"], 2);
    }
}
