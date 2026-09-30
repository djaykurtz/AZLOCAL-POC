<#
.SYNOPSIS
  Node-side pre-deploy readiness checks for the remaining verifiable gates:
  DNS resolution of the AD domain, time sync/skew, OS build symmetry, and local
  Administrator presence. Read-only over WinRM.
#>
[CmdletBinding()]
param(
  [string[]] $Nodes = @('azl-node-01','azl-node-02','azl-node-04','azl-node-06'),
  [string]   $DnsSuffix = 'lab.example.com',
  [string]   $AdDomain = 'corp.example.com',
  [string]   $CredPath = '.\.creds\azloc-local-admin.cred'
)
$ErrorActionPreference = 'Stop'
$pw  = ConvertTo-SecureString ((Get-Content $CredPath -Raw).Trim())
$opt = New-PSSessionOption -OpenTimeout 15000 -OperationTimeout 120000

$blk = {
  param($adDomain)
  $dns = try {
    $r = Resolve-DnsName -Name $adDomain -Type A -ErrorAction Stop | Where-Object { $_.IPAddress } | Select-Object -First 1
    if ($r) { "OK ($($r.IPAddress))" } else { 'NO-A-RECORD' }
  } catch { "FAIL $($_.Exception.Message.Split([char]10)[0])" }
  $dnsServers = (Get-DnsClientServerAddress -AddressFamily IPv4 | Where-Object { $_.ServerAddresses } | Select-Object -First 1).ServerAddresses -join ','
  $w32 = try { (w32tm /query /status 2>&1 | Select-String 'Source|Last Successful' | ForEach-Object { $_.ToString().Trim() }) -join ' | ' } catch { 'n/a' }
  [pscustomobject]@{
    Node       = $env:COMPUTERNAME
    OSBuild    = (Get-CimInstance Win32_OperatingSystem).Version
    UtcNow     = (Get-Date).ToUniversalTime().ToString('HH:mm:ss')
    DnsServers = $dnsServers
    ResolveAD  = $dns
    TimeSource = $w32
    LocalAdmin = try { if (Get-LocalUser -Name 'Administrator' -ErrorAction Stop) { 'present' } } catch { 'MISSING' }
  }
}

$rows = foreach ($n in $Nodes) {
  $cred = [pscredential]::new("$n\Administrator", $pw)
  try { Invoke-Command -ComputerName "$n.$DnsSuffix" -Credential $cred -SessionOption $opt -ScriptBlock $blk -ArgumentList $AdDomain -ErrorAction Stop }
  catch { [pscustomobject]@{ Node=$n; OSBuild='ERR'; UtcNow=''; DnsServers=''; ResolveAD=$_.Exception.Message.Split([char]10)[0]; TimeSource=''; LocalAdmin='' } }
}

$rows | Format-Table Node,OSBuild,UtcNow,DnsServers,ResolveAD,LocalAdmin -Auto | Out-String -Width 220
"--- Time source detail ---"
$rows | ForEach-Object { "{0}: {1}" -f $_.Node, $_.TimeSource }
""
$builds = $rows | Where-Object OSBuild -ne 'ERR' | Select-Object -ExpandProperty OSBuild -Unique
"OS build symmetry: $(if ($builds.Count -le 1) { 'UNIFORM ('+($builds -join ',')+')' } else { 'MISMATCH: '+($builds -join ' vs ') })"
$adOk = ($rows | Where-Object { $_.ResolveAD -like 'OK*' }).Count
"AD domain resolvable from: $adOk / $($rows.Count) nodes"
