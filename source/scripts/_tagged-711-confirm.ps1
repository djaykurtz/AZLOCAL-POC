# TAGGED 711 confirmation THROUGH SW1, post-rename. Every node's Port3 is now the SW1/711 port.
# This closes the one gap we never proved: tagged 711 forwarding THROUGH the switch (we had proved
# tagged over the direct DAC, and untagged through the switch, but not tagged through the switch).
# SW1 is confirmed trunk + allowed vlan 711 on all node ports.
#   PASS = tagged 711 crosses SW1 east-west on the corrected ports -> real storage path works.
#   FAIL = a switch-side tagged-forwarding problem independent of the naming (would need switch attention).
$pw = ConvertTo-SecureString ((Get-Content ".\.creds\azloc-local-admin.cred" -Raw).Trim())
$ca = [pscredential]::new('azl-node-01\Administrator',$pw)
$cb = [pscredential]::new('azl-node-02\Administrator',$pw)
$port = 'Port3'   # now the SW1/711 port on every node
$vlan = 711

Write-Host "===== TAGGED $vlan through SW1: node01 $port  <->  node02 $port ====="
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
Write-Host ("TAGGED $vlan THROUGH SW1 (node01 $port -> node02 $port): Ping=$($res.Ping)  ARP=$($res.Arp)")
Write-Host ("VERDICT: {0}" -f $(if($pass){"PASS - tagged $vlan forwards through SW1 on the corrected ports. Last gap closed; ready for validator."}else{'FAIL - tagged forwarding through SW1 still broken; switch-side issue independent of naming.'}))

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
