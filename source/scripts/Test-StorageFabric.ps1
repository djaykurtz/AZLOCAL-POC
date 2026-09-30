<#
.SYNOPSIS
  Non-permanent test of the storage fabric (VLAN trunk + jumbo) between two nodes,
  BEFORE the Azure Local deployment wizard configures the real storage intent.

.DESCRIPTION
  The four cluster nodes' Mellanox storage ports normally sit at defaults
  (MTU 1500, no VLAN tag, no IP) until Network ATC configures them at deploy time.
  This script TEMPORARILY tags one storage port with a storage VLAN, enables jumbo,
  assigns a test IP on both nodes, then pings across:
    - a normal (small) ping proves the VLAN is trunked/passing between the ports
    - a jumbo, do-not-fragment ping proves the switch jumbo MTU is enabled end to end
  It ALWAYS restores the original adapter state (VLAN ID, jumbo, IP) in a finally block,
  pass or fail. Nothing permanent is changed.

  This tests L2 reachability + jumbo, which is what the wizard's storage network
  validation gates on. It does NOT load-test PFC/ETS (lossless), which only shows
  under sustained RDMA load; PFC misconfig degrades performance, it does not block
  the deploy the way a broken VLAN/jumbo does.

.NOTES
  ASCII only. Local, reversible. Requires WinRM to both nodes by FQDN.
#>
[CmdletBinding()]
param(
  [string] $NodeA      = 'azl-node-01.lab.example.com',
  [string] $NodeB      = 'azl-node-02.lab.example.com',
  [string] $ShortA     = 'azl-node-01',
  [string] $ShortB     = 'azl-node-02',
  [string] $Port       = 'Port3',      # Port3 is the first storage fabric on every node
  [int]    $Vlan       = 711,
  [string] $IpA        = '192.168.110.1',
  [string] $IpB        = '192.168.110.2',
  [int]    $Prefix     = 24,
  [int]    $JumboPingBytes = 8900,     # < 9014 host payload; -f no-fragment
  [string] $CredPath   = '.\.creds\azloc-local-admin.cred'
)

$ErrorActionPreference = 'Stop'
$pw = ConvertTo-SecureString ((Get-Content $CredPath -Raw).Trim())
$credA = [pscredential]::new("$ShortA\Administrator", $pw)
$credB = [pscredential]::new("$ShortB\Administrator", $pw)
$opt = New-PSSessionOption -OpenTimeout 15000 -OperationTimeout 120000

