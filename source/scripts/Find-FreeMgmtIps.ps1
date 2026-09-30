<#
.SYNOPSIS
  Find candidate FREE contiguous IPs on the management subnet by ARP-sweeping from a node.

.DESCRIPTION
  Runs on a cluster node (which sits on the management subnet). For each candidate IP it
  triggers ARP resolution (works even though ICMP is firewalled - ARP is L2, below the host
  firewall), then reads Get-NetNeighbor. An IP that resolves to a real MAC is IN USE; one that
  stays Incomplete / has no neighbor entry is APPARENTLY FREE. Then it reports the longest
  contiguous free runs so you can pick a block for the Azure Local infrastructure pool.

  CAVEAT: this shows what is *responding right now*, not what is *reserved but offline*. Confirm
  any candidate block against your IPAM / allocation records before reserving it.
#>
[CmdletBinding()]
param(
  [string] $Node = 'azl-node-01',
  [string] $DnsSuffix = 'lab.example.com',
  [string] $Subnet = '10.10.1',
  [int]    $First = 193,
  [int]    $Last  = 254,
  [int]    $NeededBlock = 6,
  [string] $CredPath = '.\.creds\azloc-local-admin.cred'
)
$ErrorActionPreference = 'Stop'
$pw   = ConvertTo-SecureString ((Get-Content $CredPath -Raw).Trim())
$cred = [pscredential]::new("$Node\Administrator", $pw)
$opt  = New-PSSessionOption -OpenTimeout 15000 -OperationTimeout 300000

$blk = {
  param($subnet, $first, $last)
  # management interface (the one holding the subnet IP)
  $mgmt = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $_.IPAddress -like "$subnet.*" } | Select-Object -First 1
  if (-not $mgmt) { return [pscustomobject]@{ Error = "No interface on $subnet.* found on this node" } }
  $ifIndex = $mgmt.InterfaceIndex
  $selfIp  = $mgmt.IPAddress
  $ips = $first..$last | ForEach-Object { "$subnet.$_" }
  # clear stale neighbor entries for the range, then fire ARP via fast pings
  foreach ($ip in $ips) { Remove-NetNeighbor -InterfaceIndex $ifIndex -IPAddress $ip -Confirm:$false -ErrorAction SilentlyContinue }
  $ips | ForEach-Object { Start-Process -FilePath ping -ArgumentList "-n 1 -w 120 $_" -WindowStyle Hidden }
  Start-Sleep -Seconds 6
  $nb = Get-NetNeighbor -InterfaceIndex $ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue
  $rows = foreach ($ip in $ips) {
    $entry = $nb | Where-Object { $_.IPAddress -eq $ip } | Select-Object -First 1
    $inUse = $false; $mac = ''
    if ($entry -and $entry.State -match 'Reachable|Stale|Delay|Probe' -and $entry.LinkLayerAddress -and $entry.LinkLayerAddress -ne '00-00-00-00-00-00') { $inUse = $true; $mac = $entry.LinkLayerAddress }
    [pscustomobject]@{ IP=$ip; InUse=$inUse; Mac=$mac; State=($entry.State) }
  }
  [pscustomobject]@{ SelfIp=$selfIp; IfIndex=$ifIndex; Rows=$rows }
}

$sess = New-PSSession -ComputerName "$Node.$DnsSuffix" -Credential $cred -SessionOption $opt
try {
  $res = Invoke-Command -Session $sess -ScriptBlock $blk -ArgumentList $Subnet,$First,$Last
} finally { Remove-PSSession $sess -ErrorAction SilentlyContinue }

if ($res.Error) { Write-Host $res.Error -ForegroundColor Red; return }
"Swept $Subnet.$First - $Subnet.$Last from $Node (self=$($res.SelfIp))"
$used = $res.Rows | Where-Object InUse
$free = $res.Rows | Where-Object { -not $_.InUse }
"In use: $($used.Count)   Apparently free: $($free.Count)"
""
"IN USE:"
$used | ForEach-Object { "  {0}  {1}" -f $_.IP, $_.Mac }

# find contiguous free runs
$freeNums = $free | ForEach-Object { [int]($_.IP.Split('.')[-1]) } | Sort-Object
$runs = @(); $start = $null; $prev = $null
foreach ($n in $freeNums) {
  if ($null -eq $start) { $start = $n; $prev = $n; continue }
  if ($n -eq $prev + 1) { $prev = $n; continue }
  $runs += [pscustomobject]@{ Start="$Subnet.$start"; End="$Subnet.$prev"; Count=($prev-$start+1) }
  $start = $n; $prev = $n
}
if ($null -ne $start) { $runs += [pscustomobject]@{ Start="$Subnet.$start"; End="$Subnet.$prev"; Count=($prev-$start+1) } }

""
"CONTIGUOUS FREE RUNS (apparent):"
$runs | Sort-Object Count -Descending | Format-Table -Auto | Out-String -Width 120
$fit = $runs | Where-Object Count -ge $NeededBlock | Sort-Object { [int]($_.Start.Split('.')[-1]) } | Select-Object -First 1
if ($fit) {
  $s = [int]($fit.Start.Split('.')[-1])
  "SUGGESTED BLOCK for the $NeededBlock-IP infra pool: $Subnet.$s - $Subnet.$($s+$NeededBlock-1)  (first IP $Subnet.$s = failover cluster)"
  "  -> CONFIRM against IPAM before reserving. Probe shows live-response only."
} else {
  "No apparent free run >= $NeededBlock in the swept range. Widen -First/-Last or check IPAM."
}
