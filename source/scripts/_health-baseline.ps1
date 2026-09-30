# Post-deploy known-good health baseline for AZL-CLUSTER-01.
# Read-only. Captures cluster, S2D storage, Network ATC, and Arc/ARB health to out/_health-baseline-*.txt.
# Cluster cmdlets go over domain-admin WinRM; Azure queries use the timeout wrapper.
. "$PSScriptRoot\Invoke-WithTimeout.ps1"
$rg = 'rg-azlocal-poc-001'
$node = 'azl-node-01.lab.example.com'
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$outFile = ".\out\_health-baseline-$stamp.txt"
$pw = ConvertTo-SecureString ((Get-Content ".\.creds\sim-example-internal-admin.cred" -Raw).Trim())
$cred = [pscredential]::new('sim\labadmin', $pw)
$lines = @("Azure Local health baseline  $stamp", "Cluster AZL-CLUSTER-01", "")

Write-Host "Gathering cluster + storage health via WinRM..."
try {
    $host1 = Invoke-Command $node -Credential $cred -Authentication Negotiate -ScriptBlock {
        $o = @()
        $o += "== Cluster nodes =="
        $o += (Get-ClusterNode | Select-Object Name,State,DynamicWeight | Format-Table -Auto | Out-String).Trim()
        $o += "== Cluster core resources =="
        $o += (Get-ClusterGroup | Select-Object Name,OwnerNode,State | Format-Table -Auto | Out-String).Trim()
        $o += "== Cluster network =="
        $o += (Get-ClusterNetwork | Select-Object Name,State,Role,Address | Format-Table -Auto | Out-String).Trim()
        $o += "== Storage pool =="
        $o += (Get-StoragePool -IsPrimordial $false -EA SilentlyContinue | Select-Object FriendlyName,HealthStatus,OperationalStatus,@{n='SizeTB';e={[math]::Round($_.Size/1TB,2)}},@{n='FreeTB';e={[math]::Round(($_.Size-$_.AllocatedSize)/1TB,2)}} | Format-Table -Auto | Out-String).Trim()
        $o += "== Virtual disks (volumes) =="
        $o += (Get-VirtualDisk -EA SilentlyContinue | Select-Object FriendlyName,HealthStatus,OperationalStatus,ResiliencySettingName,@{n='SizeGB';e={[math]::Round($_.Size/1GB,0)}} | Format-Table -Auto | Out-String).Trim()
        $o += "== Physical disks summary =="
        $o += (Get-PhysicalDisk -EA SilentlyContinue | Group-Object HealthStatus | Select-Object Name,Count | Format-Table -Auto | Out-String).Trim()
        $o += "== Storage jobs (resync/repair) =="
        $sj = Get-StorageJob -EA SilentlyContinue
        $o += if ($sj) { ($sj | Select-Object Name,JobState,PercentComplete | Format-Table -Auto | Out-String).Trim() } else { "  none (idle)" }
        $o += "== S2D enabled =="
        $o += "  " + ((Get-ClusterStorageSpacesDirect -EA SilentlyContinue).State)
        $o += "== Network ATC intents =="
        try { $o += (Get-NetIntent | Select-Object IntentName,Scope | Format-Table -Auto | Out-String).Trim() } catch { $o += "  Get-NetIntent: $($_.Exception.Message)" }
        try { $o += (Get-NetIntentStatus | Select-Object IntentName,Host,ConfigurationStatus,ProvisioningStatus | Format-Table -Auto | Out-String).Trim() } catch { $o += "  Get-NetIntentStatus: $($_.Exception.Message)" }
        $o
    } -ErrorAction Stop
    $lines += $host1
} catch { $lines += "WinRM gather FAILED: $($_.Exception.Message)" }

$lines += ""
Write-Host "Gathering Azure-side health..."
$lines += "== Azure: cluster resource =="
$lines += (Invoke-WithTimeout -TimeoutSec 60 -Label 'cluster' -Script { az rest --method GET --uri "https://management.azure.com/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-azlocal-poc-001/providers/Microsoft.AzureStackHCI/clusters/AZL-CLUSTER-01?api-version=2024-04-01" --query "{status:properties.status,prov:properties.provisioningState,nodes:properties.reportedProperties.nodes[].name}" -o json 2>&1 }).Output
$lines += "== Azure: Arc Resource Bridge =="
$lines += (Invoke-WithTimeout -TimeoutSec 60 -Label 'arb' -Script { az resource list -g 'rg-azlocal-poc-001' --resource-type 'Microsoft.ResourceConnector/appliances' --query "[].{name:name,prov:properties.provisioningState,status:properties.status}" -o json 2>&1 }).Output
$lines += "== Azure: custom location =="
$lines += (Invoke-WithTimeout -TimeoutSec 60 -Label 'cl' -Script { az customlocation list -g 'rg-azlocal-poc-001' --query "[].{name:name,prov:provisioningState}" -o json 2>&1 }).Output
$lines += "== Azure: node Arc status =="
foreach ($n in 'AZL-NODE-01','AZL-NODE-02','AZL-NODE-04','AZL-NODE-06') {
    $s = (Invoke-WithTimeout -TimeoutSec 40 -Label $n -Script { param($nn) az resource show -g 'rg-azlocal-poc-001' -n $nn --resource-type Microsoft.HybridCompute/machines --query "properties.status" -o tsv 2>&1 } ).Output
    # note: job scriptblock param passing differs; fall back to inline
}
$lines += (Invoke-WithTimeout -TimeoutSec 90 -Label 'arcnodes' -Script { foreach($nn in 'AZL-NODE-01','AZL-NODE-02','AZL-NODE-04','AZL-NODE-06'){ "$nn = " + (az resource show -g 'rg-azlocal-poc-001' -n $nn --resource-type Microsoft.HybridCompute/machines --query "properties.status" -o tsv 2>$null) } }).Output

$lines | Out-File $outFile -Encoding utf8
Write-Host "Saved -> $outFile"
Get-Content $outFile
