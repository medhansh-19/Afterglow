use serde::{Deserialize, Serialize};

#[derive(Clone, Debug, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Snapshot {
    pub bus: String,
    pub identity: String,
    pub title: String,
    pub artist: String,
    pub album: String,
    pub duration: f64,
    pub position: f64,
    pub playing: bool,
    pub rate: f64,
    pub artwork: Option<String>,
    pub can_seek: bool,
}

#[cfg(target_os = "linux")]
pub fn players(selected: Option<String>) -> Result<Vec<Snapshot>, String> {
    use mpris::{PlaybackStatus, PlayerFinder};
    let finder = PlayerFinder::new().map_err(|e| e.to_string())?;
    let mut output = Vec::new();
    for player in finder.find_all().map_err(|e| e.to_string())? {
        if selected.as_ref().is_some_and(|s| s != player.bus_name()) {
            continue;
        }
        let Ok(metadata) = player.get_metadata() else {
            continue;
        };
        let duration = metadata.length().map(|x| x.as_secs_f64()).unwrap_or(0.0);
        output.push(Snapshot {
            bus: player.bus_name().into(),
            identity: player.identity().into(),
            title: metadata.title().unwrap_or("").into(),
            artist: metadata.artists().unwrap_or_default().join(", "),
            album: metadata.album_name().unwrap_or("").into(),
            duration,
            position: player
                .get_position()
                .map(|p| p.as_secs_f64())
                .unwrap_or(0.0),
            playing: player.get_playback_status().ok() == Some(PlaybackStatus::Playing),
            rate: player.get_playback_rate().unwrap_or(1.0),
            artwork: metadata.art_url().map(str::to_owned),
            can_seek: player.can_seek().unwrap_or(false),
        });
    }
    Ok(output)
}

#[cfg(target_os = "linux")]
pub fn control(bus: String, action: String, position: Option<f64>) -> Result<(), String> {
    use mpris::PlayerFinder;
    let finder = PlayerFinder::new().map_err(|e| e.to_string())?;
    let player = finder
        .find_all()
        .map_err(|e| e.to_string())?
        .into_iter()
        .find(|p| p.bus_name() == bus)
        .ok_or("This player has disconnected.")?;
    let result = match action.as_str() {
        "toggle" => player.play_pause(),
        "next" => player.next(),
        "previous" => player.previous(),
        "stop" => player.stop(),
        "seek" => {
            let p = position
                .filter(|p| p.is_finite() && *p >= 0.0 && *p <= 86400.0)
                .ok_or("Invalid position.")?;
            let track_id = player
                .get_metadata()
                .map_err(|e| e.to_string())?
                .track_id()
                .ok_or("No active track.")?;
            player.set_position(track_id, &std::time::Duration::from_secs_f64(p))
        }
        _ => return Err("Unknown player command.".into()),
    };
    result.map_err(|e| e.to_string())
}

#[cfg(not(any(target_os = "linux", target_os = "windows")))]
pub fn players(_: Option<String>) -> Result<Vec<Snapshot>, String> {
    Err("Player integration requires Linux. Use the silent demo to preview the interface.".into())
}
#[cfg(not(any(target_os = "linux", target_os = "windows")))]
pub fn control(_: String, _: String, _: Option<f64>) -> Result<(), String> {
    Err("MPRIS requires Linux.".into())
}

#[cfg(all(test, target_os = "linux"))]
mod tests {
    use super::*;
    #[test]
    #[ignore = "requires the real D-Bus fixture started by linux/tests/mpris.sh"]
    fn backend_mpris() {
        let bus = "org.mpris.MediaPlayer2.AfterglowFixture".to_owned();
        let first = players(Some(bus.clone())).unwrap().remove(0);
        assert_eq!(first.title, "Fixture Song");
        assert_eq!(first.artist, "Fixture Artist");
        assert_eq!(first.duration, 120.0);
        assert!(!first.playing);
        control(bus.clone(), "toggle".into(), None).unwrap();
        assert!(players(Some(bus.clone())).unwrap()[0].playing);
        control(bus.clone(), "seek".into(), Some(42.5)).unwrap();
        assert_eq!(players(Some(bus.clone())).unwrap()[0].position, 42.5);
        control(bus.clone(), "next".into(), None).unwrap();
        assert_eq!(
            players(Some(bus.clone())).unwrap()[0].title,
            "Next Fixture Song"
        );
        control(bus.clone(), "previous".into(), None).unwrap();
        assert_eq!(players(Some(bus.clone())).unwrap()[0].title, "Fixture Song");
        control(bus.clone(), "stop".into(), None).unwrap();
        assert_eq!(players(Some(bus.clone())).unwrap()[0].position, 0.0);
        assert!(control(bus.clone(), "seek".into(), Some(f64::NAN)).is_err());
        assert!(control(bus, "not-an-action".into(), None).is_err());
    }
}

#[cfg(target_os = "windows")]
pub use crate::windows::player::{control, players};
