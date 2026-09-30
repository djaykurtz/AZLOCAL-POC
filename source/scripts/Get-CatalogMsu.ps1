<#
.SYNOPSIS
  Download a specific Microsoft Update Catalog MSU by KB + title filter.
.DESCRIPTION
  Scrapes catalog.update.microsoft.com: search -> find the row whose title
  matches -TitleLike -> resolve the real download URL via DownloadDialog.aspx
  -> download to -OutDir. No WUA/second-hop involved (plain HTTPS GET).
.EXAMPLE
  .\Get-CatalogMsu.ps1 -Kb KB5082417 -TitleLike 'server operating system version 24H2 for x64' -OutDir .\out\msu
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$Kb,
  [Parameter(Mandatory)][string]$TitleLike,
  [string]$OutDir = (Join-Path $PSScriptRoot '..\out\msu')
)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
New-Item -ItemType Directory -Path $OutDir -Force | Out-Null

Write-Host "[*] Searching catalog for $Kb ..." -ForegroundColor Cyan
$searchUrl = "https://www.catalog.update.microsoft.com/Search.aspx?q=$Kb"
$resp = Invoke-WebRequest -Uri $searchUrl -UseBasicParsing

# Each result row: <tr id="<GUID>_RXX" ...> ... goToDetails("<GUID>") ... title text ...
# The download button data lives in a JS array keyed by the GUID. Parse rows.
$rows = [regex]::Matches($resp.Content, '(?s)<tr[^>]*id="([0-9a-fA-F\-]{36})_R\d+".*?</tr>')
if ($rows.Count -eq 0) { throw "No result rows parsed for $Kb." }

$match = $null
foreach ($r in $rows) {
  $guid = $r.Groups[1].Value
  $block = $r.Value
  # title is in a <a ...>TITLE</a> within the row
  $titleM = [regex]::Match($block, '(?s)goToDetails[^>]*>\s*(.*?)\s*</a>')
  $title = if ($titleM.Success) { ($titleM.Groups[1].Value -replace '\s+',' ').Trim() } else { '' }
  if ($title -like "*$TitleLike*") { $match = [pscustomobject]@{ Guid=$guid; Title=$title }; break }
}
if (-not $match) {
  Write-Host "    Rows found but none matched '$TitleLike'. Available titles:" -ForegroundColor Yellow
  foreach ($r in $rows) {
    $block=$r.Value; $tm=[regex]::Match($block,'(?s)goToDetails[^>]*>\s*(.*?)\s*</a>')
    if($tm.Success){ "      - " + (($tm.Groups[1].Value -replace '\s+',' ').Trim()) }
  }
  throw "No catalog row matched title filter."
}
Write-Host "    Matched: $($match.Title)" -ForegroundColor Green
Write-Host "    GUID:    $($match.Guid)"

Write-Host "[*] Resolving download URL via DownloadDialog ..." -ForegroundColor Cyan
$body = @{ updateIDs = (ConvertTo-Json @(@{ size=0; languages=''; uidInfo=$match.Guid; updateID=$match.Guid }) -Compress) }
$dlg = Invoke-WebRequest -Uri 'https://www.catalog.update.microsoft.com/DownloadDialog.aspx' -Method Post -Body $body -UseBasicParsing
$urls = [regex]::Matches($dlg.Content, "(https?://[^'""]+\.(?:msu|cab))") | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique
if (-not $urls) { throw "DownloadDialog returned no .msu/.cab URL." }

foreach ($u in $urls) {
  $name = Split-Path $u -Leaf
  $out = Join-Path $OutDir $name
  Write-Host "[*] Downloading $name ..." -ForegroundColor Cyan
  Invoke-WebRequest -Uri $u -OutFile $out -UseBasicParsing
  $sz = [math]::Round((Get-Item $out).Length/1MB,1)
  Write-Host "    Saved: $out ($sz MB)" -ForegroundColor Green
}
Write-Host "[*] Done." -ForegroundColor Cyan
