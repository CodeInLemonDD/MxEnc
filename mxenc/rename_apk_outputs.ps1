# Rename and Organize Existing APKs Script
# Usage: ./rename_apk_outputs.ps1

$ErrorActionPreference = "Stop"

# Paths
$ProjectRoot = "C:\Users\17993\Projects\MxEnc-Alpha-2.0.0\mxenc"
$PubspecPath = Join-Path $ProjectRoot "pubspec.yaml"
$OutputDir = "C:\Users\17993\Projects\MxEnc-Alpha-2.0.0\mxenc\build\app\outputs\flutter-apk"
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

# 2. Prepare Release Directory
if (-not (Test-Path $ReleaseDir)) {
    New-Item -ItemType Directory -Path $ReleaseDir | Out-Null
}

# 3. Rename and Copy Files
$Mappings = @{
    "app-armeabi-v7a-release.apk" = "[老旧手机]猫鸮加密-$Version-armeabi-v7a-release.apk"
    "app-arm64-v8a-release.apk"   = "[普通手机]猫鸮加密-$Version-arm64-v8a-release.apk"
    "app-x86_64-release.apk"      = "[特殊设备]猫鸮加密-$Version-x86_64-release.apk"
}

Write-Host "`n--- Processing APKs from: $OutputDir ---"

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
Write-Host "Files have been copied and renamed to: $ReleaseDir"
Invoke-Item $ReleaseDir
