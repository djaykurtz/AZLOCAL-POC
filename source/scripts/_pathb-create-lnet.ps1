# Path-B stage 3 (fixed): create tenant logical network.
# The vm-switch-name contains parentheses which break az.cmd batch parsing, so call the
# CLI Python entrypoint directly (PowerShell passes argv cleanly, no cmd reparse).
$ErrorActionPreference = 'Stop'
$azCmd = (Get-Command az).Source
$py = Join-Path (Split-Path (Split-Path $azCmd)) 'python.exe'
if (-not (Test-Path $py)) { throw "CLI python.exe not found at $py" }
function azpy { & $py -m azure.cli @args }

$rg = 'rg-azlocal-poc-001'
$clName = 'azl-cluster-01-cl'
$clId = azpy customlocation show -g $rg -n $clName --query id -o tsv
$loc  = azpy customlocation show -g $rg -n $clName --query location -o tsv
$lnet = 'AZL-CLUSTER-01-TenantLNET'

$exists = azpy stack-hci-vm network lnet show -g $rg --name $lnet --query name -o tsv 2>$null
if ($exists) { Write-Host "$lnet already exists"; return }

Write-Host "Creating tenant logical network $lnet ..."
azpy stack-hci-vm network lnet create `
    --resource-group $rg `
    --custom-location $clId `
    --location $loc `
    --name $lnet `
    --vm-switch-name 'ConvergedSwitch(compute_management)' `
    --ip-allocation-method 'Static' `
    --address-prefixes '10.10.0.0/22' `
    --gateway '10.10.1.1' `
    --dns-servers '10.20.50.50' '10.20.10.50' `
    --ip-pool-start '10.10.1.240' `
    --ip-pool-end '10.10.1.243' `
    2>&1 | Tee-Object -FilePath ".\out\_lnet-create-tenant.txt"

azpy stack-hci-vm network lnet show -g $rg --name $lnet --query "{name:name,prov:properties.provisioningState}" -o table
