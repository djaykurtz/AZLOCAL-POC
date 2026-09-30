<#
.SYNOPSIS
    Sprint S1 - create a test VM on the Azure Local cluster and exercise its lifecycle.
.DESCRIPTION
    Dry-run by default (prints the intended az commands). Pass -Execute to act.
    Requires an image (-ImageName) already registered on the custom location and a logical
    network (-LNetName). Uses Invoke-WithTimeout so hung az calls break cleanly.
.NOTES
    Image path is the current blocker: register Microsoft.EdgeMarketplace (directory admins) for a marketplace
    image, or create a custom image from a VHD (az stack-hci-vm image create). Then pass its name here.
#>
param(
    [string]$VmName       = 'poc-testvm-01',
    [string]$ImageName    = '<IMAGE-NAME-REQUIRED>',
    [string]$LNetName     = 'AZL-CLUSTER-01-InfraLNET',
    [string]$AdminUser    = 'azureuser',
    [int]   $CpuCount     = 2,
    [int]   $MemoryMB     = 4096,
    [string]$ResourceGroup= 'rg-azlocal-poc-001',
    [string]$Location     = 'southcentralus',
    [string]$CustomLocation = 'azl-cluster-01-cl',
    [switch]$Execute
)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\Invoke-WithTimeout.ps1"
$sub = '00000000-0000-0000-0000-000000000001'
$clId = "/subscriptions/$sub/resourceGroups/$ResourceGroup/providers/Microsoft.ExtendedLocation/customLocations/$CustomLocation"

function Step($label, [scriptblock]$cmd, [int]$to = 300) {
    Write-Host "---- $label ----"
    if (-not $Execute) { Write-Host "  DRY-RUN, would run:`n  $($cmd.ToString().Trim())"; return }
    $r = Invoke-WithTimeout -TimeoutSec $to -Label $label -Script $cmd
    if ($r.TimedOut) { Write-Warning "$label timed out" } else { $r.Output }
}

if ($ImageName -eq '<IMAGE-NAME-REQUIRED>' -and $Execute) {
    Write-Error "Set -ImageName to a registered image before -Execute. See docs/planning/deploy-test-vms.md."
    return
}

Write-Host "== Sprint S1: VM $VmName on $CustomLocation (image=$ImageName, lnet=$LNetName) =="

Step "create VM" {
    az stack-hci-vm create --name $using:VmName --resource-group $using:ResourceGroup --custom-location $using:clId `
        --location $using:Location --image $using:ImageName --admin-username $using:AdminUser `
        --nic-name "$($using:VmName)-nic" --network-arguments name=$using:LNetName `
        --hardware-profile "vmSize=Custom" --processors $using:CpuCount --memory-mb $using:MemoryMB -o json 2>&1
} 900

Step "power state" { az stack-hci-vm show --name $using:VmName --resource-group $using:ResourceGroup --query "properties.instanceView.powerState.code" -o tsv 2>&1 }
Step "stop"   { az stack-hci-vm stop    --name $using:VmName --resource-group $using:ResourceGroup 2>&1 } 300
Step "start"  { az stack-hci-vm start   --name $using:VmName --resource-group $using:ResourceGroup 2>&1 } 300
Step "restart"{ az stack-hci-vm restart --name $using:VmName --resource-group $using:ResourceGroup 2>&1 } 300
Step "final power state" { az stack-hci-vm show --name $using:VmName --resource-group $using:ResourceGroup --query "{name:name,power:properties.instanceView.powerState.code,prov:properties.provisioningState}" -o json 2>&1 }

Write-Host ""
Write-Host "To delete when done: az stack-hci-vm delete --name $VmName --resource-group $ResourceGroup --yes"
Write-Host "Success criteria (S1): VM reaches Running, reachable over mgmt path, stop/start/restart all succeed."
