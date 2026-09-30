# MAC-driven storage-NIC rename: make Port3 = the SW1/711 port and Port4 = the SW2/712 port on EVERY
# node, so it matches ATC's config (Port3=711, Port4=712). Source of truth = MAC -> switch from the
# LLDP map (out/_lldp-cabling-map.csv). Names are just corrected to match physical reality.
#
# Safe: only touches the two Mellanox storage adapters (mgmt is the separate Broadcom 'Management'
# NIC, so WinRM stays up). Uses temp names to avoid collisions. Idempotent: nodes already correct are
# skipped. Documents original name<->MAC before changing. DRY-RUN by default; pass -Execute to apply.
param([switch]$Execute)

$pw = ConvertTo-SecureString ((Get-Content ".\.creds\azloc-local-admin.cred" -Raw).Trim())
$map = Import-Csv .\out\_lldp-cabling-map.csv    # cols: Node,Adapter,MAC,NeighborSwitch,...
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$logPath = ".\out\_adapter-rename-log-$stamp.csv"

# Build per-node desired state from MAC -> switch (sw1 => Port3, sw2 => Port4)
$byNode = $map | Group-Object Node
$plan = @()
foreach ($g in $byNode) {
  $sw1 = $g.Group | Where-Object NeighborSwitch -eq 'sw1' | Select-Object -First 1
  $sw2 = $g.Group | Where-Object NeighborSwitch -eq 'sw2' | Select-Object -First 1
  if (-not $sw1 -or -not $sw2) { Write-Warning "Node $($g.Name): missing sw1/sw2 mapping, skipping"; continue }
  $plan += [pscustomobject]@{
    Node=$g.Name; sam=$g.Name.ToLower()
    Sw1Mac=$sw1.MAC.ToUpper(); Sw1CurrentName=$sw1.Adapter    # -> should become Port3
    Sw2Mac=$sw2.MAC.ToUpper(); Sw2CurrentName=$sw2.Adapter    # -> should become Port4
    NeedsChange = -not ($sw1.Adapter -eq 'Port3' -and $sw2.Adapter -eq 'Port4')
  }
}

Write-Host "===== RENAME PLAN (MAC is source of truth; SW1/711 port -> Port3, SW2/712 port -> Port4) ====="
$plan | Format-Table Node,Sw1Mac,Sw1CurrentName,Sw2Mac,Sw2CurrentName,NeedsChange -AutoSize
# document original mapping
$plan | Select-Object Node,Sw1Mac,@{n='Sw1OldName';e={$_.Sw1CurrentName}},@{n='Sw1NewName';e={'Port3'}},
                        Sw2Mac,@{n='Sw2OldName';e={$_.Sw2CurrentName}},@{n='Sw2NewName';e={'Port4'}},NeedsChange |
  Export-Csv $logPath -NoTypeInformation
Write-Host "Documented original name<->MAC mapping to $logPath"

if (-not $Execute) {
  Write-Host ""
  Write-Host "DRY-RUN only. Nodes needing change: $(($plan | Where-Object NeedsChange).Node -join ', ')"
  Write-Host "Re-run with -Execute to apply the renames."
  return
}

$renameSb = {
  param($sw1mac,$sw2mac)
  $a1 = Get-NetAdapter | Where-Object { $_.MacAddress.ToUpper() -eq $sw1mac }
  $a2 = Get-NetAdapter | Where-Object { $_.MacAddress.ToUpper() -eq $sw2mac }
  if (-not $a1 -or -not $a2) { return [pscustomobject]@{ Node=$env:COMPUTERNAME; Result='ERROR: adapter MAC not found'; Port3='';Port4='' } }
  # temp names first to avoid collision, then final
  Rename-NetAdapter -Name $a1.Name -NewName '__tmp_p3' -ErrorAction Stop
  Rename-NetAdapter -Name $a2.Name -NewName '__tmp_p4' -ErrorAction Stop
  Rename-NetAdapter -Name '__tmp_p3' -NewName 'Port3' -ErrorAction Stop
  Rename-NetAdapter -Name '__tmp_p4' -NewName 'Port4' -ErrorAction Stop
  $p3 = (Get-NetAdapter -Name Port3).MacAddress
  $p4 = (Get-NetAdapter -Name Port4).MacAddress
  [pscustomobject]@{ Node=$env:COMPUTERNAME; Result='renamed'; Port3=$p3; Port4=$p4 }
}

Write-Host ""
Write-Host "===== EXECUTING RENAMES ====="
foreach ($p in $plan) {
  if (-not $p.NeedsChange) { Write-Host "$($p.Node): already correct, skipping."; continue }
  $cred = [pscredential]::new("$($p.sam)\Administrator",$pw)
  try {
    Invoke-Command "$($p.sam).lab.example.com" -Credential $cred -Authentication Negotiate -ScriptBlock $renameSb -ArgumentList $p.Sw1Mac,$p.Sw2Mac |
      Format-Table Node,Result,Port3,Port4 -AutoSize
  } catch { Write-Warning "$($p.Node): $($_.Exception.Message)" }
}
Write-Host ""
Write-Host "Done. Verify with: & .\scripts\_lldp-cabling-map.ps1  (expect all rows Verdict=OK)."
