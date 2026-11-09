pub mod desktop;
pub mod player;
pub mod power;
pub mod shortcuts;
pub mod storage;

/// Each blocking worker initializes its own COM apartment; do not uninitialize an
/// apartment owned by Tauri or a preceding user of the thread.
pub struct Apartment(bool);
impl Apartment {
    pub fn new() -> Result<Self, String> {
        use windows::Win32::System::WinRT::{RoInitialize, RO_INIT_MULTITHREADED};
        let result = unsafe { RoInitialize(RO_INIT_MULTITHREADED) };
        match result { Ok(()) => Ok(Self(true)), Err(error) => Err(format!("Windows runtime initialization failed: {error}")) }
    }
}
impl Drop for Apartment {
    fn drop(&mut self) {
        if self.0 { unsafe { windows::Win32::System::WinRT::RoUninitialize() } }
    }
}
