# SELF-SERVICE cabling mapper via LLDP - no switch team needed, no MAC-aging race.
# For each node it captures LLDP (EtherType 0x88CC) ~45s, maps pktmon Component -> MAC (pktmon list)
# -> Windows adapter name (Get-NetAdapter), and reads the neighbor switch system name from the LLDP
# payload. Output: per node/port -> which switch (sw1=711, sw2=712) and whether it matches ATC's
# expectation (Port3 should be SW1/711, Port4 should be SW2/712). Mismatches = adapters to rename.
# Arista switches send LLDP ~every 30s, so a 45s capture reliably catches one per port. Read-only.
$pw = ConvertTo-SecureString ((Get-Content ".\.creds\azloc-local-admin.cred" -Raw).Trim())
$nodes = 'azl-node-01','azl-node-02','azl-node-04','azl-node-06'

$probe = {
  $etl = "C:\Windows\Temp\lldpmap.etl"; $txt = "C:\Windows\Temp\lldpmap.txt"
  Remove-Item $etl,$txt -ErrorAction SilentlyContinue
  # component -> MAC (Mellanox only) and adapter-name -> MAC
  $listRaw = & pktmon list 2>&1
  $compMac = @{}
  foreach ($ln in $listRaw) {
    if ($ln -match '^\s*(\d+)\s+([0-9A-Fa-f-]{17})\s+Mellanox') { $compMac[$matches[1]] = $matches[2].ToUpper() }
  }
  $adapters = Get-NetAdapter -Name Port3,Port4 -ErrorAction SilentlyContinue |
              Select-Object Name,@{n='MAC';e={$_.MacAddress.ToUpper()}}
  # capture LLDP
  & pktmon filter remove 2>&1 | Out-Null
  & pktmon filter add LLDP --ethertype 0x88CC 2>&1 | Out-Null
  & pktmon start --capture --pkt-size 0 --file-name $etl 2>&1 | Out-Null
  Start-Sleep -Seconds 45
  & pktmon stop 2>&1 | Out-Null
  & pktmon etl2txt $etl -o $txt 2>&1 | Out-Null
  & pktmon filter remove 2>&1 | Out-Null
  # parse: header line has 'Component N, Filter', next payload line has the switch system name
  $compSwitch = @{}
  $curComp = $null
  if (Test-Path $txt) {
    foreach ($ln in Get-Content $txt) {
      if ($ln -match 'Component\s+(\d+),\s+Filter') { $curComp = $matches[1] }
      elseif ($ln -match '7050(sw\d)') { if ($curComp) { $compSwitch[$curComp] = $matches[1] } }
    }
  }
  # join
  foreach ($a in $adapters) {
    $comp = ($compMac.GetEnumerator() | Where-Object { $_.Value -eq $a.MAC } | Select-Object -First 1).Key
    $sw   = if ($comp -and $compSwitch.ContainsKey($comp)) { $compSwitch[$comp] } else { '(no LLDP seen)' }
    [pscustomobject]@{ Node=$env:COMPUTERNAME; Adapter=$a.Name; MAC=$a.MAC; Component=$comp; NeighborSwitch=$sw }
  }
}

$rows = foreach ($sam in $nodes) {
  Write-Host "Capturing LLDP on $sam (~45s)..."
  $cred = [pscredential]::new("$sam\Administrator",$pw)
  try { Invoke-Command "$sam.lab.example.com" -Credential $cred -Authentication Negotiate -ScriptBlock $probe }
  catch { [pscustomobject]@{ Node=$sam; Adapter='(unreachable)'; MAC=''; Component=''; NeighborSwitch="$($_.Exception.Message)" } }
}

$final = $rows | ForEach-Object {
  $vlan = switch ($_.NeighborSwitch) { 'sw1' {'711'} 'sw2' {'712'} default {'?'} }
  $expectedSwitch = if ($_.Adapter -eq 'Port3') {'sw1'} elseif ($_.Adapter -eq 'Port4') {'sw2'} else {'?'}
  $match = if ($_.NeighborSwitch -in 'sw1','sw2') { if ($_.NeighborSwitch -eq $expectedSwitch) {'OK'} else {'MISMATCH -> rename'} } else {'?' }
  [pscustomobject]@{
    Node=$_.Node; Adapter=$_.Adapter; MAC=$_.MAC; NeighborSwitch=$_.NeighborSwitch
    'VLAN(byswitch)'=$vlan; 'ATC expects'=$expectedSwitch; Verdict=$match
  }
}
$final | Sort-Object Node,Adapter | Format-Table -AutoSize
$final | Sort-Object Node,Adapter | Export-Csv .\out\_lldp-cabling-map.csv -NoTypeInformation
Write-Host ""
Write-Host "Saved: out\_lldp-cabling-map.csv"
Write-Host "sw1=SW1/711, sw2=SW2/712. ATC binds Port3->711, Port4->712, so a port on the 'wrong' switch = rename target."
