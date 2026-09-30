# Untagged-through-SWITCH test on the Port4 pair.
# The network operator set the SW ports for az1/az2 "port 1" (= our Port4) to untagged/access and
# reconnected them THROUGH THE SWITCH (no longer the direct DAC).
# Host Port4 is already VlanID 0 (untagged) from prior cleanup, matching an access port.
#   PASS  = switch forwards untagged between node01 Port4 and node02 Port4 -> physical link
#           into switch + switch fabric are good; the fault is specifically TAGGED handling.
#   FAIL  = switch not forwarding between those ports even untagged -> larger switch issue
#           (port isolation / ports on different access VLANs / not bridging).
$pw = ConvertTo-SecureString ((Get-Content ".\.creds\azloc-local-admin.cred" -Raw).Trim())
$ca = [pscredential]::new("azl-node-01\Administrator",$pw)
$cb = [pscredential]::new("azl-node-02\Administrator",$pw)
$port = 'Port4'

Write-Host "===== Untagged through the SWITCH ($port pair) ====="
Write-Host "Step 1: confirm host $port is untagged (VlanID 0) + link Up on both nodes"
$state = { param($p)
  $a = Get-NetAdapter -Name $p -EA SilentlyContinue
  $v = (Get-NetAdapterAdvancedProperty -Name $p -RegistryKeyword 'VlanID' -EA SilentlyContinue).RegistryValue
  [pscustomobject]@{ Node=$env:COMPUTERNAME; NIC=$p; Status=$a.Status; Media=$a.MediaConnectionState; VlanID=$v; MAC=$a.MacAddress }
}
Invoke-Command azl-node-01.lab.example.com -Credential $ca -Authentication Negotiate -ScriptBlock $state -ArgumentList $port | Format-Table -AutoSize
Invoke-Command azl-node-02.lab.example.com -Credential $cb -Authentication Negotiate -ScriptBlock $state -ArgumentList $port | Format-Table -AutoSize

Write-Host "Step 2: assign point-to-point test IPs (untagged, /30) and ping node01 -> node02"
$setip = { param($p,$ip)
  Set-NetAdapterAdvancedProperty -Name $p -RegistryKeyword 'VlanID' -RegistryValue 0 -ErrorAction SilentlyContinue
  Get-NetIPAddress -InterfaceAlias $p -AddressFamily IPv4 -EA SilentlyContinue | Where-Object {$_.IPAddress -like '192.168.100.*'} | Remove-NetIPAddress -Confirm:$false -EA SilentlyContinue
  New-NetIPAddress -InterfaceAlias $p -IPAddress $ip -PrefixLength 30 -EA SilentlyContinue | Out-Null
}
Invoke-Command azl-node-01.lab.example.com -Credential $ca -Authentication Negotiate -ScriptBlock $setip -ArgumentList $port,'192.168.100.1'
Invoke-Command azl-node-02.lab.example.com -Credential $cb -Authentication Negotiate -ScriptBlock $setip -ArgumentList $port,'192.168.100.2'
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
Write-Host ("UNTAGGED THROUGH SWITCH: Ping=$($res.Ping)  ARP=$($res.Arp)")
Write-Host ("VERDICT: {0}" -f $(if($pass){'PASS - switch forwards untagged between these ports. Physical link + fabric good; fault is TAGGED handling only.'}else{'FAIL - switch not forwarding between these ports even untagged. Larger switch-side issue.'}))

Write-Host ""
Write-Host "== Cleanup: remove test IPs, leave VlanID 0 baseline =="
$clean = { param($p)
  Get-NetIPAddress -InterfaceAlias $p -AddressFamily IPv4 -EA SilentlyContinue | Where-Object {$_.IPAddress -like '192.168.100.*'} | Remove-NetIPAddress -Confirm:$false -EA SilentlyContinue
  (Get-NetAdapterAdvancedProperty -Name $p -RegistryKeyword 'VlanID' -EA SilentlyContinue).RegistryValue
}
$v1 = Invoke-Command azl-node-01.lab.example.com -Credential $ca -Authentication Negotiate -ScriptBlock $clean -ArgumentList $port
$v2 = Invoke-Command azl-node-02.lab.example.com -Credential $cb -Authentication Negotiate -ScriptBlock $clean -ArgumentList $port
Write-Host ("node01 $port VlanID now: {0}   node02 $port VlanID now: {1}" -f $v1, $v2)
