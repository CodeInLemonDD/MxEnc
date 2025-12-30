# Android Rust Build Script
# Usage: ./build_android.ps1

$RustProjectRoot = "rust_core"
$JniLibsDir = "android/app/src/main/jniLibs"

# Ensure cargo-ndk is installed
if (-not (Get-Command cargo-ndk -ErrorAction SilentlyContinue)) {
    Write-Host "Installing cargo-ndk..."
    cargo install cargo-ndk
}

# Define targets
$Targets = @(
    @{ Arch = "aarch64-linux-android"; Abi = "arm64-v8a" },
    @{ Arch = "armv7-linux-androideabi"; Abi = "armeabi-v7a" },
    @{ Arch = "x86_64-linux-android"; Abi = "x86_64" }
)

Push-Location $RustProjectRoot

foreach ($Target in $Targets) {
    $Arch = $Target.Arch
    $Abi = $Target.Abi
    
    Write-Host "`n--- Building for $Abi ($Arch) ---"
    
    # Build using cargo-ndk
    # Note: We don't use -o here because we want to control the copy process manually to be safe
    # But cargo-ndk -o is actually very convenient. Let's try to use it directly to the target folder.
    
    cargo ndk -t $Arch -o ../$JniLibsDir build --release
    
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Build failed for $Abi"
        Pop-Location
        exit 1
    }
}

Pop-Location

Write-Host "`n--- Android Build Complete ---"
Write-Host "Libraries placed in: $JniLibsDir"
