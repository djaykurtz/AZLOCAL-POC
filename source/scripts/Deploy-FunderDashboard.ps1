<#
.SYNOPSIS
    Deploy (or update) the funder-facing Azure Monitor Workbook for the Azure Local PoC.
.DESCRIPTION
    Reads infra/dashboard/funder-workbook-content.json (human-editable ARG tiles), compresses it into the
    serializedData string, and deploys infra/dashboard/funder-workbook.arm.json (a Microsoft.Insights/workbooks
    resource) to the RG. Re-running updates the SAME workbook (stable GUID in the template).
.NOTES
    Needs write on Microsoft.Insights/workbooks (Contributor or Monitoring Contributor - a different RP than
    the HCI VM work, so activate Contributor via PIM first). After deploy, open it in the portal:
    Azure Monitor -> Workbooks -> "Azure Local PoC". Share read-only via RBAC.
#>
param(
    [string]$ResourceGroup = 'rg-azlocal-poc-001'
)
$ErrorActionPreference = 'Stop'
$root    = Split-Path $PSScriptRoot -Parent
$content = Join-Path $root 'infra\dashboard\funder-workbook-content.json'
$arm     = Join-Path $root 'infra\dashboard\funder-workbook.arm.json'
$azCmd = (Get-Command az).Source
$py = Join-Path (Split-Path (Split-Path $azCmd)) 'python.exe'

# 1. Read + compress the workbook content into the serializedData string.
$serialized = (Get-Content $content -Raw | ConvertFrom-Json | ConvertTo-Json -Depth 50 -Compress)
Write-Host ("serializedData length: {0} chars" -f $serialized.Length)

# 2. Write an ARM parameters file (avoids CLI quoting of the long string).
$paramObj = [ordered]@{
    '$schema'      = 'https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#'
    contentVersion = '1.0.0.0'
    parameters     = [ordered]@{
        serializedData = @{ value = $serialized }
    }
}
$paramFile = Join-Path $root 'out\_funder-workbook.params.json'
$paramObj | ConvertTo-Json -Depth 50 | Set-Content -Path $paramFile -Encoding utf8

# 3. Deploy.
Write-Host "Deploying workbook to $ResourceGroup ..."
& $py -m azure.cli deployment group create `
    --resource-group $ResourceGroup `
    --name 'funder-dashboard-workbook' `
    --template-file $arm `
    --parameters "@$paramFile" `
    --query "{state:properties.provisioningState, workbook:properties.outputs.workbookResourceId.value}" -o json 2>&1
