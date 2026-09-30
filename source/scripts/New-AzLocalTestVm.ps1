<#
.SYNOPSIS
    Create a test VM on the Azure Local cluster from a gallery image, reusable for any image.
.DESCRIPTION
    Creates a NIC on a logical network, then the VM. Prints the power state. Uses the CLI python
    entrypoint (az.cmd cannot parse the vmSwitchName's parentheses). Password auth satisfies create;
    for a real login on a cloud image pass -SshKeyPath instead.
.EXAMPLE
    .\New-AzLocalTestVm.ps1 -VmName rocky-testvm-01 -ImageName rocky-10-2
.EXAMPLE
    .\New-AzLocalTestVm.ps1 -VmName app01 -ImageName rocky-10-2 -SshKeyPath ~\.ssh\id_rsa.pub
.NOTES
    Prereqs: az login + PIM active; the gallery image exists; a logical network with a free IP pool.
    Teardown: az stack-hci-vm delete --name <vm> -g <rg> --yes ; then delete the NIC.
#>
param(
    [Parameter(Mandatory)] [string]$VmName,
    [Parameter(Mandatory)] [string]$ImageName,
    [string]$LNet           = 'AZL-CLUSTER-01-TenantLNET',
    [string]$Size           = 'Default',
    [string]$AdminUser      = 'azureuser',
    [string]$SshKeyPath,
    [string]$ResourceGroup  = 'rg-azlocal-poc-001',
    [string]$CustomLocation = 'azl-cluster-01-cl',
    [string]$CsvName        = 'UserStorage_2',
    [string]$KeyVaultName   = 'kv-lab-secrets',
    [string]$PwSecretName   = 'poc-vm-admin',
    [string]$Role,
    [string]$Slot,
    [switch]$EnableAgent
)
$ErrorActionPreference = 'Stop'
$azCmd = (Get-Command az).Source
$py = Join-Path (Split-Path (Split-Path $azCmd)) 'python.exe'
function azpy { & $py -m azure.cli @args }

$clId = azpy customlocation show -g $ResourceGroup -n $CustomLocation --query id -o tsv
$loc  = azpy customlocation show -g $ResourceGroup -n $CustomLocation --query location -o tsv
# resolve a storage path (VM disks) by CSV name
$spId = azpy stack-hci-vm storagepath list -g $ResourceGroup --query "[?ends_with(properties.path,'$CsvName')].id | [0]" -o tsv
if (-not $spId) { throw "no storage path found for CSV $CsvName" }

$nic = "$VmName-nic"
if (-not (azpy stack-hci-vm network nic show -g $ResourceGroup --name $nic --query name -o tsv 2>$null)) {
    Write-Host "Creating NIC $nic on $LNet ..."
    azpy stack-hci-vm network nic create --name $nic --resource-group $ResourceGroup `
        --custom-location $clId --location $loc --subnet-id $LNet | Out-Null
} else { Write-Host "NIC $nic exists" }

# Auth. The stack-hci-vm create ALWAYS wants --admin-password (it crashes with no TTY otherwise), so we
# always generate a random break-glass password, stash it in Key Vault, and pass it. With an SSH key we
# use authentication-type 'all' (key is the real login; password is break-glass). The password is handled
# entirely inside this script so the terminal invocation carries no secret.
$pw = (-join ((48..57)+(65..90)+(97..122) | Get-Random -Count 24 | ForEach-Object {[char]$_})) + 'Aa1!'
azpy keyvault secret set --vault-name $KeyVaultName --name $PwSecretName --value $pw -o none 2>&1 | Out-Null
Write-Host "break-glass password stored in KV $KeyVaultName/$PwSecretName"
if ($SshKeyPath) {
    $keyVal = (Get-Content $SshKeyPath -Raw).Trim()   # pass the key CONTENT, not a path
    $authArgs = @('--authentication-type','all','--ssh-key-values',$keyVal,'--admin-password',$pw)
} else {
    $authArgs = @('--authentication-type','password','--admin-password',$pw)
}

Write-Host "Creating VM $VmName (image=$ImageName, size=$Size, agent=$EnableAgent) ..."
$agent = if ($EnableAgent) { 'true' } else { 'false' }
# $null | closes stdin so az can never block on an interactive prompt (it errors fast instead).
$null | azpy stack-hci-vm create --name $VmName --resource-group $ResourceGroup --custom-location $clId `
    --location $loc --image $ImageName --nics $nic --admin-username $AdminUser `
    @authArgs --enable-agent $agent --size $Size --storage-path-id $spId --only-show-errors `
    2>&1 | Tee-Object -FilePath ".\out\_vm-create-$VmName.txt"
Remove-Variable pw

# Stamp role/slot tags on the Arc machine record (Microsoft.HybridCompute/machines) - that is the
# resource the funder dashboard's VMs tile queries, so tags here surface as dashboard columns. The
# tag is a durable "slot" label independent of the transient VM name (survives VM churn).
if ($Role -or $Slot) {
    $tags = @()
    if ($Role) { $tags += "role=$Role" }
    if ($Slot) { $tags += "slot=$Slot" }
    $mId = azpy resource show -g $ResourceGroup -n $VmName --resource-type Microsoft.HybridCompute/machines --query id -o tsv 2>$null
    if ($mId) {
        azpy tag update --resource-id $mId --operation Merge --tags @tags -o none 2>&1 | Out-Null
        Write-Host "tagged Arc machine ${VmName}: $($tags -join ' ')"
    } else {
        Write-Warning "could not resolve Microsoft.HybridCompute/machines for $VmName yet; tag it later with: azpy tag update --resource-id <id> --operation Merge --tags $($tags -join ' ')"
    }
}

Write-Host "--- VM status ---"
azpy stack-hci-vm show --name $VmName -g $ResourceGroup `
    --query "{name:name,prov:properties.provisioningState,power:properties.status.powerState,host:properties.hostNodeName}" -o table
