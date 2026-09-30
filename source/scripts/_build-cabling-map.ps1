# Build a labeled cabling-map workbook from the storage-NIC inventory.
# Columns include the Arista-format MAC and blank Switch/Port/VLAN cells to fill in while
# cross-referencing the SW1/SW2 MAC tables. Pre-fills the two mappings already confirmed.
# Writes .xlsx if the ImportExcel module is available; always writes a .csv fallback.

function To-AristaMac([string]$mac) {
  $h = ($mac -replace '[-:]','').ToLower()
  if ($h.Length -ne 12) { return $mac }
  '{0}.{1}.{2}' -f $h.Substring(0,4), $h.Substring(4,4), $h.Substring(8,4)
}

# Confirmed mappings so far (from switch MAC tables):
#   node01 Port4 (00-00-5E-00-53-06) -> SW1 Et9/1  VLAN 711
#   node02 Port3 (00-00-5E-00-53-03) -> SW1 Et10/1 VLAN 711
$confirmed = @{
  'AZL-NODE-01|Port4' = @('SW1','Et9/1','711','confirmed via MAC table 2026-07-27')
  'AZL-NODE-02|Port3' = @('SW1','Et10/1','711','confirmed via MAC table 2026-07-27')
}

# Expected switch port per node number (both switches use the same port number per node):
$portByNode = @{ '01'='Et9/1'; '02'='Et10/1'; '03'='Et11/1'; '04'='Et12/1'; '05'='Et13/1'; '06'='Et14/1' }

$src = Import-Csv .\out\_storage-nic-inventory.csv
$rows = foreach ($r in $src) {
  $key = "$($r.Node)|$($r.Adapter)"
  $numMatch = [regex]::Match($r.Node,'(\d\d)$')
  $expPort  = if ($numMatch.Success) { $portByNode[$numMatch.Groups[1].Value] } else { '' }
  $c = $confirmed[$key]
  [pscustomobject]@{
    Node          = $r.Node
    'Win Adapter' = $r.Adapter
    'MAC (Windows)' = $r.MAC
    'MAC (Arista)'  = (To-AristaMac $r.MAC)
    Status        = $r.Status
    'Link Speed'  = $r.Speed
    'Switch (fill)'      = if ($c) { $c[0] } else { '' }
    'Switch Port (fill)' = if ($c) { $c[1] } else { $expPort + ' (verify)' }
    'VLAN (fill)'        = if ($c) { $c[2] } else { '' }
    'Intended VLAN per ATC' = if ($r.Adapter -eq 'Port3') { '711 (StorageNetwork1)' } else { '712 (StorageNetwork2)' }
    Notes         = if ($c) { $c[3] } else { '' }
  }
}

$csv = '.\out\_cabling-map.csv'
$rows | Export-Csv $csv -NoTypeInformation
Write-Host "Wrote $csv"

$xlsx = '.\out\_cabling-map.xlsx'
if (Get-Module -ListAvailable -Name ImportExcel) {
  Import-Module ImportExcel
  if (Test-Path $xlsx) { Remove-Item $xlsx -Force }
  $rows | Export-Excel -Path $xlsx -WorksheetName 'CablingMap' -AutoSize -FreezeTopRow -BoldTopRow -AutoFilter
  Write-Host "Wrote $xlsx (native Excel)"
} else {
  Write-Host "ImportExcel module not installed -> only CSV written."
  Write-Host "The CSV opens directly in Excel. To also get a native .xlsx, run:  Install-Module ImportExcel -Scope CurrentUser"
}

Write-Host ""
$rows | Format-Table Node,'Win Adapter','MAC (Windows)','MAC (Arista)','Switch (fill)','Switch Port (fill)','VLAN (fill)','Intended VLAN per ATC' -AutoSize
