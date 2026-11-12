param([ValidateSet('baseline','balanced','size')][string]$NativeProfile = 'baseline')
$settings = @{
    CARGO_PROFILE_RELEASE_LTO = $null
    CARGO_PROFILE_RELEASE_CODEGEN_UNITS = $null
    CARGO_PROFILE_RELEASE_STRIP = $null
    CARGO_PROFILE_RELEASE_OPT_LEVEL = $null
}
if ($NativeProfile -ne 'baseline') {
    $settings.CARGO_PROFILE_RELEASE_LTO = if ($NativeProfile -eq 'size') { 'true' } else { 'thin' }
    $settings.CARGO_PROFILE_RELEASE_CODEGEN_UNITS = '1'
    $settings.CARGO_PROFILE_RELEASE_STRIP = 'debuginfo'
    $settings.CARGO_PROFILE_RELEASE_OPT_LEVEL = if ($NativeProfile -eq 'size') { 's' } else { '3' }
}
return $settings
