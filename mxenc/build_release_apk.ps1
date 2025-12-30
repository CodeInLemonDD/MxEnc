# Build and Rename Script for Android APKs
# Usage: ./build_release_apk.ps1

$ErrorActionPreference = "Stop"
$ProjectRoot = Get-Location
$PubspecPath = Join-Path $ProjectRoot "pubspec.yaml"
$OutputDir = Join-Path $ProjectRoot "build/app/outputs/flutter-apk"
$ReleaseDir = Join-Path $ProjectRoot "release"

# 1. Extract Version from pubspec.yaml
if (-not (Test-Path $PubspecPath)) {
    Write-Error "pubspec.yaml not found at $PubspecPath"
    exit 1
}

$PubspecContent = Get-Content $PubspecPath -Raw
if ($PubspecContent -match "version:\s*([\d\.]+)") {
    $Version = $matches[1]
    Write-Host "Detected Version: $Version"
} else {
    Write-Error "Could not parse version from pubspec.yaml"
    exit 1
}

# 2. Run Flutter Build
Write-Host "`n--- Starting Flutter Build (Split per ABI) ---"
flutter build apk --split-per-abi

if ($LASTEXITCODE -ne 0) {
    Write-Error "Flutter build failed."
    exit 1
}

# 3. Rename and Move Files
if (-not (Test-Path $ReleaseDir)) {
    New-Item -ItemType Directory -Path $ReleaseDir | Out-Null
}

$Mappings = @{
    "app-armeabi-v7a-release.apk" = "[老旧手机]猫鸮加密-$Version-armeabi-v7a-release.apk"
    "app-arm64-v8a-release.apk"   = "[普通手机]猫鸮加密-$Version-arm64-v8a-release.apk"
    "app-x86_64-release.apk"      = "[特殊设备]猫鸮加密-$Version-x86_64-release.apk"
}

Write-Host "`n--- Processing Output Files ---"

foreach ($Key in $Mappings.Keys) {
    $SourcePath = Join-Path $OutputDir $Key
    $TargetName = $Mappings[$Key]
    $DestPath = Join-Path $ReleaseDir $TargetName

    if (Test-Path $SourcePath) {
        Copy-Item -Path $SourcePath -Destination $DestPath -Force
        Write-Host "Success: $TargetName"
    } else {
        Write-Warning "File not found: $Key"
    }
}

Write-Host "`n--- All Done! ---"
Write-Host "Release files are in: $ReleaseDir"
Invoke-Item $ReleaseDir
