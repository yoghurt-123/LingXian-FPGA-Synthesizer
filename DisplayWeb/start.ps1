$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $root

if (-not (Test-Path (Join-Path $root "dist\index.html"))) {
    Write-Host "dist/index.html not found."
    Write-Host "Run: npm install; npm run build"
    exit 1
}

$url = "http://127.0.0.1:5173/"
$server = Start-Process -FilePath "node" -ArgumentList @(
    (Join-Path $root "server.mjs"),
    (Join-Path $root "dist")
) -WorkingDirectory $root -PassThru -WindowStyle Hidden

Start-Sleep -Milliseconds 900
Write-Host "AURAL instrument display: $url"
Start-Process $url
Write-Host "Server process: $($server.Id). Close this window to stop the server."
Wait-Process -Id $server.Id
