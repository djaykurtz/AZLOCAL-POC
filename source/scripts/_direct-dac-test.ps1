# Direct-DAC test: the network operator cabled node01 <-> node02 directly (az1 port1 to az2 port1),
# bypassing the switch. Detect which Windows port is the DAC (Up + connected), then
# test untagged point-to-point connectivity over it. No VLAN needed on a direct cable.
$pw = ConvertTo-SecureString ((Get-Content ".\.creds\azloc-local-admin.cred" -Raw).Trim())
$ca = [pscredential]::new("azl-node-01\Administrator",$pw)
$cb = [pscredential]::new("azl-node-02\Administrator",$pw)

Write-Host "===== STEP 1: link/media state of storage ports on both nodes ====="
$linkState = {
  Get-NetAdapter -Name Port3,Port4 -ErrorAction SilentlyContinue | ForEach-Object {
    [pscustomobject]@{ Node=$env:COMPUTERNAME; NIC=$_.Name; Status=$_.Status; Media=$_.MediaConnectionState; Speed=$_.LinkSpeed; MAC=$_.MacAddress }
  }
}
$l1 = Invoke-Command azl-node-01.lab.example.com -Credential $ca -Authentication Negotiate -ScriptBlock $linkState
$l2 = Invoke-Command azl-node-02.lab.example.com -Credential $cb -Authentication Negotiate -ScriptBlock $linkState
$l1 + $l2 | Format-Table Node,NIC,Status,Media,Speed,MAC -AutoSize

Write-Host ""
Write-Host "===== STEP 2: test each candidate port pair UNTAGGED (direct cable, /30) ====="
foreach ($port in 'Port3','Port4') {
  Write-Host "`n--- Testing $port pair (node01 .1  <->  node02 .2) ---"
  $apply = { param($p,$ip)
    Set-NetAdapterAdvancedProperty -Name $p -RegistryKeyword 'VlanID' -RegistryValue 0 -ErrorAction SilentlyContinue
    Get-NetIPAddress -InterfaceAlias $p -AddressFamily IPv4 -EA SilentlyContinue | Where-Object {$_.IPAddress -like '192.168.100.*'} | Remove-NetIPAddress -Confirm:$false -EA SilentlyContinue
    New-NetIPAddress -InterfaceAlias $p -IPAddress $ip -PrefixLength 30 -EA SilentlyContinue | Out-Null
  }
  Invoke-Command azl-node-01.lab.example.com -Credential $ca -Authentication Negotiate -ScriptBlock $apply -ArgumentList $port,'192.168.100.1' | Out-Null
  Invoke-Command azl-node-02.lab.example.com -Credential $cb -Authentication Negotiate -ScriptBlock $apply -ArgumentList $port,'192.168.100.2' | Out-Null
  Start-Sleep 3
  $res = Invoke-Command azl-node-01.lab.example.com -Credential $ca -Authentication Negotiate -ScriptBlock {
    param($p)
    Remove-NetNeighbor -InterfaceAlias $p -IPAddress 192.168.100.2 -Confirm:$false -EA SilentlyContinue
    $ping = Test-Connection -ComputerName 192.168.100.2 -Count 5 -Quiet -EA SilentlyContinue
    Start-Sleep 1
    $nb = Get-NetNeighbor -InterfaceAlias $p -IPAddress 192.168.100.2 -EA SilentlyContinue
    [pscustomobject]@{ Port=$p; Ping=[bool]$ping; Arp=if($nb){"$($nb.State)/$($nb.LinkLayerAddress)"}else{'none'} }
  } -ArgumentList $port
  $pass = ($res.Arp -match 'Reachable|Stale')
  Write-Host ("  $port : Ping=$($res.Ping)  ARP=$($res.Arp)  ==> {0}" -f $(if($pass){'PASS (this is the DAC pair, host+NIC good)'}else{'no link this pair'}))
  # cleanup this pair's test IPs
  $clean = { param($p) Get-NetIPAddress -InterfaceAlias $p -AddressFamily IPv4 -EA SilentlyContinue | Where-Object {$_.IPAddress -like '192.168.100.*'} | Remove-NetIPAddress -Confirm:$false -EA SilentlyContinue }
  Invoke-Command azl-node-01.lab.example.com -Credential $ca -Authentication Negotiate -ScriptBlock $clean -ArgumentList $port | Out-Null
  Invoke-Command azl-node-02.lab.example.com -Credential $cb -Authentication Negotiate -ScriptBlock $clean -ArgumentList $port | Out-Null
}
Write-Host ""
Write-Host "Test IPs removed. If a pair PASSED untagged over the DAC, host NICs + cabling are proven good"
Write-Host "and the switch is the fault. Next: repeat that pair WITH VLAN 711 tag to confirm tagging works too."
