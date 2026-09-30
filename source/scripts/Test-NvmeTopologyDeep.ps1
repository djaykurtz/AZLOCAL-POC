param([string[]]$Nodes = @('05','03'))
$pw = ConvertTo-SecureString ((Get-Content "$PSScriptRoot\..\.creds\azloc-local-admin.cred" -Raw).Trim())
foreach ($n in $Nodes) {
  $nn = '{0:00}' -f [int]$n
  $short = "azl-node-$nn"; $fqdn = "$short.lab.example.com"
  $c = [pscredential]::new("$short\Administrator", $pw)
  $s = New-PSSession -ComputerName $fqdn -Credential $c -Authentication Negotiate -ErrorAction SilentlyContinue
  if (-not $s) { Write-Host "$short unreachable" -ForegroundColor Red; continue }
  Write-Host "`n================= $short =================" -ForegroundColor Cyan
  Invoke-Command -Session $s -ScriptBlock {
    $ErrorActionPreference = 'Continue'

    "### 1) Every NVMe controller (PnP), with status + problem code ###"
    Get-PnpDevice -Class 'SCSIAdapter','System' -ErrorAction SilentlyContinue |
      Where-Object { $_.FriendlyName -match 'NVM Express|NVMe' } |
      Select-Object Status, Class, FriendlyName, InstanceId |
      Format-Table -Auto | Out-String | Write-Host

    "### 2) ANY device in a problem/error state (yellow-bang) — would show a seated-but-not-started drive ###"
    Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue |
      Where-Object { $_.Status -ne 'OK' -and $_.Class -in 'SCSIAdapter','System','DiskDrive','Unknown' } |
      Select-Object Status, Class, FriendlyName, InstanceId |
      Format-Table -Auto | Out-String | Write-Host

    "### 3) PCIe bridges/root-ports and their downstream child count (empty branch = bifurcated lane w/ nothing enumerated) ###"
    $bridges = Get-PnpDevice -PresentOnly -Class 'System' -ErrorAction SilentlyContinue |
      Where-Object { $_.FriendlyName -match 'PCI Express (Root Port|Upstream|Downstream)|PCI-to-PCI|PCI Express Port' }
    $bridgeRows = foreach ($b in $bridges) {
      $children = Get-PnpDeviceProperty -InstanceId $b.InstanceId -KeyName 'DEVPKEY_Device_Children' -ErrorAction SilentlyContinue
      $kids = @($children.Data)
      [pscustomobject]@{
        Bridge   = ($b.FriendlyName -replace 'Intel\(R\) ','')
        Children = $kids.Count
        ChildIds = (($kids | ForEach-Object { ($_ -split '\\')[1] }) -join ',')
      }
    }
    $bridgeRows | Where-Object { $_.Bridge -match 'Express' } | Format-Table -Auto | Out-String | Write-Host

    "### 4) Total NVMe controllers vs physical disks (sanity) ###"
    $ctrls = @(Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue | Where-Object { $_.FriendlyName -match 'NVM Express Controller' })
    $disks = @(Get-Disk | Where-Object { $_.BusType -eq 'NVMe' })
    "NVMe controllers present: $($ctrls.Count) | NVMe disks enumerated: $($disks.Count)"
    "  (expect: controllers == disks; boot + data)"
  }
  Remove-PSSession $s
}
