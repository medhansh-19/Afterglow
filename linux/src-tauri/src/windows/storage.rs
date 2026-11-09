use std::{os::windows::ffi::OsStrExt, path::Path};
use windows::{core::PCWSTR, Win32::Storage::FileSystem::{MoveFileExW, MOVEFILE_REPLACE_EXISTING, MOVEFILE_WRITE_THROUGH}};

/// Replace the existing file in one same-volume operation. Unlike rename on
/// Windows, this also supports the second and subsequent preference saves.
pub fn replace(temporary: &Path, destination: &Path) -> Result<(), String> {
    let source: Vec<u16> = temporary.as_os_str().encode_wide().chain(Some(0)).collect();
    let target: Vec<u16> = destination.as_os_str().encode_wide().chain(Some(0)).collect();
    unsafe { MoveFileExW(PCWSTR(source.as_ptr()), PCWSTR(target.as_ptr()), MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH) }.map_err(|e| e.to_string())
}
