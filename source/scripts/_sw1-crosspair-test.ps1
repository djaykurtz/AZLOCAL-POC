# Cross-pair test matching ACTUAL SW1 cabling proven by the switch MAC table:
#   SW1 Et9/1  = node01 Port4 (MAC 00-00-5E-00-53-06)  <- confirmed on VLAN 711
#   SW1 Et10/1 = node02 Port3 (MAC 00-00-5E-00-53-03)  <- confirmed on VLAN 711 (flapped)
# The nodes are cabled ASYMMETRICALLY (node01 uses Port4 for SW1, node02 uses Port3 for SW1),
# so the earlier same-port-number test (Port4<->Port4) was across two different switches.
# This test uses the REAL SW1 ports on each node, untagged (switch ports untagged/native 711).
#   PASS = SW1/711 forwards east-west between node01 and node02 -> switch fabric good on 711.
#   FAIL = even the correctly-cabled SW1 pair does not cross -> switch not bridging on 711.
$pw = ConvertTo-SecureString ((Get-Content ".\.creds\azloc-local-admin.cred" -Raw).Trim())
$ca = [pscredential]::new("azl-node-01\Administrator",$pw)
$cb = [pscredential]::new("azl-node-02\Administrator",$pw)
$p1 = 'Port4'   # node01 port on SW1 Et9/1
$p2 = 'Port3'   # node02 port on SW1 Et10/1

Write-Host "===== SW1/711 cross-pair test: node01 $p1  <->  node02 $p2 (untagged) ====="
$state = { param($p)
  $a = Get-NetAdapter -Name $p -EA SilentlyContinue
  $v = (Get-NetAdapterAdvancedProperty -Name $p -RegistryKeyword 'VlanID' -EA SilentlyContinue).RegistryValue
  [pscustomobject]@{ Node=$env:COMPUTERNAME; NIC=$p; Status=$a.Status; Media=$a.MediaConnectionState; VlanID=$v; MAC=$a.MacAddress }
}
Invoke-Command azl-node-01.lab.example.com -Credential $ca -Authentication Negotiate -ScriptBlock $state -ArgumentList $p1 | Format-Table -AutoSize
Invoke-Command azl-node-02.lab.example.com -Credential $cb -Authentication Negotiate -ScriptBlock $state -ArgumentList $p2 | Format-Table -AutoSize

Write-Host "Assign untagged /30 test IPs and ping node01 -> node02"
$setip = { param($p,$ip)
  Set-NetAdapterAdvancedProperty -Name $p -RegistryKeyword 'VlanID' -RegistryValue 0 -ErrorAction SilentlyContinue
  Get-NetIPAddress -InterfaceAlias $p -AddressFamily IPv4 -EA SilentlyContinue | Where-Object {$_.IPAddress -like '192.168.100.*'} | Remove-NetIPAddress -Confirm:$false -EA SilentlyContinue
  New-NetIPAddress -InterfaceAlias $p -IPAddress $ip -PrefixLength 30 -EA SilentlyContinue | Out-Null
}
Invoke-Command azl-node-01.lab.example.com -Credential $ca -Authentication Negotiate -ScriptBlock $setip -ArgumentList $p1,'192.168.100.1'
Invoke-Command azl-node-02.lab.example.com -Credential $cb -Authentication Negotiate -ScriptBlock $setip -ArgumentList $p2,'192.168.100.2'
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
Write-Host ("SW1/711 CROSS-PAIR (node01 $p1 -> node02 $p2): Ping=$($res.Ping)  ARP=$($res.Arp)")
Write-Host ("VERDICT: {0}" -f $(if($pass){'PASS - SW1 forwards 711 east-west when the correctly-cabled ports are used.'}else{'FAIL - even the correct SW1 pair does not cross on 711.'}))

Write-Host ""
Write-Host "== Cleanup: remove test IPs, leave VlanID 0 baseline =="
$clean = { param($p)
  Get-NetIPAddress -InterfaceAlias $p -AddressFamily IPv4 -EA SilentlyContinue | Where-Object {$_.IPAddress -like '192.168.100.*'} | Remove-NetIPAddress -Confirm:$false -EA SilentlyContinue
  (Get-NetAdapterAdvancedProperty -Name $p -RegistryKeyword 'VlanID' -EA SilentlyContinue).RegistryValue
}
$v1 = Invoke-Command azl-node-01.lab.example.com -Credential $ca -Authentication Negotiate -ScriptBlock $clean -ArgumentList $p1
$v2 = Invoke-Command azl-node-02.lab.example.com -Credential $cb -Authentication Negotiate -ScriptBlock $clean -ArgumentList $p2
Write-Host ("node01 $p1 VlanID now: {0}   node02 $p2 VlanID now: {1}" -f $v1, $v2)
