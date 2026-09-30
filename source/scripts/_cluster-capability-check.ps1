# Bounded Arc VM capability check for the cluster. Uses Invoke-WithTimeout so hangs break cleanly.
# Writes results to out/_vm-capability.txt.
. "$PSScriptRoot\Invoke-WithTimeout.ps1"
$rg = 'rg-azlocal-poc-001'
$lines = @()
$lines += "Cluster Arc VM capability check  $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
$lines += ""

$checks = @(
  @{ Label='customlocation'; Script={ az customlocation list -g 'rg-azlocal-poc-001' --query "[].{name:name,prov:provisioningState}" -o tsv 2>&1 } }
  @{ Label='marketplace/gallery images'; Script={ az stack-hci-vm image list -g 'rg-azlocal-poc-001' --query "[].{name:name,os:properties.osType,prov:properties.provisioningState}" -o tsv 2>&1 } }
  @{ Label='logical networks'; Script={ az stack-hci-vm network lnet list -g 'rg-azlocal-poc-001' --query "[].{name:name,prov:properties.provisioningState}" -o tsv 2>&1 } }
  @{ Label='existing VMs'; Script={ az stack-hci-vm list -g 'rg-azlocal-poc-001' --query "[].{name:name,prov:provisioningState}" -o tsv 2>&1 } }
)

foreach ($c in $checks) {
  Write-Host "checking $($c.Label) ..."
  $r = Invoke-WithTimeout -TimeoutSec 90 -Label $c.Label -Script $c.Script
  $lines += "== $($c.Label)  (took $($r.DurationSec)s, timedOut=$($r.TimedOut)) =="
  $lines += ($r.Output | ForEach-Object { "$_" })
  $lines += ""
}

$lines | Out-File .\out\_vm-capability.txt -Encoding utf8
Write-Host "DONE -> out\_vm-capability.txt"
Get-Content .\out\_vm-capability.txt