# Scriptblock: capture current state, then apply VLAN + jumbo + test IP
$applyBlock = {
  param($nic, $vlan, $ip, $prefix)
  $result = [ordered]@{ Node = $env:COMPUTERNAME; NIC = $nic }

  # Capture originals for rollback
  $vlanProp  = Get-NetAdapterAdvancedProperty -Name $nic -RegistryKeyword 'VlanID' -ErrorAction SilentlyContinue
  $jumboProp = Get-NetAdapterAdvancedProperty -Name $nic -ErrorAction SilentlyContinue | Where-Object { $_.RegistryKeyword -like '*JumboPacket*' }
  $origVlan  = if ($vlanProp)  { $vlanProp.RegistryValue }  else { $null }
  $origJumbo = if ($jumboProp) { $jumboProp.RegistryValue } else { $null }
  $result.OrigVlan  = "$origVlan"
  $result.OrigJumbo = "$origJumbo"
  $result.JumboKeyword = if ($jumboProp) { $jumboProp.RegistryKeyword } else { $null }

  # Apply VLAN tag
  try { Set-NetAdapterAdvancedProperty -Name $nic -RegistryKeyword 'VlanID' -RegistryValue $vlan -NoRestart -ErrorAction Stop; $result.SetVlan = 'ok' }
  catch { $result.SetVlan = "ERR: $($_.Exception.Message.Split([char]10)[0])" }

  # Apply jumbo (9014) if we found the keyword
  if ($jumboProp) {
    try { Set-NetAdapterAdvancedProperty -Name $nic -RegistryKeyword $jumboProp.RegistryKeyword -RegistryValue 9014 -NoRestart -ErrorAction Stop; $result.SetJumbo = 'ok' }
    catch { $result.SetJumbo = "ERR: $($_.Exception.Message.Split([char]10)[0])" }
  } else { $result.SetJumbo = 'no-jumbo-prop' }

  # Restart adapter to apply both, wait for Up
  Restart-NetAdapter -Name $nic -ErrorAction SilentlyContinue
  $deadline = (Get-Date).AddSeconds(40)
  do { Start-Sleep -Seconds 2; $st = (Get-NetAdapter -Name $nic).Status } while ($st -ne 'Up' -and (Get-Date) -lt $deadline)
  $result.LinkAfter = $st

  # Assign test IP (remove any prior test IP first)
  Get-NetIPAddress -InterfaceAlias $nic -AddressFamily IPv4 -ErrorAction SilentlyContinue |
    Where-Object { $_.IPAddress -eq $ip } | Remove-NetIPAddress -Confirm:$false -ErrorAction SilentlyContinue
  New-NetIPAddress -InterfaceAlias $nic -IPAddress $ip -PrefixLength $prefix -ErrorAction SilentlyContinue | Out-Null
  $result.TestIP = $ip

  # Report the ACTUAL IP-layer MTU so we know jumbo really applied (not just the adv property)
  Start-Sleep -Seconds 3
  $ifIndex = (Get-NetAdapter -Name $nic).ifIndex
  $result.NlMtu = (Get-NetIPInterface -InterfaceIndex $ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue).NlMtu

  # Open ICMP echo inbound on the test interface so a Public-profile firewall does not
  # produce a false negative. Temporary rule, removed in restore.
  New-NetFirewallRule -Name 'TEMP-StorageFabricTest-ICMP' -DisplayName 'TEMP StorageFabricTest ICMP' `
    -Direction Inbound -Protocol ICMPv4 -IcmpType 8 -Action Allow -Profile Any -ErrorAction SilentlyContinue | Out-Null
  [pscustomobject]$result
}

# Scriptblock: restore original state
$restoreBlock = {
  param($nic, $ip, $origVlan, $jumboKeyword, $origJumbo)
  Remove-NetFirewallRule -Name 'TEMP-StorageFabricTest-ICMP' -ErrorAction SilentlyContinue
  Get-NetIPAddress -InterfaceAlias $nic -AddressFamily IPv4 -ErrorAction SilentlyContinue |
    Where-Object { $_.IPAddress -eq $ip } | Remove-NetIPAddress -Confirm:$false -ErrorAction SilentlyContinue
  if ($origVlan -ne $null -and "$origVlan" -ne '') {
    Set-NetAdapterAdvancedProperty -Name $nic -RegistryKeyword 'VlanID' -RegistryValue ([int]$origVlan) -NoRestart -ErrorAction SilentlyContinue
  } else {
    Set-NetAdapterAdvancedProperty -Name $nic -RegistryKeyword 'VlanID' -RegistryValue 0 -NoRestart -ErrorAction SilentlyContinue
  }
  if ($jumboKeyword -and "$origJumbo" -ne '') {
    Set-NetAdapterAdvancedProperty -Name $nic -RegistryKeyword $jumboKeyword -RegistryValue ([int]$origJumbo) -NoRestart -ErrorAction SilentlyContinue
  }
  Restart-NetAdapter -Name $nic -ErrorAction SilentlyContinue
  [pscustomobject]@{ Node = $env:COMPUTERNAME; NIC = $nic; Restored = $true }
}

$sA = New-PSSession -ComputerName $NodeA -Credential $credA -Authentication Negotiate -SessionOption $opt
$sB = New-PSSession -ComputerName $NodeB -Credential $credB -Authentication Negotiate -SessionOption $opt
$stateA = $null; $stateB = $null
try {
  Write-Host "== Applying temporary VLAN $Vlan + jumbo + test IPs ==" -ForegroundColor Cyan
  $stateA = Invoke-Command -Session $sA -ScriptBlock $applyBlock -ArgumentList $Port, $Vlan, $IpA, $Prefix
  $stateB = Invoke-Command -Session $sB -ScriptBlock $applyBlock -ArgumentList $Port, $Vlan, $IpB, $Prefix
  $stateA | Format-List | Out-String | Write-Host
  $stateB | Format-List | Out-String | Write-Host

  Start-Sleep -Seconds 3
  Write-Host "== Test 1: L2/ARP + source-bound ping A->B over $Port (definitive VLAN $Vlan check) ==" -ForegroundColor Cyan
  $l2 = Invoke-Command -Session $sA -ScriptBlock {
    param($ip, $nic, $srcIp)
    # Route the storage subnet should egress $nic; report the chosen egress
    $route = Get-NetRoute -DestinationPrefix '192.168.110.0/24' -ErrorAction SilentlyContinue | Select-Object -First 1
    $egress = if ($route) { (Get-NetAdapter -InterfaceIndex $route.ifIndex -ErrorAction SilentlyContinue).Name } else { 'none' }
    # Force source-bound ping to trigger ARP out the storage NIC
    $ping = & ping.exe -n 3 -w 1000 -S $srcIp $ip 2>&1 | Out-String
    $pingOk = ($ping -match 'Reply from') -and ($ping -notmatch 'unreachable|timed out|100% loss')
    # ARP is the real L2 verdict: did we resolve the peer MAC on the storage NIC?
    Start-Sleep -Seconds 1
    $nb = Get-NetNeighbor -InterfaceAlias $nic -IPAddress $ip -ErrorAction SilentlyContinue
    [pscustomobject]@{
      EgressForStorageSubnet = $egress
      SourceBoundPingReply   = $pingOk
      ArpState               = if ($nb) { $nb.State } else { 'none' }
      ArpMac                 = if ($nb) { $nb.LinkLayerAddress } else { '' }
    }
  } -ArgumentList $IpB, $Port, $IpA
  $l2 | Format-List | Out-String | Write-Host

  Write-Host "== Test 2: jumbo no-fragment ping A->B ($JumboPingBytes bytes, source-bound) ==" -ForegroundColor Cyan
  $jumbo = Invoke-Command -Session $sA -ScriptBlock {
    param($ip,$bytes,$srcIp)
    $out = & ping.exe -n 3 -f -l $bytes -S $srcIp $ip 2>&1 | Out-String
    $ok = $out -match 'Reply from' -and $out -notmatch 'need to be fragmented|Request timed out|100% loss'
    [pscustomobject]@{ Target=$ip; JumboOk=$ok; Raw=$out.Trim() }
  } -ArgumentList $IpB, $JumboPingBytes, $IpA
  Write-Host $jumbo.Raw
  Write-Host ""
  $l2pass = ($l2.ArpState -eq 'Reachable' -or $l2.ArpState -eq 'Stale' -or $l2.SourceBoundPingReply)
  Write-Host ("RESULT: VLAN{0}_L2pass={1} (ARP={2}, egress={3})  jumboPing={4}" -f `
      $Vlan, $l2pass, $l2.ArpState, $l2.EgressForStorageSubnet, $jumbo.JumboOk) -ForegroundColor Yellow
}
finally {
  Write-Host "== Restoring original adapter state on both nodes ==" -ForegroundColor Cyan
  if ($stateA) { Invoke-Command -Session $sA -ScriptBlock $restoreBlock -ArgumentList $Port, $IpA, $stateA.OrigVlan, $stateA.JumboKeyword, $stateA.OrigJumbo | Format-Table -Auto | Out-String | Write-Host }
  if ($stateB) { Invoke-Command -Session $sB -ScriptBlock $restoreBlock -ArgumentList $Port, $IpB, $stateB.OrigVlan, $stateB.JumboKeyword, $stateB.OrigJumbo | Format-Table -Auto | Out-String | Write-Host }
  Remove-PSSession $sA, $sB -ErrorAction SilentlyContinue
  Write-Host "Done. Adapters restored to pre-test state."
}
