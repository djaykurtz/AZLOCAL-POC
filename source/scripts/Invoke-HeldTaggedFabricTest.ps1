<#
.SYNOPSIS
  Held tagged storage-fabric test: brings up VLAN-tagged storage traffic between
  two nodes on the SAME switch and HOLDS it for a few minutes so the network team
  can inspect the switch MAC table / counters live.

.DESCRIPTION
  The Azure Local storage VLAN tags only exist during an active deploy/validation
  run, so a switch MAC table is empty at rest. This script recreates the supported
  ConnectX-5 tagging path (temp Hyper-V external vSwitch + Set-VMNetworkAdapterVlan,
  exactly how Network ATC tags storage), assigns test IPs, starts CONTINUOUS ping
  to keep frames flowing, and holds for -HoldSeconds while you tell the switch team
  to run their MAC-table check. Everything is torn down in a finally block.

  Default: node 01 + node 02, Port3, VLAN 711 (SW1 fabric). For the 712/SW2 fabric
  run again with -Port Port4 -Vlan 712 -IpA/-IpB in a different subnet.

  During the hold window have the switch team run (SW1 for 711):
     show vlan 711
     show mac address-table vlan 711
     show interfaces ethernet 9/1,10/1 counters
  and look for the node Mellanox MACs printed below.

.NOTES
  ASCII only. Local + reversible. Storage NIC only; management/WinRM untouched.
  Same two nodes must be on the SAME switch for the VLAN under test
  (Port3 -> SW1/711, Port4 -> SW2/712).
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
  [int]    $HoldSeconds = 240,
  [string] $SwitchName = 'POC-VLANTest',
  [string] $CredPath = '.\.creds\azloc-local-admin.cred'
)
$ErrorActionPreference = 'Stop'
$pw = ConvertTo-SecureString ((Get-Content $CredPath -Raw).Trim())
$credA = [pscredential]::new("$ShortA\Administrator", $pw)
$credB = [pscredential]::new("$ShortB\Administrator", $pw)
$opt = New-PSSessionOption -OpenTimeout 15000 -OperationTimeout ([int]($HoldSeconds*1000 + 120000))

$applyBlock = {
  param($nic, $sw, $vlan, $ip, $prefix)
  $r = [ordered]@{ Node = $env:COMPUTERNAME; NIC = $nic }
  # physical Mellanox MAC the switch will learn (host vNIC inherits the port MAC)
  $r.PhysMac = (Get-NetAdapter -Name $nic -ErrorAction SilentlyContinue).MacAddress
  Get-VMSwitch -Name $sw -ErrorAction SilentlyContinue | Remove-VMSwitch -Force -ErrorAction SilentlyContinue
  New-VMSwitch -Name $sw -NetAdapterName $nic -AllowManagementOS $true -ErrorAction Stop | Out-Null
  $vnic = "vEthernet ($sw)"
  Set-VMNetworkAdapterVlan -ManagementOS -VMNetworkAdapterName $sw -Access -VlanId $vlan -ErrorAction Stop
  Start-Sleep -Seconds 3
  Get-NetIPAddress -InterfaceAlias $vnic -AddressFamily IPv4 -ErrorAction SilentlyContinue |
    Where-Object { $_.IPAddress -like '169.254.*' -or $_.IPAddress -eq $ip } | Remove-NetIPAddress -Confirm:$false -ErrorAction SilentlyContinue
  New-NetIPAddress -InterfaceAlias $vnic -IPAddress $ip -PrefixLength $prefix -ErrorAction Stop | Out-Null
  $r.vNIC = $vnic; $r.TestIP = $ip; $r.Link = (Get-NetAdapter -Name $vnic).Status
  [pscustomobject]$r
}

# Continuous ping as a background job on the node so frames keep flowing during the hold
$startFloodBlock = {
  param($vnic, $peerIp, $seconds)
  # seed a permanent neighbor entry is not needed; just flood pings
  $job = Start-Job -ScriptBlock {
    param($peer, $secs)
    $end = (Get-Date).AddSeconds($secs)
    while ((Get-Date) -lt $end) { Test-Connection -ComputerName $peer -Count 4 -ErrorAction SilentlyContinue | Out-Null }
  } -ArgumentList $peerIp, $seconds
  [pscustomobject]@{ Node = $env:COMPUTERNAME; JobId = $job.Id; PeerIp = $peerIp; Seconds = $seconds }
}

$cleanupBlock = {
  param($sw)
  $existed = [bool](Get-VMSwitch -Name $sw -ErrorAction SilentlyContinue)
  Get-Job -ErrorAction SilentlyContinue | Stop-Job -ErrorAction SilentlyContinue
  Get-Job -ErrorAction SilentlyContinue | Remove-Job -Force -ErrorAction SilentlyContinue
  Get-VMSwitch -Name $sw -ErrorAction SilentlyContinue | Remove-VMSwitch -Force -ErrorAction SilentlyContinue
  [pscustomobject]@{ Node = $env:COMPUTERNAME; Removed = $existed; StillPresent = [bool](Get-VMSwitch -Name $sw -ErrorAction SilentlyContinue) }
}

$swHint = if ($Vlan -eq 711) { 'SW1 (STOR-SW-01)' } elseif ($Vlan -eq 712) { 'SW2 (STOR-SW-02)' } else { 'the relevant switch' }

