//! Standalone acceptance runner. Never packaged in Afterglow.
//! Uses the real updater, signatures and installers; only the window runtime is headless.
use std::{fs, path::PathBuf, time::Duration};
use tauri_plugin_updater::UpdaterExt;

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let args: Vec<String> = std::env::args().collect();
    assert_eq!(args.len(), 7, "CONFIG CURRENT_VERSION LOOPBACK_FEED DESTINATION MODE REPORT");
    let source: serde_json::Value = serde_json::from_slice(&fs::read(&args[1])?)?;
    let endpoint = args[3].parse::<tauri::Url>()?;
    assert_eq!(endpoint.scheme(), "http");
    assert_eq!(endpoint.host_str(), Some("127.0.0.1"), "Test transport is loopback-only");
    let mut context = tauri::test::mock_context(tauri::test::noop_assets());
    context.package_info_mut().name = "Afterglow".into();
    context.package_info_mut().version = args[2].parse()?;
    context.config_mut().identifier = source["identifier"].as_str().unwrap().into();
    context.config_mut().plugins.0.insert("updater".into(), serde_json::json!({
        "pubkey": source["plugins"]["updater"]["pubkey"],
        "requireSignedVersion": true,
        "dangerousInsecureTransportProtocol": true,
        "windows": {"installMode":"passive"}
    }));
    let app = tauri::test::mock_builder()
        .plugin(tauri_plugin_updater::Builder::new().build())
        .build(context)?;
    tauri::async_runtime::block_on(async {
        let updater = app.updater_builder().endpoints(vec![endpoint])?
            .timeout(Duration::from_secs(30)).no_proxy()
            .executable_path(PathBuf::from(&args[4]))
            .restart_after_install(false)
            .installer_arg(format!("/D={}", PathBuf::from(&args[4]).parent().unwrap().display()))
            .build()?;
        let result = updater.check().await;
        if args[5] == "reject" {
            let rejected = match result {
                Err(_) => true,
                Ok(Some(update)) => update.download(|_, _| {}, || {}).await.is_err(),
                Ok(None) => false,
            };
            assert!(rejected, "Invalid signature/offline request must fail closed");
            fs::write(&args[6], b"{\"rejected\":true}")?;
            return Ok::<_, Box<dyn std::error::Error>>(());
        }
        let update = result?;
        if args[5] == "none" {
            assert!(update.is_none(), "Equal and older versions must not be offered");
            fs::write(&args[6], b"{\"no_update\":true}")?;
            return Ok(());
        }
        let update = update.expect("Newer signed release must be offered");
        let bytes = update.download(|_, _| {}, || {}).await?;
        update.verify(&bytes)?;
        let mut corrupted = bytes.clone();
        corrupted[0] ^= 1;
        assert!(update.verify(&corrupted).is_err(), "Modified payload must fail verification");
        fs::write(&args[6], serde_json::to_vec(&serde_json::json!({
            "version": update.version, "download_verified": true, "tamper_rejected": true
        }))?)?;
        if args[5] == "install" {
            update.install(bytes)?; // Windows exits after handing off to the real NSIS installer.
        } else if args[5] == "install-fail" {
            assert!(update.install(bytes).is_err(), "Read-only destination must reject installation");
        } else {
            assert_eq!(args[5], "verify");
        }
        Ok(())
    })
}
