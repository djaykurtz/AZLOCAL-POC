# Definitive fabric traversal + tag-integrity test using pktmon on the RECEIVER.
# node02 captures ONLY frames whose source MAC = node01 Port3 (00-00-5E-00-53-01).
# node02 never sends with that MAC, so any captured frame = node01's frame that
# physically crossed SW1 to node02. Also decodes to reveal if the VLAN 711 tag survived.
# Switch-independent, no console needed.

$pw = ConvertTo-SecureString ((Get-Content ".\.creds\azloc-local-admin.cred" -Raw).Trim())
$ca = [pscredential]::new("azl-node-01\Administrator",$pw)
$cb = [pscredential]::new("azl-node-02\Administrator",$pw)

$node01Mac = '00-00-5E-00-53-01'   # node01 Port3 physical Mellanox MAC
$node01MacNoSep = $node01Mac -replace '-',''

Write-Host "===== pktmon RX capture on node02 Port3, filtered to node01 MAC $node01Mac ====="

# Start capture on node02 filtered to node01's MAC
Invoke-Command azl-node-02.lab.example.com -Credential $cb -Authentication Negotiate -ScriptBlock {
  param($mac)
  pktmon stop 2>&1 | Out-Null
  pktmon filter remove 2>&1 | Out-Null
  pktmon filter add HciTag -m $mac 2>&1 | Out-Null
  Remove-Item C:\Windows\Temp\rx711.etl -ErrorAction SilentlyContinue
  # capture full packets, all components; MAC filter limits to node01's frames
  pktmon start --capture --pkt-size 0 --file-name C:\Windows\Temp\rx711.etl 2>&1 | Out-Null
  "capture started"
} -ArgumentList $node01Mac | Out-Null
Write-Host "node02 capture started."

Write-Host "node01 flooding 40 tagged-711 pings to .2 ..."
Invoke-Command azl-node-01.lab.example.com -Credential $ca -Authentication Negotiate -ScriptBlock {
  Remove-NetNeighbor -InterfaceAlias Port3 -IPAddress 192.168.110.2 -Confirm:$false -EA SilentlyContinue
  1..40 | ForEach-Object { Test-Connection -ComputerName 192.168.110.2 -Count 1 -EA SilentlyContinue | Out-Null }
} | Out-Null
Start-Sleep 2

# Stop + decode on node02
$result = Invoke-Command azl-node-02.lab.example.com -Credential $cb -Authentication Negotiate -ScriptBlock {
  pktmon stop 2>&1 | Out-Null
  Remove-Item C:\Windows\Temp\rx711.txt -ErrorAction SilentlyContinue
  pktmon etl2txt C:\Windows\Temp\rx711.etl --out C:\Windows\Temp\rx711.txt 2>&1 | Out-Null
  $lines = if (Test-Path C:\Windows\Temp\rx711.txt) { Get-Content C:\Windows\Temp\rx711.txt } else { @() }
  $pktLines = $lines | Where-Object { $_ -match 'Ethernet|0x8100|VLAN|ICMP|ARP' }
  [pscustomobject]@{
    TotalLines   = $lines.Count
    Packetish    = ($pktLines | Measure-Object).Count
    Has8100Vlan  = [bool]($lines -match '8100|VLAN|vlan')
    Sample       = ($lines | Select-Object -First 30) -join "`n"
  }
}
Write-Host ("Capture lines: {0}   packet-ish lines: {1}   VLAN-tag seen: {2}" -f $result.TotalLines, $result.Packetish, $result.Has8100Vlan)
Write-Host "---- first 30 decoded lines ----"
Write-Host $result.Sample
Write-Host ""
Write-Host "INTERPRETATION:"
Write-Host " - Any captured frames = node01 tagged frames DID cross SW1 to node02 (fabric forwards)."
Write-Host " - Zero captured = node01 frames never reach node02 (switch drop or no tag emitted)."
