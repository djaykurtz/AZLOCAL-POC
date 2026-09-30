<#
.SYNOPSIS
  Post-imaging bring-up for an Azure Local node, run from platform team DevBox
  via WinRM the moment smart-hands hands the box back.

.DESCRIPTION
  One-shot script that:
    1. Verifies WSMan reachability + credentials.
    2. Captures hardware inventory (CPU, RAM, disks, NICs, OS build).
    3. Optionally sets a static IPv4 on the chosen management NIC.
    4. Sets time zone to Pacific Standard Time (lab is Portland).
    5. Configures DNS suffix to lab.example.com.
    6. Opens the firewall rule for Azure Local OS management (TCP 30301).
    7. Writes a transcript + a structured inventory JSON to .\out\.

  Does NOT do Arc onboarding, domain join, or cluster prep - those are
  separate steps after this script reports a clean run.

.PARAMETER NodeFqdn
  Fully qualified DNS name of the node. Example:
    azl-node-01.lab.example.com

.PARAMETER LocalAdminCredential
  Local Administrator credentials set by smart hands at imaging time.
  Pass as a PSCredential. If omitted, the script prompts.

.PARAMETER StaticIPv4
  Optional static IP to assign on the management NIC. Skip to keep DHCP.

.PARAMETER PrefixLength
  CIDR mask length for the static IP. Default 24. Override per the
  Networking team's answer to "what is the subnet mask for
  10.10.1.187-192?".

.PARAMETER DefaultGateway
  Default gateway for the static IP. Required if StaticIPv4 is set.

.PARAMETER DnsServers
  One or more DNS server IPs. If omitted, leaves existing DNS untouched.

.EXAMPLE
  # DHCP path, just inventory + WinRM verify
  .\node01-postimage.ps1 -NodeFqdn azl-node-01.lab.example.com

.EXAMPLE
  # Static IP path
  .\node01-postimage.ps1 `
    -NodeFqdn azl-node-01.lab.example.com `
    -StaticIPv4 10.10.1.187 -PrefixLength 26 `
    -DefaultGateway 10.10.1.129 `
    -DnsServers 10.20.10.50, 10.20.10.51
#>

[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)]
  [string]$NodeFqdn,

  [System.Management.Automation.PSCredential]$LocalAdminCredential,

  [string]$StaticIPv4,
  [int]$PrefixLength = 24,
  [string]$DefaultGateway,
  [string[]]$DnsServers,

  [string]$TimeZoneId = 'Pacific Standard Time',
  [string]$DnsSuffix  = 'lab.example.com'
)

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path -Parent $PSScriptRoot
$outDir = Join-Path $RepoRoot 'out'
New-Item -ItemType Directory -Path $outDir -Force | Out-Null
$ts = (Get-Date).ToString('yyyyMMdd-HHmmss')
$shortName = ($NodeFqdn -split '\.')[0]
$transcriptPath = Join-Path $outDir "$shortName-postimage-$ts.log"
$inventoryPath  = Join-Path $outDir "$shortName-inventory-$ts.json"
Start-Transcript -Path $transcriptPath -Force | Out-Null

