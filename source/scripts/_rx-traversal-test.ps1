# RX-counter traversal test: does a tagged VLAN 711 frame from node01 reach node02?
# Switch-independent (reads peer NIC RX counters). No switch console access needed.
$pw = ConvertTo-SecureString ((Get-Content ".\.creds\azloc-local-admin.cred" -Raw).Trim())
$ca = [pscredential]::new("azl-node-01\Administrator",$pw)
$cb = [pscredential]::new("azl-node-02\Administrator",$pw)

Write-Host "===== RX-COUNTER TRAVERSAL TEST (tagged VLAN 711, Port3) ====="
$rxBefore = Invoke-Command azl-node-02.lab.example.com -Credential $cb -Authentication Negotiate -ScriptBlock {
  $s = Get-NetAdapterStatistics -Name Port3
  [pscustomobject]@{ U=$s.ReceivedUnicastPackets; B=$s.ReceivedBroadcastPackets }
}
Write-Host ("node02 Port3 RX before: Unicast={0} Broadcast={1}" -f $rxBefore.U, $rxBefore.B)

Write-Host "Sending 30 ping/ARP attempts from node01 (tagged 711)..."
Invoke-Command azl-node-01.lab.example.com -Credential $ca -Authentication Negotiate -ScriptBlock {
  Remove-NetNeighbor -InterfaceAlias Port3 -IPAddress 192.168.110.2 -Confirm:$false -EA SilentlyContinue
  1..30 | ForEach-Object { Test-Connection -ComputerName 192.168.110.2 -Count 1 -EA SilentlyContinue | Out-Null }
} | Out-Null
Start-Sleep 2

$rxAfter = Invoke-Command azl-node-02.lab.example.com -Credential $cb -Authentication Negotiate -ScriptBlock {
  $s = Get-NetAdapterStatistics -Name Port3
  [pscustomobject]@{ U=$s.ReceivedUnicastPackets; B=$s.ReceivedBroadcastPackets }
}
Write-Host ("node02 Port3 RX after:  Unicast={0} Broadcast={1}" -f $rxAfter.U, $rxAfter.B)
Write-Host ("DELTA: Unicast=+{0}  Broadcast=+{1}" -f ($rxAfter.U-$rxBefore.U), ($rxAfter.B-$rxBefore.B))
Write-Host ""
Write-Host "If Broadcast delta > ~30, node01's tagged 711 ARP crossed SW1 to node02 = fabric forwards."
Write-Host "If ~0, tagged frames are NOT traversing (switch drop or tag not emitted)."
