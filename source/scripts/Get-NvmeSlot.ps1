param([string[]]$Nodes = @('04','05'))
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
    $nvme = Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue |
      Where-Object { $_.FriendlyName -match 'NVM Express Controller' }
    $rows = foreach ($d in $nvme) {
      $loc  = (Get-PnpDeviceProperty -InstanceId $d.InstanceId -KeyName 'DEVPKEY_Device_LocationInfo' -ErrorAction SilentlyContinue).Data
      $lpaths = (Get-PnpDeviceProperty -InstanceId $d.InstanceId -KeyName 'DEVPKEY_Device_LocationPaths' -ErrorAction SilentlyContinue).Data
      $ui   = (Get-PnpDeviceProperty -InstanceId $d.InstanceId -KeyName 'DEVPKEY_Device_UINumber' -ErrorAction SilentlyContinue).Data  # ACPI _SUN = physical slot
      # parent root port + its location (root ports usually carry the "Slot N" label on Dell)
      $parent = (Get-PnpDeviceProperty -InstanceId $d.InstanceId -KeyName 'DEVPKEY_Device_Parent' -ErrorAction SilentlyContinue).Data
      $pLoc = $null; $pUi = $null
      if ($parent) {
        $pLoc = (Get-PnpDeviceProperty -InstanceId $parent -KeyName 'DEVPKEY_Device_LocationInfo' -ErrorAction SilentlyContinue).Data
        $pUi  = (Get-PnpDeviceProperty -InstanceId $parent -KeyName 'DEVPKEY_Device_UINumber' -ErrorAction SilentlyContinue).Data
      }
      [pscustomobject]@{
        VenDev    = ($d.InstanceId -split '\\')[1]
        Location  = $loc
        SlotSUN   = $ui
        ParentLoc = $pLoc
        ParentSlot= $pUi
        LocPath   = ($lpaths | Select-Object -First 1)
      }
    }
    $rows | Format-List
  }
  Remove-PSSession $s
}
