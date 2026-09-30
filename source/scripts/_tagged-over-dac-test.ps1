# Tagged-over-DAC test: the DAC is node01 Port4 <-> node02 Port4 (untagged already PASSED).
# Now apply VLAN 711 tag on both ends and test over the direct cable (no switch).
#  PASS = host VLAN tagging works end-to-end -> switch is the fault.
#  FAIL = Mellanox tagging is the problem (host-side, fixable).
$pw = ConvertTo-SecureString ((Get-Content ".\.creds\azloc-local-admin.cred" -Raw).Trim())
$ca = [pscredential]::new("azl-node-01\Administrator",$pw)
$cb = [pscredential]::new("azl-node-02\Administrator",$pw)
$port = 'Port4'

Write-Host "===== Tagged VLAN 711 over direct DAC ($port pair) ====="
$apply = { param($p,$ip)
  Set-NetAdapterAdvancedProperty -Name $p -RegistryKeyword 'VlanID' -RegistryValue 711 -ErrorAction SilentlyContinue
  Start-Sleep 3
  Get-NetIPAddress -InterfaceAlias $p -AddressFamily IPv4 -EA SilentlyContinue | Where-Object {$_.IPAddress -like '192.168.100.*'} | Remove-NetIPAddress -Confirm:$false -EA SilentlyContinue
  New-NetIPAddress -InterfaceAlias $p -IPAddress $ip -PrefixLength 30 -EA SilentlyContinue | Out-Null
  $v = (Get-NetAdapterAdvancedProperty -Name $p -RegistryKeyword 'VlanID' -EA SilentlyContinue).RegistryValue
  [pscustomobject]@{ Node=$env:COMPUTERNAME; VlanID=$v }
}
Invoke-Command azl-node-01.lab.example.com -Credential $ca -Authentication Negotiate -ScriptBlock $apply -ArgumentList $port,'192.168.100.1' | Format-Table -AutoSize
Invoke-Command azl-node-02.lab.example.com -Credential $cb -Authentication Negotiate -ScriptBlock $apply -ArgumentList $port,'192.168.100.2' | Format-Table -AutoSize
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
Write-Host ("TAGGED 711 over DAC: Ping=$($res.Ping)  ARP=$($res.Arp)")
Write-Host ("VERDICT: {0}" -f $(if($pass){'PASS - host VLAN 711 tagging works end-to-end. Switch is the fault.'}else{'FAIL - host-side Mellanox tagging is the problem.'}))

Write-Host ""
Write-Host "== Cleanup: remove tag + test IPs, back to baseline =="
$clean = { param($p)
  Get-NetIPAddress -InterfaceAlias $p -AddressFamily IPv4 -EA SilentlyContinue | Where-Object {$_.IPAddress -like '192.168.100.*'} | Remove-NetIPAddress -Confirm:$false -EA SilentlyContinue
  Set-NetAdapterAdvancedProperty -Name $p -RegistryKeyword 'VlanID' -RegistryValue 0 -ErrorAction SilentlyContinue
  (Get-NetAdapterAdvancedProperty -Name $p -RegistryKeyword 'VlanID' -EA SilentlyContinue).RegistryValue
}
$v1 = Invoke-Command azl-node-01.lab.example.com -Credential $ca -Authentication Negotiate -ScriptBlock $clean -ArgumentList $port
$v2 = Invoke-Command azl-node-02.lab.example.com -Credential $cb -Authentication Negotiate -ScriptBlock $clean -ArgumentList $port
Write-Host ("node01 $port VlanID now: {0}   node02 $port VlanID now: {1}" -f $v1, $v2)
