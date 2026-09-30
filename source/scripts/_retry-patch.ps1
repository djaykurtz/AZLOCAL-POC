# Force az to refresh its token and retry the PATCH
Start-Sleep -Seconds 30
Write-Host "==== Token refresh check ===="
az account get-access-token --resource https://management.azure.com/ --query "expiresOn" -o tsv

$dsUri = "https://management.azure.com/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-azlocal-poc-001/providers/Microsoft.AzureStackHCI/clusters/AZL-CLUSTER-01/deploymentSettings/default?api-version=2024-04-01"
$current = az rest --method GET --uri $dsUri --output json | ConvertFrom-Json

$body = @{
    properties = @{
        arcNodeResourceIds      = $current.properties.arcNodeResourceIds
        deploymentMode          = 'Validate'
        deploymentConfiguration = $current.properties.deploymentConfiguration
    }
} | ConvertTo-Json -Depth 32
$body | Set-Content .\out\_ds-patch-retest.json -Encoding UTF8

Write-Host ""
Write-Host "==== Submitting PATCH ===="
$r = az rest --method PUT --uri $dsUri --headers "Content-Type=application/json" --body "@.\out\_ds-patch-retest.json" --output json 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "STILL FAILED:"
    Write-Host $r
} else {
    Write-Host "PATCH accepted!"
}
