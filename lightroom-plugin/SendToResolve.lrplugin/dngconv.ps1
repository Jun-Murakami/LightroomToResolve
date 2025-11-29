param (
    [Parameter(Mandatory = $true)]
    [string]$SourceRaw
)

$ErrorActionPreference = "Stop"

$defaultLog = Join-Path $env:APPDATA "LightroomToResolve\dngconv.log"
New-Item -ItemType Directory -Path (Split-Path $defaultLog -Parent) -Force | Out-Null
"[{0}] Script started" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss") | Out-File -FilePath $defaultLog -Encoding UTF8 -Append

$configPath = Join-Path $PSScriptRoot "dngconv.config.json"
if (-not (Test-Path $configPath)) {
    "Config file not found: $configPath" | Out-File -FilePath $defaultLog -Append
    throw "Config file not found: $configPath"
}

$config = Get-Content $configPath -Raw | ConvertFrom-Json
$logFile = $config.logFile
if ([string]::IsNullOrWhiteSpace($logFile)) {
    $logFile = $defaultLog
} else {
    $logFile = [Environment]::ExpandEnvironmentVariables($logFile)
    New-Item -ItemType Directory -Path (Split-Path $logFile -Parent) -Force | Out-Null
}

if ($logFile -ne $defaultLog) {
    Get-Content $defaultLog | Out-File -FilePath $logFile -Encoding UTF8 -Append
    Remove-Item $defaultLog -Force
}

$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
"[$timestamp] Config loaded from $configPath" | Out-File -FilePath $logFile -Encoding UTF8 -Append

$converter = $config.dngConverter
if (-not (Test-Path $converter)) {
    "[$timestamp] Converter not found: $converter" | Out-File -FilePath $logFile -Append -Encoding UTF8
    throw "Adobe DNG Converter not found: $converter"
}

"[$timestamp] Start conversion for $SourceRaw" | Out-File -FilePath $logFile -Encoding UTF8 -Append

if (-not (Test-Path $SourceRaw)) {
    throw "Source RAW not found: $SourceRaw"
}

$sourceDir = Split-Path $SourceRaw -Parent
$baseName = [System.IO.Path]::GetFileNameWithoutExtension($SourceRaw)
$tempOutput = Join-Path $sourceDir ($baseName + ".dng")
$finalOutput = Join-Path $sourceDir ($baseName + "_2d.dng")

if (Test-Path $tempOutput) { Remove-Item $tempOutput -Force }
if (Test-Path $finalOutput) { Remove-Item $finalOutput -Force }

$arguments = @("-c", "-d", $sourceDir, $SourceRaw)

$process = Start-Process -FilePath $converter -ArgumentList $arguments -PassThru -Wait -NoNewWindow

if ($process.ExitCode -ne 0) {
    "[$timestamp] Converter exit code $($process.ExitCode)" | Out-File -FilePath $logFile -Append -Encoding UTF8
    throw "Converter failed with exit code $($process.ExitCode)"
}

if (-not (Test-Path $tempOutput)) {
    "[$timestamp] Output missing: $tempOutput" | Out-File -FilePath $logFile -Append -Encoding UTF8
    throw "Output file not found: $tempOutput"
}

Rename-Item -Path $tempOutput -NewName $finalOutput
"[$timestamp] Converted to $finalOutput" | Out-File -FilePath $logFile -Append -Encoding UTF8

Write-Output $finalOutput