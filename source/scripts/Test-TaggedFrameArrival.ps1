<#
.SYNOPSIS
  Host-only "is the tag flowing" test - proves whether tagged VLAN frames
  actually cross the switch between two nodes, without needing switch access.

.DESCRIPTION
  Brings up the temp tagged vSwitch on both nodes (same 802.1Q path as
  Test-StorageFabricTagged.ps1), then on EACH node runs a pktmon capture
  filtered to the PEER node's host-vNIC MAC while BOTH nodes send ARP/ping.

  If node A captures frames sourced from node B's vNIC MAC, then tagged VLAN
  frames from B crossed the switch to A (tag insert + switch classify + switch
  forward all work in that direction). Zero frames = the tag is NOT flowing on
  that path (host not egressing tagged, or switch not forwarding the VLAN).

  IMPORTANT: with an external vSwitch the on-wire source MAC is the host vNIC's
  Hyper-V dynamic MAC (00-15-5D-*), NOT the Mellanox 98-03-9B-* port MAC. So the
  switch learns 00-15-5D-* on the storage VLAN, and that is what we filter/look for.

  Temp vSwitch is always removed in the finally block. Management NIC untouched.

.NOTES
  ASCII only. Local, reversible. Requires Hyper-V + WinRM + pktmon.
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
  [int]    $Seconds  = 15,
  [string] $SwitchName = 'POC-VLANTest',
  [string] $CredPath = '.\.creds\azloc-local-admin.cred'
)
$ErrorActionPreference = 'Stop'
$pw = ConvertTo-SecureString ((Get-Content $CredPath -Raw).Trim())
$credA = [pscredential]::new("$ShortA\Administrator", $pw)
$credB = [pscredential]::new("$ShortB\Administrator", $pw)
$opt = New-PSSessionOption -OpenTimeout 15000 -OperationTimeout 300000

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
  [pscustomobject]@{
    Node    = $env:COMPUTERNAME
    vNIC    = $vnic
    TestIP  = $ip
    VlanSet = (Get-VMNetworkAdapterVlan -ManagementOS -VMNetworkAdapterName $sw).AccessVlanId
    Mac     = (Get-NetAdapter -Name $vnic).MacAddress
    Link    = (Get-NetAdapter -Name $vnic).Status
  }
}

# Runs on a node as a background job: seed static ARP for peer (so pings are real
# UNICAST ICMP, not broadcast ARP), capture frames from $peerMac for $secs while
# sending, and count arrivals. Distinguishes broadcast-floods-but-unicast-drops.
$captureBlock = {
  param($peerMac, $peerIp, $sw, $secs)
  $etl = Join-Path $env:TEMP 'tagflow.etl'
  $txt = Join-Path $env:TEMP 'tagflow.txt'
  if (-not (Get-Command pktmon.exe -ErrorAction SilentlyContinue)) {
    return [pscustomobject]@{ Node=$env:COMPUTERNAME; pktmon='MISSING' }
  }
  $vnic = "vEthernet ($sw)"
  $mac  = $peerMac -replace '[:\-]', '' -replace '(.{2})(?!$)', '$1-'   # normalize to xx-xx-.. form
  # Seed a STATIC neighbor so ping emits unicast ICMP immediately (no ARP dependency). Non-fatal.
  $seed = 'skipped'
  try {
    Remove-NetNeighbor -InterfaceAlias $vnic -IPAddress $peerIp -Confirm:$false -ErrorAction SilentlyContinue
    New-NetNeighbor -InterfaceAlias $vnic -IPAddress $peerIp -LinkLayerAddress $mac -State Permanent -ErrorAction Stop | Out-Null
    $seed = 'ok'
  } catch { $seed = "seedfail: $($_.Exception.Message)" }
  cmd /c "pktmon stop" *>$null
  Remove-Item $etl,$txt -ErrorAction SilentlyContinue
  cmd /c "pktmon filter remove" *>$null
  cmd /c "pktmon filter add PEER -m $mac" *>$null
  cmd /c "pktmon start --capture --file-name `"$etl`" --pkt-size 128" *>$null
  # Emit unicast ICMP fast (static neighbor set), 100ms cap so unanswered pings don't stall.
  $sent = 30
  cmd /c "ping -n $sent -w 100 $peerIp" *>$null
  Start-Sleep -Seconds 2
  cmd /c "pktmon stop" *>$null
  cmd /c "pktmon format `"$etl`" -o `"$txt`"" *>$null
  cmd /c "pktmon filter remove" *>$null
  Remove-NetNeighbor -InterfaceAlias $vnic -IPAddress $peerIp -Confirm:$false -ErrorAction SilentlyContinue
  $t = (Get-Content $txt -Raw -ErrorAction SilentlyContinue)
  $macFlat = ($mac -replace '-', '')
  $hits = 0
  if ($t) {
    $hits = ([regex]::Matches($t, [regex]::Escape($mac), 'IgnoreCase')).Count
    if ($hits -eq 0) { $hits = ([regex]::Matches($t, [regex]::Escape($macFlat), 'IgnoreCase')).Count }
  }
  [pscustomobject]@{
    Node          = $env:COMPUTERNAME
    PeerMac       = $mac
    Seed          = $seed
    IcmpSent      = $sent
    FramesFromPeer= $hits
    Verdict       = if ($hits -gt 0) { 'TAG FLOWS (peer frames arrived)' } else { 'NO PEER FRAMES (tag not crossing to this node)' }
  }
}

