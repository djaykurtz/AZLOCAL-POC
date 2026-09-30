<#
.SYNOPSIS
  VALID tagged storage-fabric test using the SAME 802.1Q path Azure Local uses.

.DESCRIPTION
  The physical-adapter VlanID property does NOT reliably emit 802.1Q tags on
  Mellanox WinOF-2, so scripts\Test-StorageFabric.ps1 cannot validate a TAGGED
  fabric. This test instead does it the supported way:
    - creates a TEMP external vSwitch on the storage NIC (Port3) with a host vNIC
    - tags that host vNIC with Set-VMNetworkAdapterVlan -ManagementOS -Access -VlanId
      (real 802.1Q tagging - exactly how Network ATC tags storage at deploy)
    - assigns a test IP, then checks ARP/ping node A -> node B
    - ALWAYS removes the temp vSwitch in a finally block (Port3 returns to standalone)
  ARP state is the definitive L2 verdict. Storage NIC only - management (WinRM on
  the Broadcom/CORP NIC) is untouched.

.NOTES
  ASCII only. Local, reversible. Requires Hyper-V (present on Azure Local OS) + WinRM.
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
  $r = [ordered]@{ Node = $env:COMPUTERNAME; NIC = $nic }
  # Clean any prior test switch
  Get-VMSwitch -Name $sw -ErrorAction SilentlyContinue | Remove-VMSwitch -Force -ErrorAction SilentlyContinue
  # Create temp external vSwitch on the storage NIC with a host vNIC
  New-VMSwitch -Name $sw -NetAdapterName $nic -AllowManagementOS $true -ErrorAction Stop | Out-Null
  $vnic = "vEthernet ($sw)"
  # Real 802.1Q tag on the host vNIC (same as Network ATC)
  Set-VMNetworkAdapterVlan -ManagementOS -VMNetworkAdapterName $sw -Access -VlanId $vlan -ErrorAction Stop
  Start-Sleep -Seconds 3
  # Assign test IP
  Get-NetIPAddress -InterfaceAlias $vnic -AddressFamily IPv4 -ErrorAction SilentlyContinue |
    Where-Object { $_.IPAddress -like '169.254.*' -or $_.IPAddress -eq $ip } | Remove-NetIPAddress -Confirm:$false -ErrorAction SilentlyContinue
  New-NetIPAddress -InterfaceAlias $vnic -IPAddress $ip -PrefixLength $prefix -ErrorAction Stop | Out-Null
  $r.Switch  = (Get-VMSwitch -Name $sw).Name
  $r.VlanSet = (Get-VMNetworkAdapterVlan -ManagementOS -VMNetworkAdapterName $sw).AccessVlanId
  $r.vNIC    = $vnic
  $r.TestIP  = $ip
  $r.Link    = (Get-NetAdapter -Name $vnic).Status
  [pscustomobject]$r
}

$testBlock = {
  param($vnic, $peerIp)
  Remove-NetNeighbor -InterfaceAlias $vnic -IPAddress $peerIp -Confirm:$false -ErrorAction SilentlyContinue
  $ping = Test-Connection -ComputerName $peerIp -Count 3 -Quiet -ErrorAction SilentlyContinue
  Start-Sleep -Seconds 1
  $nb = Get-NetNeighbor -InterfaceAlias $vnic -IPAddress $peerIp -ErrorAction SilentlyContinue
  [pscustomobject]@{
    Node        = $env:COMPUTERNAME
    vNIC        = $vnic
    PingReply   = [bool]$ping
    ArpState    = if ($nb) { "$($nb.State)" } else { 'None' }
    ArpMac      = if ($nb) { $nb.LinkLayerAddress } else { '' }
  }
}

$cleanupBlock = {
  param($sw)
  $existed = [bool](Get-VMSwitch -Name $sw -ErrorAction SilentlyContinue)
  Get-VMSwitch -Name $sw -ErrorAction SilentlyContinue | Remove-VMSwitch -Force -ErrorAction SilentlyContinue
  [pscustomobject]@{ Node = $env:COMPUTERNAME; Removed = $existed; StillPresent = [bool](Get-VMSwitch -Name $sw -ErrorAction SilentlyContinue) }
}

$sA = New-PSSession -ComputerName $NodeA -Credential $credA -SessionOption $opt
$sB = New-PSSession -ComputerName $NodeB -Credential $credB -SessionOption $opt
try {
  "== Applying temp vSwitch + 802.1Q VLAN $Vlan tag + test IPs =="
  Invoke-Command -Session $sA -ScriptBlock $applyBlock -ArgumentList $Port,$SwitchName,$Vlan,$IpA,$Prefix | Format-List | Out-String
  Invoke-Command -Session $sB -ScriptBlock $applyBlock -ArgumentList $Port,$SwitchName,$Vlan,$IpB,$Prefix | Format-List | Out-String
  Start-Sleep -Seconds 3

  "== Test: ARP + ping A->B over the tagged vNIC (definitive VLAN $Vlan check) =="
  $vnicName = "vEthernet ($SwitchName)"
  $res = Invoke-Command -Session $sA -ScriptBlock $testBlock -ArgumentList $vnicName,$IpB
  $res | Format-List | Out-String

  $pass = ($res.ArpState -match 'Reachable|Stale') -and ($res.ArpMac -and $res.ArpMac -ne '00-00-00-00-00-00')
  "RESULT: TAGGED_VLAN${Vlan}_L2pass=$pass  (ArpState=$($res.ArpState), ArpMac=$($res.ArpMac), Ping=$($res.PingReply))"
}
finally {
  "== Cleanup: removing temp vSwitch on both nodes =="
  Invoke-Command -Session $sA -ScriptBlock $cleanupBlock -ArgumentList $SwitchName | Format-Table -Auto | Out-String
  Invoke-Command -Session $sB -ScriptBlock $cleanupBlock -ArgumentList $SwitchName | Format-Table -Auto | Out-String
  Remove-PSSession $sA,$sB -ErrorAction SilentlyContinue
  "Done. Storage NICs returned to standalone."
}