$sA = New-PSSession -ComputerName $NodeA -Credential $credA -SessionOption $opt
$sB = New-PSSession -ComputerName $NodeB -Credential $credB -SessionOption $opt
try {
  Write-Host "== Applying temp vSwitch + 802.1Q VLAN $Vlan tag + test IPs on $ShortA and $ShortB ==" -ForegroundColor Cyan
  $aInfo = Invoke-Command -Session $sA -ScriptBlock $applyBlock -ArgumentList $Port,$SwitchName,$Vlan,$IpA,$Prefix
  $bInfo = Invoke-Command -Session $sB -ScriptBlock $applyBlock -ArgumentList $Port,$SwitchName,$Vlan,$IpB,$Prefix
  $aInfo | Format-List | Out-String | Write-Host
  $bInfo | Format-List | Out-String | Write-Host

  Write-Host "== Starting continuous ping both directions for $HoldSeconds s ==" -ForegroundColor Cyan
  Invoke-Command -Session $sA -ScriptBlock $startFloodBlock -ArgumentList $aInfo.vNIC,$IpB,$HoldSeconds | Out-Null
  Invoke-Command -Session $sB -ScriptBlock $startFloodBlock -ArgumentList $bInfo.vNIC,$IpA,$HoldSeconds | Out-Null

  Write-Host ""
  Write-Host "=========================================================================" -ForegroundColor Yellow
  Write-Host " TAGGED VLAN $Vlan TRAFFIC IS NOW LIVE FOR $HoldSeconds SECONDS" -ForegroundColor Yellow
  Write-Host " Tell the switch team to run NOW on $swHint :" -ForegroundColor Yellow
  Write-Host "     show vlan $Vlan" -ForegroundColor White
  Write-Host "     show mac address-table vlan $Vlan" -ForegroundColor White
  Write-Host "     show interfaces counters | (the node ports)" -ForegroundColor White
  Write-Host ""
  Write-Host " Look for these node Mellanox MACs on VLAN $Vlan :" -ForegroundColor Yellow
  Write-Host ("     $ShortA $Port = {0}" -f $aInfo.PhysMac) -ForegroundColor White
  Write-Host ("     $ShortB $Port = {0}" -f $bInfo.PhysMac) -ForegroundColor White
  Write-Host ""
  Write-Host " MACs PRESENT  -> switch is learning; forwarding/isolation is the issue" -ForegroundColor Yellow
  Write-Host " MACs ABSENT   -> VLAN $Vlan not created/active on the switch, or tag not accepted" -ForegroundColor Yellow
  Write-Host "=========================================================================" -ForegroundColor Yellow
  Write-Host ""

  # Countdown + periodic ARP check from node A
  $checkEnd = (Get-Date).AddSeconds($HoldSeconds)
  while ((Get-Date) -lt $checkEnd) {
    $remain = [int]($checkEnd - (Get-Date)).TotalSeconds
    $arp = Invoke-Command -Session $sA -ScriptBlock {
      param($vnic,$peer)
      $nb = Get-NetNeighbor -InterfaceAlias $vnic -IPAddress $peer -ErrorAction SilentlyContinue
      if ($nb) { "$($nb.State)/$($nb.LinkLayerAddress)" } else { 'none' }
    } -ArgumentList $aInfo.vNIC,$IpB
    $pass = $arp -match 'Reachable|Stale'
    Write-Host ("  [{0,4}s left] node01->node02 ARP: {1}  {2}" -f $remain, $arp, $(if($pass){'<-- L2 WORKS'}else{''}))
    Start-Sleep -Seconds 20
  }

  Write-Host ""
  Write-Host "== Final ARP verdict ==" -ForegroundColor Cyan
  $final = Invoke-Command -Session $sA -ScriptBlock {
    param($vnic,$peer)
    $nb = Get-NetNeighbor -InterfaceAlias $vnic -IPAddress $peer -ErrorAction SilentlyContinue
    $ping = Test-Connection -ComputerName $peer -Count 4 -Quiet -ErrorAction SilentlyContinue
    [pscustomobject]@{ ArpState = if($nb){"$($nb.State)"}else{'None'}; ArpMac = if($nb){$nb.LinkLayerAddress}else{''}; Ping = [bool]$ping }
  } -ArgumentList $aInfo.vNIC,$IpB
  $l2 = ($final.ArpState -match 'Reachable|Stale') -and ($final.ArpMac -and $final.ArpMac -ne '00-00-00-00-00-00')
  Write-Host ("  VLAN $Vlan host-to-host L2: {0}  (ArpState=$($final.ArpState) ArpMac=$($final.ArpMac) Ping=$($final.Ping))" -f $(if($l2){'PASS'}else{'FAIL'})) -ForegroundColor $(if($l2){'Green'}else{'Red'})
}
finally {
  Write-Host "== Cleanup: removing temp vSwitch + stopping ping jobs on both nodes ==" -ForegroundColor Cyan
  Invoke-Command -Session $sA -ScriptBlock $cleanupBlock -ArgumentList $SwitchName | Format-Table -Auto | Out-String | Write-Host
  Invoke-Command -Session $sB -ScriptBlock $cleanupBlock -ArgumentList $SwitchName | Format-Table -Auto | Out-String | Write-Host
  Remove-PSSession $sA,$sB -ErrorAction SilentlyContinue
  Write-Host "Done. Storage NICs returned to standalone." -ForegroundColor Green
}
