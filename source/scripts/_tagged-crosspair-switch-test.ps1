# DEFINITIVE test: TAGGED VLAN 711 across the SWITCH on the CORRECTLY-CABLED pair.
#   node01 Port4 (SW1 Et9/1)  <->  node02 Port3 (SW1 Et10/1)   -- both proven on SW1/711
# This mirrors what Network ATC actually does (it tags storage with 711/712).
#
# PREREQUISITE (switch side, confirm with the network operator BEFORE trusting a FAIL):
#   Et9/1 and Et10/1 must be TRUNK with VLAN 711 TAGGED (the real deployment config).
#   If they are still untagged/native-711 access ports, a tagged frame may be dropped on
#   ingress for the WRONG reason -> a FAIL would be inconclusive. Restore trunk+711-tagged first.
#
#   PASS = tagged 711 crosses the switch on the correct pair -> real deployment storage path works;
#          the only issue was the asymmetric cabling.
#   FAIL (with ports confirmed trunk+711-tagged) = switch not forwarding TAGGED 711 between the ports.
$pw = ConvertTo-SecureString ((Get-Content ".\.creds\azloc-local-admin.cred" -Raw).Trim())
$ca = [pscredential]::new("azl-node-01\Administrator",$pw)
$cb = [pscredential]::new("azl-node-02\Administrator",$pw)
$p1 = 'Port4'   # node01 on SW1 Et9/1
$p2 = 'Port3'   # node02 on SW1 Et10/1
$vlan = 711

Write-Host "===== TAGGED VLAN $vlan across SWITCH: node01 $p1  <->  node02 $p2 ====="
$apply = { param($p,$ip,$vl)
  Set-NetAdapterAdvancedProperty -Name $p -RegistryKeyword 'VlanID' -RegistryValue $vl -ErrorAction SilentlyContinue
  Start-Sleep 3
  Get-NetIPAddress -InterfaceAlias $p -AddressFamily IPv4 -EA SilentlyContinue | Where-Object {$_.IPAddress -like '192.168.100.*'} | Remove-NetIPAddress -Confirm:$false -EA SilentlyContinue
  New-NetIPAddress -InterfaceAlias $p -IPAddress $ip -PrefixLength 30 -EA SilentlyContinue | Out-Null
  $v = (Get-NetAdapterAdvancedProperty -Name $p -RegistryKeyword 'VlanID' -EA SilentlyContinue).RegistryValue
  [pscustomobject]@{ Node=$env:COMPUTERNAME; NIC=$p; VlanID=$v }
}
Invoke-Command azl-node-01.lab.example.com -Credential $ca -Authentication Negotiate -ScriptBlock $apply -ArgumentList $p1,'192.168.100.1',$vlan | Format-Table -AutoSize
Invoke-Command azl-node-02.lab.example.com -Credential $cb -Authentication Negotiate -ScriptBlock $apply -ArgumentList $p2,'192.168.100.2',$vlan | Format-Table -AutoSize
Start-Sleep 3

$res = Invoke-Command azl-node-01.lab.example.com -Credential $ca -Authentication Negotiate -ScriptBlock {
  param($p)
  Remove-NetNeighbor -InterfaceAlias $p -IPAddress 192.168.100.2 -Confirm:$false -EA SilentlyContinue
  $ping = Test-Connection -ComputerName 192.168.100.2 -Count 6 -Quiet -EA SilentlyContinue
  Start-Sleep 1
  $nb = Get-NetNeighbor -InterfaceAlias $p -IPAddress 192.168.100.2 -EA SilentlyContinue
  [pscustomobject]@{ Ping=[bool]$ping; Arp=if($nb){"$($nb.State)/$($nb.LinkLayerAddress)"}else{'none'} }
} -ArgumentList $p1
$pass = ($res.Arp -match 'Reachable|Stale')
Write-Host ""
Write-Host ("TAGGED $vlan ACROSS SWITCH (node01 $p1 -> node02 $p2): Ping=$($res.Ping)  ARP=$($res.Arp)")
Write-Host ("VERDICT: {0}" -f $(if($pass){"PASS - tagged $vlan crosses the switch on the correct pair. Real ATC storage path works; asymmetric cabling was the only issue."}else{"FAIL - if ports are CONFIRMED trunk+$vlan-tagged, switch is not forwarding tagged $vlan. If ports are still untagged/access, result is INCONCLUSIVE (restore trunk first)."}))

Write-Host ""
Write-Host "== Cleanup: remove tag + test IPs, back to VlanID 0 baseline =="
$clean = { param($p)
  Get-NetIPAddress -InterfaceAlias $p -AddressFamily IPv4 -EA SilentlyContinue | Where-Object {$_.IPAddress -like '192.168.100.*'} | Remove-NetIPAddress -Confirm:$false -EA SilentlyContinue
  Set-NetAdapterAdvancedProperty -Name $p -RegistryKeyword 'VlanID' -RegistryValue 0 -ErrorAction SilentlyContinue
  (Get-NetAdapterAdvancedProperty -Name $p -RegistryKeyword 'VlanID' -EA SilentlyContinue).RegistryValue
}
$v1 = Invoke-Command azl-node-01.lab.example.com -Credential $ca -Authentication Negotiate -ScriptBlock $clean -ArgumentList $p1
$v2 = Invoke-Command azl-node-02.lab.example.com -Credential $cb -Authentication Negotiate -ScriptBlock $clean -ArgumentList $p2
Write-Host ("node01 $p1 VlanID now: {0}   node02 $p2 VlanID now: {1}" -f $v1, $v2)
