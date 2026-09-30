# SW2/712 complement test: by SW1 findings, the SW2 ports should be node01 Port3 and node02 Port4.
#   node01 Port3 (MAC 00-00-5E-00-53-01 / 0000.5e00.5301)
#   node02 Port4 (MAC 00-00-5E-00-53-04 / 0000.5e00.5304)
# Same untagged method as _sw1-crosspair-test.ps1. Two purposes:
#   (1) connectivity result node01 Port3 <-> node02 Port4 through SW2;
#   (2) generate traffic so the network operator can confirm these MACs land on SW2 (completes the verified map).
# CAVEAT: untagged only reflects VLAN 712 IF the network operator set the SW2 ports untagged/native 712. If the SW2
#   ports are still trunk/native-1, a pass reflects whatever native VLAN forwards, not necessarily 712.
#   Either way the MAC-learning on SW2 is the key deliverable here.
$pw = ConvertTo-SecureString ((Get-Content ".\.creds\azloc-local-admin.cred" -Raw).Trim())
$ca = [pscredential]::new("azl-node-01\Administrator",$pw)
$cb = [pscredential]::new("azl-node-02\Administrator",$pw)
$p1 = 'Port3'   # node01 expected on SW2
$p2 = 'Port4'   # node02 expected on SW2

Write-Host "===== SW2 complement test (expected 712): node01 $p1  <->  node02 $p2 (untagged) ====="
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
Write-Host ("SW2 COMPLEMENT (node01 $p1 -> node02 $p2): Ping=$($res.Ping)  ARP=$($res.Arp)")
Write-Host ("VERDICT: {0}" -f $(if($pass){'PASS - these two ports cross through SW2 (confirms they are the SW2 pair).'}else{'FAIL - did not cross; check SW2 port mode / whether these are really the SW2 ports.'}))
Write-Host "For the network operator to confirm on SW2 MAC table: node01 Port3 = 0000.5e00.5301 ; node02 Port4 = 0000.5e00.5304"

Write-Host ""
Write-Host "== Cleanup: remove test IPs, leave VlanID 0 baseline =="
$clean = { param($p)
  Get-NetIPAddress -InterfaceAlias $p -AddressFamily IPv4 -EA SilentlyContinue | Where-Object {$_.IPAddress -like '192.168.100.*'} | Remove-NetIPAddress -Confirm:$false -EA SilentlyContinue
  (Get-NetAdapterAdvancedProperty -Name $p -RegistryKeyword 'VlanID' -EA SilentlyContinue).RegistryValue
}
$v1 = Invoke-Command azl-node-01.lab.example.com -Credential $ca -Authentication Negotiate -ScriptBlock $clean -ArgumentList $p1
$v2 = Invoke-Command azl-node-02.lab.example.com -Credential $cb -Authentication Negotiate -ScriptBlock $clean -ArgumentList $p2
Write-Host ("node01 $p1 VlanID now: {0}   node02 $p2 VlanID now: {1}" -f $v1, $v2)
