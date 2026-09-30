# Investigate the container surface on the cluster: AKS on Azure Local (Kubernetes) + the Docker VM path.
# Read-only. Checks providers, CLI extensions, and the AKS Arc command surface. Writes findings to out/.
. "$PSScriptRoot\Invoke-WithTimeout.ps1"
$rg = 'rg-azlocal-poc-001'
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$outFile = ".\out\_container-surface-$stamp.txt"
$lines = @("Container surface investigation  $stamp", "")

$lines += "== Providers relevant to AKS/containers =="
$provs = 'Microsoft.HybridContainerService','Microsoft.KubernetesConfiguration','Microsoft.Kubernetes','Microsoft.ExtendedLocation','Microsoft.ResourceConnector'
$lines += (Invoke-WithTimeout -TimeoutSec 90 -Label 'providers' -Script {
    foreach($p in 'Microsoft.HybridContainerService','Microsoft.KubernetesConfiguration','Microsoft.Kubernetes','Microsoft.ExtendedLocation','Microsoft.ResourceConnector'){
        "{0,-40} {1}" -f $p, (az provider show -n $p --query registrationState -o tsv 2>$null)
    }
}).Output

$lines += ""
$lines += "== CLI extensions installed =="
$lines += (Invoke-WithTimeout -TimeoutSec 40 -Label 'ext' -Script { az extension list --query "[].{name:name,version:version}" -o tsv 2>&1 }).Output

$lines += ""
$lines += "== Try add aksarc extension =="
$lines += (Invoke-WithTimeout -TimeoutSec 120 -Label 'add aksarc' -Script { az extension add --name aksarc --only-show-errors 2>&1; "aksarc add exit=$LASTEXITCODE" }).Output

$lines += ""
$lines += "== aksarc command surface =="
$lines += (Invoke-WithTimeout -TimeoutSec 40 -Label 'aksarc help' -Script { (az aksarc --help 2>&1) | Select-String -Pattern 'Subgroups|Commands|create|list|nodepool|vnet' -Context 0,12 }).Output

$lines += ""
$lines += "== Existing provisioned K8s / AKS Arc clusters =="
$lines += (Invoke-WithTimeout -TimeoutSec 60 -Label 'aksarc list' -Script { az aksarc list -g 'rg-azlocal-poc-001' -o json 2>&1 }).Output

$lines += ""
$lines += "== Existing logical networks (AKS needs one with a VIP/IP pool) =="
$lines += (Invoke-WithTimeout -TimeoutSec 60 -Label 'lnet' -Script { az stack-hci-vm network lnet list -g 'rg-azlocal-poc-001' -o json 2>&1 }).Output

$lines | Out-File $outFile -Encoding utf8
Write-Host "Saved -> $outFile"
Get-Content $outFile
