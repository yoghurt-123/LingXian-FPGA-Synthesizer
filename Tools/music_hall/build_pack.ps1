param(
    [Parameter(Mandatory=$true)][string]$PackDir,
    [Parameter(Mandatory=$true)][string]$Output
)
$ErrorActionPreference = 'Stop'
$root = Resolve-Path $PackDir
node (Join-Path $PSScriptRoot 'build_pack.js') $root
if ($LASTEXITCODE -ne 0) { throw 'build_pack.js failed' }
if (Test-Path $Output) { Remove-Item $Output -Force }
Add-Type -AssemblyName System.IO.Compression.FileSystem
[System.IO.Compression.ZipFile]::CreateFromDirectory($root.Path, (Join-Path (Get-Location) $Output), [System.IO.Compression.CompressionLevel]::Optimal, $false)
Write-Host "wrote $Output"