$cleanupBlock = {
  param($sw)
  cmd /c "pktmon stop" *>$null
  cmd /c "pktmon filter remove" *>$null
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
  $a | Format-List | Out-String
  $b | Format-List | Out-String
  Start-Sleep -Seconds 2

  "== Capturing on each node for peer's frames while both send ($Seconds s) =="
  # Each node captures the OTHER node's vNIC MAC and pings the other node's IP.
  $jA = Invoke-Command -Session $sA -ScriptBlock $captureBlock -ArgumentList $b.Mac,$IpB,$SwitchName,$Seconds -AsJob
  $jB = Invoke-Command -Session $sB -ScriptBlock $captureBlock -ArgumentList $a.Mac,$IpA,$SwitchName,$Seconds -AsJob
  $null = Wait-Job $jA,$jB -Timeout ($Seconds + 60)
  $rA = Receive-Job $jA
  $rB = Receive-Job $jB
  Remove-Job $jA,$jB -Force -ErrorAction SilentlyContinue

  "== FRAME ARRIVAL RESULTS =="
  @($rA,$rB) | Format-Table Node,Seed,IcmpSent,FramesFromPeer,Verdict -Auto | Out-String

  $aSees = [int]($rA.FramesFromPeer)
  $bSees = [int]($rB.FramesFromPeer)
  ""
  "INTERPRETATION:"
  if ($aSees -gt 0 -and $bSees -gt 0) {
    "  Frames cross BOTH ways -> tag flows + switch forwards VLAN $Vlan. ARP failure would then be a host/ARP-reply issue, not the fabric."
  } elseif ($aSees -eq 0 -and $bSees -eq 0) {
    "  ZERO frames either way -> tagged VLAN $Vlan is NOT traversing the switch. Either hosts are not egressing tagged, or the switch is not forwarding $Vlan between these ports."
  } else {
    "  ASYMMETRIC ($($a.Node) sees $aSees, $($b.Node) sees $bSees) -> one direction of VLAN $Vlan forwarding is broken on the switch (per-port VLAN membership)."
  }
}
finally {
  "== Cleanup: removing temp vSwitch + pktmon filters on both nodes =="
  Invoke-Command -Session $sA -ScriptBlock $cleanupBlock -ArgumentList $SwitchName | Format-Table -Auto | Out-String
  Invoke-Command -Session $sB -ScriptBlock $cleanupBlock -ArgumentList $SwitchName | Format-Table -Auto | Out-String
  Remove-PSSession $sA,$sB -ErrorAction SilentlyContinue
  "Done. Storage NICs returned to standalone."
}