try {
  Write-Host "== Post-imaging bring-up: $NodeFqdn ==" -ForegroundColor Cyan

  if (-not $LocalAdminCredential) {
    $LocalAdminCredential = Get-Credential -UserName 'Administrator' `
      -Message "Local admin password for $NodeFqdn"
  }

  # 1. Reachability
  Write-Host "`n[1/7] Test-WSMan handshake..."
  $wsman = Test-WSMan -ComputerName $NodeFqdn -Authentication Negotiate `
    -Credential $LocalAdminCredential -ErrorAction Stop
  Write-Host "      OK. ProductVendor: $($wsman.ProductVendor), Build: $($wsman.BuildVersion)"

  # 2. Open session
  Write-Host "`n[2/7] Open PSSession..."
  $session = New-PSSession -ComputerName $NodeFqdn -Credential $LocalAdminCredential
  Write-Host "      Session $($session.Id) -> $($session.ComputerName)"

  # 3. Inventory
  Write-Host "`n[3/7] Hardware + OS inventory..."
  $inventory = Invoke-Command -Session $session -ScriptBlock {
    $ci = Get-ComputerInfo
    [pscustomobject]@{
      Hostname           = $ci.CsName
      Manufacturer       = $ci.CsManufacturer
      Model              = $ci.CsModel
      Serial             = (Get-CimInstance Win32_BIOS).SerialNumber
      Bios               = (Get-CimInstance Win32_BIOS).SMBIOSBIOSVersion
      OsName             = $ci.OsName
      OsVersion          = $ci.OsVersion
      OsBuildNumber      = $ci.OsBuildNumber
      InstallDate        = $ci.OsInstallDate
      TotalPhysicalGB    = [math]::Round($ci.CsTotalPhysicalMemory / 1GB, 1)
      LogicalProcessors  = $ci.CsNumberOfLogicalProcessors
      Processors         = (Get-CimInstance Win32_Processor) | ForEach-Object {
        @{
          Name              = $_.Name
          Cores             = $_.NumberOfCores
          LogicalProcessors = $_.NumberOfLogicalProcessors
          MaxClockMHz       = $_.MaxClockSpeed
        }
      }
      Disks              = Get-PhysicalDisk | ForEach-Object {
        @{
          DeviceId      = $_.DeviceId
          FriendlyName  = $_.FriendlyName
          MediaType     = "$($_.MediaType)"
          BusType       = "$($_.BusType)"
          SizeGB        = [math]::Round($_.Size / 1GB, 1)
          HealthStatus  = "$($_.HealthStatus)"
          CanPool       = $_.CanPool
        }
      }
      NetAdapters        = Get-NetAdapter | Where-Object Status -eq 'Up' | ForEach-Object {
        @{
          Name                = $_.Name
          InterfaceDescription = $_.InterfaceDescription
          LinkSpeed           = $_.LinkSpeed
          MacAddress          = $_.MacAddress
          ifIndex             = $_.ifIndex
        }
      }
      IpAddresses        = Get-NetIPAddress -AddressFamily IPv4 |
        Where-Object { $_.IPAddress -notlike '169.254.*' -and $_.IPAddress -ne '127.0.0.1' } |
        ForEach-Object {
          @{
            InterfaceAlias = $_.InterfaceAlias
            IPAddress      = $_.IPAddress
            PrefixLength   = $_.PrefixLength
            PrefixOrigin   = "$($_.PrefixOrigin)"
            SuffixOrigin   = "$($_.SuffixOrigin)"
          }
        }
      DnsServers         = (Get-DnsClientServerAddress -AddressFamily IPv4 |
        Where-Object { $_.ServerAddresses }) | ForEach-Object {
          @{ InterfaceAlias = $_.InterfaceAlias; Servers = $_.ServerAddresses }
        }
      TimeZone           = (Get-TimeZone).Id
      DomainJoinStatus   = if ($ci.CsPartOfDomain) { "Domain: $($ci.CsDomain)" } else { 'Workgroup' }
    }
  }
  $inventory | ConvertTo-Json -Depth 6 | Out-File -FilePath $inventoryPath -Encoding ascii
  Write-Host "      Inventory -> $inventoryPath"

  # 4. Time zone
  Write-Host "`n[4/7] Set time zone to '$TimeZoneId'..."
  Invoke-Command -Session $session -ScriptBlock {
    param($tz) Set-TimeZone -Id $tz
  } -ArgumentList $TimeZoneId
  Write-Host "      OK"

  # 5. DNS suffix
  Write-Host "`n[5/7] Set primary DNS suffix to '$DnsSuffix'..."
  Invoke-Command -Session $session -ScriptBlock {
    param($suffix)
    Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters' `
      -Name 'Domain' -Value $suffix
    Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters' `
      -Name 'NV Domain' -Value $suffix
  } -ArgumentList $DnsSuffix
  Write-Host "      OK (takes effect on next reboot)"

  # 6. Optional: static IP
  if ($StaticIPv4) {
    Write-Host "`n[6/7] Set static IPv4 $StaticIPv4/$PrefixLength gw=$DefaultGateway..."
    if (-not $DefaultGateway) { throw "DefaultGateway is required when StaticIPv4 is set." }
    Invoke-Command -Session $session -ScriptBlock {
      param($ip, $prefix, $gw, $dns)
      $adapter = Get-NetAdapter | Where-Object Status -eq 'Up' | Select-Object -First 1
      if (-not $adapter) { throw "No 'Up' adapter found on this node." }
      # Remove existing static and DHCP-assigned addresses on this adapter
      Get-NetIPAddress -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Remove-NetIPAddress -Confirm:$false -ErrorAction SilentlyContinue
      Remove-NetRoute -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4 -Confirm:$false `
        -ErrorAction SilentlyContinue
      Set-NetIPInterface -InterfaceIndex $adapter.ifIndex -Dhcp Disabled
      New-NetIPAddress -InterfaceIndex $adapter.ifIndex -IPAddress $ip `
        -PrefixLength $prefix -DefaultGateway $gw | Out-Null
      if ($dns) {
        Set-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex -ServerAddresses $dns
      }
    } -ArgumentList $StaticIPv4, $PrefixLength, $DefaultGateway, $DnsServers
    Write-Host "      OK. Reconnect may drop briefly; verify with Test-Connection $StaticIPv4."
  } else {
    Write-Host "`n[6/7] Static IP skipped (DHCP retained)."
  }

  # 7. Open Azure Local OS management port 30301
  Write-Host "`n[7/7] Open inbound TCP 30301 (Azure Local OS management)..."
  Invoke-Command -Session $session -ScriptBlock {
    $rule = Get-NetFirewallRule -DisplayName 'Azure Local OS Mgmt 30301' -ErrorAction SilentlyContinue
    if (-not $rule) {
      New-NetFirewallRule -DisplayName 'Azure Local OS Mgmt 30301' `
        -Direction Inbound -Action Allow -Protocol TCP -LocalPort 30301 `
        -Profile Any -Enabled True | Out-Null
    }
  }
  Write-Host "      OK"

  Remove-PSSession $session
  Write-Host "`n== DONE. Transcript: $transcriptPath  Inventory: $inventoryPath ==" `
    -ForegroundColor Green
}
catch {
  Write-Host "`nERROR: $($_.Exception.Message)" -ForegroundColor Red
  throw
}
finally {
  Stop-Transcript | Out-Null
}
