# Migrate the tenant network off the borrowed .240-.243 onto the OWNED reserved block .208-.219.
# Deletes the 4 test/docker VMs + NICs, deletes the old tenant lnet, recreates it on the reserved pool.
$ErrorActionPreference = 'Stop'
$az=(Get-Command az).Source; $py=Join-Path (Split-Path (Split-Path $az)) 'python.exe'
function azpy { & $py -m azure.cli @args }
$rg='rg-azlocal-poc-001'; $lnet='AZL-CLUSTER-01-TenantLNET'

foreach($vm in 'poc-testvm-01','rocky-testvm-01','ubuntu-docker-01','rocky-docker-01'){
    if (azpy stack-hci-vm show --name $vm -g $rg --query name -o tsv 2>$null) {
        Write-Host "deleting VM $vm ..."
        azpy stack-hci-vm delete --name $vm -g $rg --yes 2>&1 | Select-Object -Last 1
    }
    if (azpy stack-hci-vm network nic show --name "$vm-nic" -g $rg --query name -o tsv 2>$null) {
        azpy stack-hci-vm network nic delete --name "$vm-nic" -g $rg --yes 2>&1 | Select-Object -Last 1
    }
}

Write-Host "deleting old tenant lnet ($lnet, pool .240-.243) ..."
azpy stack-hci-vm network lnet delete --name $lnet -g $rg --yes 2>&1 | Select-Object -Last 1

$clId=azpy customlocation show -g $rg -n azl-cluster-01-cl --query id -o tsv
$loc =azpy customlocation show -g $rg -n azl-cluster-01-cl --query location -o tsv
Write-Host "creating tenant lnet on owned block, pool 10.10.1.208-.219 ..."
azpy stack-hci-vm network lnet create --resource-group $rg --custom-location $clId --location $loc `
    --name $lnet --vm-switch-name 'ConvergedSwitch(compute_management)' `
    --ip-allocation-method Static --address-prefixes '10.10.0.0/22' `
    --gateway '10.10.1.1' --dns-servers '10.20.50.50' '10.20.10.50' `
    --ip-pool-start '10.10.1.208' --ip-pool-end '10.10.1.219' 2>&1 | Select-Object -Last 2

azpy stack-hci-vm network lnet show -g $rg --name $lnet --query "{name:name,prov:properties.provisioningState,pstart:properties.subnets[0].properties.ipPools[0].start,pend:properties.subnets[0].properties.ipPools[0].end}" -o table
