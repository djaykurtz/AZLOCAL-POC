# TAGGED 712 confirmation THROUGH SW2, post-rename. Every node's Port4 is now the SW2/712 port.
# RUN ONLY AFTER the network operator adds 'switchport mode trunk' to SW2 Et9/1-14/1. As captured on 2026-07-27 the
# SW2 node ports were MISSING 'switchport mode trunk' (access mode on vlan 712), which drops tagged 712.
# Mirror of _tagged-711-confirm.ps1 but Port4 / VLAN 712 / SW2.
#   PASS = tagged 712 crosses SW2 east-west -> 712 fabric proven; both fabrics good; ready for validator.
#   FAIL = SW2 still not forwarding tagged 712 (check 'switchport mode trunk' was actually applied).
$pw = ConvertTo-SecureString ((Get-Content ".\.creds\azloc-local-admin.cred" -Raw).Trim())
$ca = [pscredential]::new('azl-node-01\Administrator',$pw)
$cb = [pscredential]::new('azl-node-02\Administrator',$pw)
$port = 'Port4'   # now the SW2/712 port on every node
$vlan = 712

Write-Host "===== TAGGED $vlan through SW2: node01 $port  <->  node02 $port ====="
$apply = { param($p,$ip,$vl)
  Set-NetAdapterAdvancedProperty -Name $p -RegistryKeyword 'VlanID' -RegistryValue $vl -ErrorAction SilentlyContinue
  Start-Sleep 3
  Get-NetIPAddress -InterfaceAlias $p -AddressFamily IPv4 -EA SilentlyContinue | Where-Object {$_.IPAddress -like '192.168.100.*'} | Remove-NetIPAddress -Confirm:$false -EA SilentlyContinue
  New-NetIPAddress -InterfaceAlias $p -IPAddress $ip -PrefixLength 30 -EA SilentlyContinue | Out-Null
  $v = (Get-NetAdapterAdvancedProperty -Name $p -RegistryKeyword 'VlanID' -EA SilentlyContinue).RegistryValue
  [pscustomobject]@{ Node=$env:COMPUTERNAME; NIC=$p; VlanID=$v; MAC=(Get-NetAdapter -Name $p).MacAddress }
}
Invoke-Command azl-node-01.lab.example.com -Credential $ca -Authentication Negotiate -ScriptBlock $apply -ArgumentList $port,'192.168.100.1',$vlan | Format-Table -AutoSize
Invoke-Command azl-node-02.lab.example.com -Credential $cb -Authentication Negotiate -ScriptBlock $apply -ArgumentList $port,'192.168.100.2',$vlan | Format-Table -AutoSize
Start-Sleep 3

$res = Invoke-Command azl-node-01.lab.example.com -Credential $ca -Authentication Negotiate -ScriptBlock {
  param($p)
  Remove-NetNeighbor -InterfaceAlias $p -IPAddress 192.168.100.2 -Confirm:$false -EA SilentlyContinue
  $ping = Test-Connection -ComputerName 192.168.100.2 -Count 6 -Quiet -EA SilentlyContinue
  Start-Sleep 1
  $nb = Get-NetNeighbor -InterfaceAlias $p -IPAddress 192.168.100.2 -EA SilentlyContinue
  [pscustomobject]@{ Ping=[bool]$ping; Arp=if($nb){"$($nb.State)/$($nb.LinkLayerAddress)"}else{'none'} }
} -ArgumentList $port
$pass = ($res.Arp -match 'Reachable|Stale')
Write-Host ""
Write-Host ("TAGGED $vlan THROUGH SW2 (node01 $port -> node02 $port): Ping=$($res.Ping)  ARP=$($res.Arp)")
Write-Host ("VERDICT: {0}" -f $(if($pass){"PASS - tagged $vlan forwards through SW2. Both fabrics proven; ready for validator."}else{'FAIL - SW2 not forwarding tagged 712. Verify switchport mode trunk was applied on SW2 Et9-14/1.'}))

Write-Host ""
Write-Host "== Cleanup: remove tag + test IPs, back to VlanID 0 baseline =="
$clean = { param($p)
  Get-NetIPAddress -InterfaceAlias $p -AddressFamily IPv4 -EA SilentlyContinue | Where-Object {$_.IPAddress -like '192.168.100.*'} | Remove-NetIPAddress -Confirm:$false -EA SilentlyContinue
  Set-NetAdapterAdvancedProperty -Name $p -RegistryKeyword 'VlanID' -RegistryValue 0 -ErrorAction SilentlyContinue
  (Get-NetAdapterAdvancedProperty -Name $p -RegistryKeyword 'VlanID' -EA SilentlyContinue).RegistryValue
}
$v1 = Invoke-Command azl-node-01.lab.example.com -Credential $ca -Authentication Negotiate -ScriptBlock $clean -ArgumentList $port
$v2 = Invoke-Command azl-node-02.lab.example.com -Credential $cb -Authentication Negotiate -ScriptBlock $clean -ArgumentList $port
Write-Host ("node01 $port VlanID now: {0}   node02 $port VlanID now: {1}" -f $v1, $v2)
