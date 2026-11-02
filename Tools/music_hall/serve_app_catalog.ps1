param(
    [string[]]$Packs = @(),
    [int]$Port = 8080,
    [string]$BindAddress = ""
)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.IO.Compression.FileSystem

$root = Resolve-Path (Join-Path $PSScriptRoot "..\..")
if ($Packs.Count -eq 0) {
    $Packs = @(Get-ChildItem -LiteralPath (Join-Path $root "music_packs") -Filter *.fpgasong |
        Select-Object -ExpandProperty FullName)
}
if ($Packs.Count -eq 0) {
    throw "No .fpgasong packs found. Pass -Packs explicitly."
}

if ([string]::IsNullOrWhiteSpace($BindAddress)) {
    $BindAddress = ([System.Net.Dns]::GetHostAddresses([System.Net.Dns]::GetHostName()) |
        Where-Object { $_.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetwork -and
            -not $_.IPAddressToString.StartsWith("127.") } |
        Select-Object -First 1 -ExpandProperty IPAddressToString)
    if ([string]::IsNullOrWhiteSpace($BindAddress)) { $BindAddress = "127.0.0.1" }
}

$serve = Join-Path $root "music_packs\music_hall_serve"
$packServe = Join-Path $serve "packs"
New-Item -ItemType Directory -Path $packServe -Force | Out-Null
Get-ChildItem -LiteralPath $packServe -Filter *.fpgasong -ErrorAction SilentlyContinue |
    Remove-Item -Force

$songs = @()
foreach ($pack in $Packs) {
    $pack = (Resolve-Path -LiteralPath $pack).Path
    $zip = [System.IO.Compression.ZipFile]::OpenRead($pack)
    try {
        $manifestEntry = $zip.GetEntry("manifest.json")
        if ($null -eq $manifestEntry) { throw "manifest.json missing in $pack" }
        $reader = New-Object System.IO.StreamReader($manifestEntry.Open(), [System.Text.Encoding]::UTF8)
        try { $manifest = $reader.ReadToEnd() | ConvertFrom-Json }
        finally { $reader.Dispose() }

        $score = $null
        $scoreEntry = $zip.GetEntry("score.json")
        if ($null -ne $scoreEntry) {
            $scoreReader = New-Object System.IO.StreamReader($scoreEntry.Open(), [System.Text.Encoding]::UTF8)
            try { $score = $scoreReader.ReadToEnd() | ConvertFrom-Json }
            finally { $scoreReader.Dispose() }
        }
    } finally {
        $zip.Dispose()
    }

    $hash = (Get-FileHash -LiteralPath $pack -Algorithm SHA256).Hash
    $safeId = ($manifest.song_id -replace '[^A-Za-z0-9._-]', '_')
    if ([string]::IsNullOrWhiteSpace($safeId)) { $safeId = "song-$($hash.Substring(0,8))" }
    $fileName = "$safeId.fpgasong"
    Copy-Item -LiteralPath $pack -Destination (Join-Path $packServe $fileName) -Force
    $duration = 0
    if ($null -ne $manifest.verification -and $null -ne $manifest.verification.duration_seconds) {
        $duration = [double]$manifest.verification.duration_seconds
    }
    $sourceName = "本地测试包"
    $sourceUrl = $null
    $license = $null
    $arrangement = $null
    if ($null -ne $score -and $null -ne $score.source) {
        if ($null -ne $score.source.name) { $sourceName = $score.source.name }
        if ($null -ne $score.source.url) { $sourceUrl = $score.source.url }
        if ($null -ne $score.source.license) { $license = $score.source.license }
        if ($null -ne $score.source.note) { $arrangement = $score.source.note }
    }
    $songs += [ordered]@{
        song_id = [string]$manifest.song_id
        title = [string]$manifest.title
        artist = [string]$manifest.composer
        duration_seconds = $duration
        source_name = $sourceName
        source_url = $sourceUrl
        license = $license
        license_url = $null
        arrangement = $arrangement
        cover_url = $null
        pack_url = "http://${BindAddress}:$Port/packs/$fileName"
        pack_bytes = (Get-Item -LiteralPath (Join-Path $packServe $fileName)).Length
        pack_sha256 = $hash
        format_version = [string]$manifest.format_version
        required_capabilities = @($manifest.capabilities_required)
    }
}

$catalog = [ordered]@{
    schema_version = "0.1"
    generated_at = (Get-Date).ToString("o")
    songs = $songs
}
$catalogPath = Join-Path $serve "catalog.json"
$json = $catalog | ConvertTo-Json -Depth 8
[System.IO.File]::WriteAllText($catalogPath, $json, (New-Object System.Text.UTF8Encoding($false)))

$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://${BindAddress}:$Port/")
try {
    $listener.Start()
} catch {
    throw "HTTP listener failed for http://${BindAddress}:$Port/. Use another -BindAddress/-Port or grant URL ACL. $($_.Exception.Message)"
}

Write-Host "Music hall catalog: http://${BindAddress}:$Port/catalog.json"
Write-Host "Packs: $(Join-Path $serve 'packs')"
Write-Host "Stop with Ctrl+C. If iPad ATS blocks cleartext HTTP, use Files import or an HTTPS test server."

try {
    while ($listener.IsListening) {
        $context = $listener.GetContext()
        $path = $context.Request.Url.AbsolutePath
        $status = 404
        $contentType = "text/plain; charset=utf-8"
        $bytes = [System.Text.Encoding]::UTF8.GetBytes("not found")
        if ($path -eq "/catalog.json") {
            $bytes = [System.IO.File]::ReadAllBytes($catalogPath)
            $contentType = "application/json; charset=utf-8"
            $status = 200
        } elseif ($path.StartsWith("/packs/")) {
            $name = [System.IO.Path]::GetFileName($path)
            $file = Join-Path $packServe $name
            if (Test-Path -LiteralPath $file -PathType Leaf) {
                $bytes = [System.IO.File]::ReadAllBytes($file)
                $contentType = "application/octet-stream"
                $status = 200
            }
        }
        $context.Response.StatusCode = $status
        $context.Response.ContentType = $contentType
        $context.Response.ContentLength64 = $bytes.Length
        $context.Response.OutputStream.Write($bytes, 0, $bytes.Length)
        $context.Response.Close()
    }
} finally {
    $listener.Stop()
    $listener.Close()
}
