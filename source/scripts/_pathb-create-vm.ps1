# Path-B stage 4: create the test VM and exercise lifecycle. Uses CLI python entrypoint.
$ErrorActionPreference = 'Stop'
$azCmd = (Get-Command az).Source
$py = Join-Path (Split-Path (Split-Path $azCmd)) 'python.exe'
function azpy { & $py -m azure.cli @args }

$rg   = 'rg-azlocal-poc-001'
$vm   = 'poc-testvm-01'
$img  = 'cirros-064'
$lnet = 'AZL-CLUSTER-01-TenantLNET'
$clId = azpy customlocation show -g $rg -n 'azl-cluster-01-cl' --query id -o tsv
$loc  = azpy customlocation show -g $rg -n 'azl-cluster-01-cl' --query location -o tsv
$spId = azpy stack-hci-vm storagepath show -g $rg --name 'UserStorage2-f0d58fbe079c49e1a3fb4dbabbbbe4bd' --query id -o tsv
if (-not $spId) { throw "storage path id not resolved" }

# throwaway complex password (kept in memory only; CirrOS uses its own creds, this just satisfies create)
$pw = ([char[]](48..57+65..90+97..122) | Get-Random -Count 20) -join '' + 'Aa1!'

$nic = "$vm-nic"
$nicExists = azpy stack-hci-vm network nic show -g $rg --name $nic --query name -o tsv 2>$null
if (-not $nicExists) {
    Write-Host "Creating NIC $nic on $lnet ..."
    azpy stack-hci-vm network nic create `
        --name $nic `
        --resource-group $rg `
        --custom-location $clId `
        --location $loc `
        --subnet-id $lnet `
        2>&1 | Tee-Object -FilePath ".\out\_nic-create-$vm.txt"
} else { Write-Host "NIC $nic already exists" }

Write-Host "Creating VM $vm (image=$img, nic=$nic, size=Default) ..."
azpy stack-hci-vm create `
    --name $vm `
    --resource-group $rg `
    --custom-location $clId `
    --location $loc `
    --image $img `
    --nics $nic `
    --authentication-type password `
    --admin-username 'cirros' `
    --admin-password $pw `
    --enable-agent false `
    --size Default `
    --storage-path-id $spId `
    2>&1 | Tee-Object -FilePath ".\out\_vm-create-$vm.txt"

Write-Host "--- VM status ---"
azpy stack-hci-vm show --name $vm -g $rg --query "{name:name,prov:properties.provisioningState,power:properties.instanceView.powerState.code}" -o table
