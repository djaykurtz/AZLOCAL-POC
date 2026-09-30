<#
.SYNOPSIS
    Bundles the capstone presentation into one self-contained HTML file.

.DESCRIPTION
    Inlines every stylesheet, script and image the deck loads, preserving the load order declared
    in the source document. The result opens from a file path, a USB stick or any static host with
    no server and no network.

    One quirk is handled explicitly. intro.js locates the media folder through
    document.currentScript.src, which is null for an inline script, so the bundler neutralises that
    lookup and swaps the image file names for the data URIs it just built.

.EXAMPLE
    .\scripts\Build-CapstoneSingleFile.ps1
    .\scripts\Build-CapstoneSingleFile.ps1 -Open
#>
[CmdletBinding()]
param(
    [string] $Source  = 'capstone/prototype/v2/index.html',
    [string] $MediaDir = 'capstone/media',
    [string] $OutFile = 'out/capstone-presentation.html',
    [switch] $Open
)

$ErrorActionPreference = 'Stop'

$repo = Split-Path -Parent $PSScriptRoot
function Resolve-RepoPath([string] $p) { Join-Path $repo $p }

$srcPath = Resolve-RepoPath $Source
if (-not (Test-Path $srcPath)) { throw "Source document not found: $srcPath" }
$srcDir = Split-Path -Parent $srcPath

$html = [IO.File]::ReadAllText($srcPath)

# ---------------------------------------------------------------- media as data URIs
$mime = @{ '.png' = 'image/png'; '.jpg' = 'image/jpeg'; '.jpeg' = 'image/jpeg'
           '.gif' = 'image/gif'; '.webp' = 'image/webp'; '.svg' = 'image/svg+xml' }

$dataUri = @{}
$mediaPath = Resolve-RepoPath $MediaDir
if (Test-Path $mediaPath) {
    Get-ChildItem $mediaPath -File | Where-Object { $mime.ContainsKey($_.Extension.ToLower()) } | ForEach-Object {
        $b64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($_.FullName))
        $dataUri[$_.Name] = 'data:' + $mime[$_.Extension.ToLower()] + ';base64,' + $b64
    }
}

# ---------------------------------------------------------------- helpers
function Read-Asset([string] $ref) {
    $p = if ([IO.Path]::IsPathRooted($ref)) { $ref } else { Join-Path $srcDir $ref }
    $p = [IO.Path]::GetFullPath($p)
    if (-not (Test-Path $p)) { throw "Referenced asset missing: $ref" }
    [IO.File]::ReadAllText($p)
}

# Only the deck's own image names are swapped, so unrelated strings are left alone.
function Expand-Media([string] $text) {
    foreach ($name in $dataUri.Keys) {
        if ($text.Contains($name)) { $text = $text.Replace("'$name'", "'$($dataUri[$name])'") }
    }
    $text
}

$inlined = [System.Collections.Generic.List[string]]::new()

# ---------------------------------------------------------------- stylesheets
foreach ($m in [regex]::Matches($html, '<link[^>]*rel="stylesheet"[^>]*href="([^"]+)"[^>]*>')) {
    $ref = $m.Groups[1].Value
    $css = Expand-Media (Read-Asset $ref)
    $css = $css.Replace('</style', '<\/style')
    $html = $html.Replace($m.Value, "<style>`n/* $ref */`n$css`n</style>")
    $inlined.Add(('css  {0,-22} {1,7:N0} KB' -f $ref, ($css.Length / 1KB)))
}

# ---------------------------------------------------------------- scripts, in declared order
foreach ($m in [regex]::Matches($html, '<script[^>]*src="([^"]+)"[^>]*>\s*</script>')) {
    $ref = $m.Groups[1].Value
    $js  = Read-Asset $ref

    # An inline script has no .src, so this lookup would fall back to the document location.
    $js = [regex]::Replace($js, "const MEDIA = new URL\([\s\S]*?\)\.href;", { "const MEDIA = '';" })

    $js = Expand-Media $js
    $js = $js.Replace('</script', '<\/script')
    $html = $html.Replace($m.Value, "<script>`n/* $ref */`n$js`n</script>")
    $inlined.Add(('js   {0,-22} {1,7:N0} KB' -f $ref, ($js.Length / 1KB)))
}

# ---------------------------------------------------------------- write
$outPath = Resolve-RepoPath $OutFile
$outDir  = Split-Path -Parent $outPath
if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }
[IO.File]::WriteAllText($outPath, $html, [Text.UTF8Encoding]::new($false))

$inlined | ForEach-Object { Write-Host "  $_" }
Write-Host ''
Write-Host ('  images inlined  {0}' -f $dataUri.Count)
Write-Host ('  remaining refs  {0}' -f ([regex]::Matches($html, '(?:src|href)="(?!#|data:|https?:|mailto:)[^"]+"').Count))
Write-Host ('  output          {0}  ({1:N0} KB)' -f $OutFile, ((Get-Item $outPath).Length / 1KB))

if ($Open) { Start-Process $outPath }
