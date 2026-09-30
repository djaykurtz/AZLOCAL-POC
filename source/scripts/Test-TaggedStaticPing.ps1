<#
.SYNOPSIS
  Confirm tagged VLAN unicast works by pinging with a STATIC ARP entry,
  bypassing broadcast ARP resolution entirely.

.DESCRIPTION
  Brings up the temp tagged vSwitch on both nodes, seeds a PERMANENT (static)
  neighbor entry for the peer on each node (so no broadcast ARP is needed), then
  runs a real ping and reports the received count.

  If ping SUCCEEDS here but the normal Test-StorageFabricTagged.ps1 FAILS
  (ArpState Incomplete), the fabric data path is fine and the problem is broadcast
  ARP delivery on the VLAN (switch broadcast/storm suppression or ARP suppression).

  Temp vSwitch + static neighbors always removed in the finally block.

.NOTES
  ASCII only. Local, reversible. Requires Hyper-V + WinRM.
#>
[CmdletBinding()]
param(
  [string] $NodeA    = 'azl-node-01.lab.example.com',
  [string] $NodeB    = 'azl-node-02.lab.example.com',
  [string] $ShortA   = 'azl-node-01',
  [string] $ShortB   = 'azl-node-02',
  [string] $Port     = 'Port3',
  [int]    $Vlan     = 711,
  [string] $IpA      = '192.168.110.1',
  [string] $IpB      = '192.168.110.2',
  [int]    $Prefix   = 24,
  [string] $SwitchName = 'POC-VLANTest',
  [string] $CredPath = '.\.creds\azloc-local-admin.cred'
)
$ErrorActionPreference = 'Stop'
$pw = ConvertTo-SecureString ((Get-Content $CredPath -Raw).Trim())
$credA = [pscredential]::new("$ShortA\Administrator", $pw)
$credB = [pscredential]::new("$ShortB\Administrator", $pw)
$opt = New-PSSessionOption -OpenTimeout 15000 -OperationTimeout 180000

$applyBlock = {
  param($nic, $sw, $vlan, $ip, $prefix)
  Get-VMSwitch -Name $sw -ErrorAction SilentlyContinue | Remove-VMSwitch -Force -ErrorAction SilentlyContinue
  New-VMSwitch -Name $sw -NetAdapterName $nic -AllowManagementOS $true -ErrorAction Stop | Out-Null
  $vnic = "vEthernet ($sw)"
  Set-VMNetworkAdapterVlan -ManagementOS -VMNetworkAdapterName $sw -Access -VlanId $vlan -ErrorAction Stop
  Start-Sleep -Seconds 3
  Get-NetIPAddress -InterfaceAlias $vnic -AddressFamily IPv4 -ErrorAction SilentlyContinue |
    Where-Object { $_.IPAddress -like '169.254.*' -or $_.IPAddress -eq $ip } | Remove-NetIPAddress -Confirm:$false -ErrorAction SilentlyContinue
  New-NetIPAddress -InterfaceAlias $vnic -IPAddress $ip -PrefixLength $prefix -ErrorAction Stop | Out-Null
  [pscustomobject]@{ Node=$env:COMPUTERNAME; vNIC=$vnic; TestIP=$ip; Mac=(Get-NetAdapter -Name $vnic).MacAddress }
}

$staticPingBlock = {
  param($sw, $peerIp, $peerMac)
  $vnic = "vEthernet ($sw)"
  $mac  = $peerMac -replace '[:\-]', '' -replace '(.{2})(?!$)', '$1-'
  Remove-NetNeighbor -InterfaceAlias $vnic -IPAddress $peerIp -Confirm:$false -ErrorAction SilentlyContinue
  New-NetNeighbor -InterfaceAlias $vnic -IPAddress $peerIp -LinkLayerAddress $mac -State Permanent -ErrorAction Stop | Out-Null
  Start-Sleep -Seconds 1
  $out = (cmd /c "ping -n 10 -w 1000 $peerIp") -join "`n"
  $recv = 0
  if ($out -match 'Received = (\d+)') { $recv = [int]$Matches[1] }
  [pscustomobject]@{ Node=$env:COMPUTERNAME; PeerIp=$peerIp; PingReceived=$recv; PingSent=10 }
}

$cleanupBlock = {
  param($sw)
  $existed = [bool](Get-VMSwitch -Name $sw -ErrorAction SilentlyContinue)
  Get-VMSwitch -Name $sw -ErrorAction SilentlyContinue | Remove-VMSwitch -Force -ErrorAction SilentlyContinue
  [pscustomobject]@{ Node=$env:COMPUTERNAME; Removed=$existed; StillPresent=[bool](Get-VMSwitch -Name $sw -ErrorAction SilentlyContinue) }
}

$sA = New-PSSession -ComputerName $NodeA -Credential $credA -SessionOption $opt
$sB = New-PSSession -ComputerName $NodeB -Credential $credB -SessionOption $opt
try {
  "== Applying temp tagged vSwitch (VLAN $Vlan) on both nodes =="
  $a = Invoke-Command -Session $sA -ScriptBlock $applyBlock -ArgumentList $Port,$SwitchName,$Vlan,$IpA,$Prefix
  $b = Invoke-Command -Session $sB -ScriptBlock $applyBlock -ArgumentList $Port,$SwitchName,$Vlan,$IpB,$Prefix
  Start-Sleep -Seconds 2

  "== Static-ARP ping (bypasses broadcast ARP) =="
  $pA = Invoke-Command -Session $sA -ScriptBlock $staticPingBlock -ArgumentList $SwitchName,$IpB,$b.Mac
  $pB = Invoke-Command -Session $sB -ScriptBlock $staticPingBlock -ArgumentList $SwitchName,$IpA,$a.Mac
  @($pA,$pB) | Format-Table Node,PeerIp,PingSent,PingReceived -Auto | Out-String

  ""
  "INTERPRETATION:"
  if (($pA.PingReceived -gt 0) -and ($pB.PingReceived -gt 0)) {
    "  Ping SUCCEEDS with static ARP both ways -> tagged VLAN $Vlan DATA PATH IS GOOD."
    "  Since normal ARP-based test fails, the fault is BROADCAST ARP delivery on VLAN $Vlan"
    "  (switch broadcast/storm-control suppression or ARP suppression). Fabric itself is fine."
  } elseif (($pA.PingReceived -gt 0) -or ($pB.PingReceived -gt 0)) {
    "  ASYMMETRIC ping success -> one-way unicast forwarding issue on VLAN $Vlan."
  } else {
    "  Ping FAILS even with static ARP -> unicast data path on VLAN $Vlan is broken (not just broadcast)."
  }
}
finally {
  "== Cleanup =="
  Invoke-Command -Session $sA -ScriptBlock $cleanupBlock -ArgumentList $SwitchName | Format-Table -Auto | Out-String
  Invoke-Command -Session $sB -ScriptBlock $cleanupBlock -ArgumentList $SwitchName | Format-Table -Auto | Out-String
  Remove-PSSession $sA,$sB -ErrorAction SilentlyContinue
  "Done. Storage NICs returned to standalone."
}
