<#
.SYNOPSIS
  Print and run the read-only Azure CLI queries that evidence the Azure Local cluster.

.DESCRIPTION
  Built for screen capture. Each query is echoed before it runs, so the recording shows the
  command and its output together and anyone can reproduce it.

  Read-only. No writes, no secrets, and serial numbers are deliberately left out of the node
  projection so the capture is safe to share.

  Requires an az login and an active PIM session. Run scripts/Invoke-PocPimElevation.ps1 first.

.PARAMETER Section
  Run one section instead of all of them: Arc, Hardware, Licence, Cluster, Inventory, Kubernetes.

.PARAMETER Force
  Continue even if the CLI is pointed at a subscription other than the expected one. Off by
  default, because evidence gathered from the wrong subscription is worse than no evidence.

.EXAMPLE
  .\scripts\Show-ClusterEvidence.ps1

.EXAMPLE
  .\scripts\Show-ClusterEvidence.ps1 -Section Hardware
#>
[CmdletBinding()]
param(
    [string]$Subscription = 'contoso-lab-sub',
    [string]$ResourceGroup = 'rg-azlocal-poc-001',
    [string]$Cluster = 'AZL-CLUSTER-01',
    [ValidateSet('All', 'Arc', 'Hardware', 'Licence', 'Cluster', 'Inventory', 'Kubernetes')]
    [string]$Section = 'All',
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$TYPE = 'microsoft.azurestackhci/clusters'

function Show-Step {
    param([string]$Title, [string]$Why, [scriptblock]$Query, [string]$Display)

    Write-Host ""
    Write-Host ("=" * 78) -ForegroundColor DarkGray
    Write-Host "  $Title" -ForegroundColor Cyan
    if ($Why) { Write-Host "  $Why" -ForegroundColor DarkGray }
    Write-Host ("=" * 78) -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "PS> $Display" -ForegroundColor Yellow
    Write-Host ""
    & $Query
    Write-Host ""
}

$run = { param($s) $Section -eq 'All' -or $Section -eq $s }

# Always first, and always shown. Evidence that does not say which subscription it came from is
# not evidence, and a capture taken against the wrong one is worse than none.
Show-Step -Title 'Where this is being read from' `
    -Why 'Named before anything is claimed, so the capture carries its own context.' `
    -Display 'az account show --query "{Subscription:name, Id:id, State:state, User:user.name}" -o table' `
    -Query {
        az account show --query "{Subscription:name, Id:id, State:state, User:user.name}" -o table
    }

$current = az account show --query name -o tsv 2>$null
if (-not $current) { throw 'Not logged in. Run az login, then scripts/Invoke-PocPimElevation.ps1.' }
if ($current -ne $Subscription) {
    $msg = "CLI is on '$current', expected '$Subscription'."
    if (-not $Force) { throw "$msg Switch with 'az account set -s $Subscription', or pass -Force." }
    Write-Warning "$msg Continuing because -Force was given."
}

if (& $run 'Arc') {
    # Resource Graph rather than az connectedmachine, because the Arc list API returns null for
    # properties and this needs one table rather than a loop of eight separate shows.
    #
    # Held as lines so the capture can print exactly what it runs. A hand written caption would
    # drift from the query, and a query nobody can copy is not evidence.
    $kqlLines = @(
        "Resources | where type =~ 'microsoft.azurestackhci/clusters'"
        "| mv-expand n = properties.reportedProperties.nodes"
        "| project key = tolower(tostring(n.name)), Model = tostring(n.model),"
        "          GiB = toint(n.memoryInGiB), Class = tostring(n.nodeType)"
        "| join kind=rightouter (Resources"
        "    | where type =~ 'microsoft.hybridcompute/machines'"
        "    | where resourceGroup =~ '$ResourceGroup'"
        "    | project key = tolower(name), Machine = name, Status = tostring(properties.status)"
        "  ) on key"
        "| extend Cluster = iff(isnotempty(Model), 'MEMBER', '-')"
        "| project Machine, Status, Cluster, Model, GiB, Class"
        "| order by Cluster asc, Machine asc"
    )
    $kql = $kqlLines -join ' '

    # Rebuild the paste-safe PowerShell the reader would type, from the same lines.
    $display = '$kql = "' + $kqlLines[0] + '" +' + "`n"
    for ($i = 1; $i -lt $kqlLines.Count; $i++) {
        $display += '        " ' + $kqlLines[$i].TrimEnd() + '"'
        $display += $(if ($i -lt $kqlLines.Count - 1) { " +`n" } else { "`n" })
    }
    $display += 'az graph query -q $kql --query "data[]" -o table'

    Show-Step -Title 'Every machine Arc knows about, and which are the cluster' `
        -Why 'Eight registered. Four are Azure Local, two never joined, two are guests it hosts.' `
        -Display $display `
        -Query {
            az graph query -q $kql --query "data[]" -o table
        }
}

if (& $run 'Hardware') {
    Show-Step -Title 'The hardware, as Azure describes it' `
        -Why 'Four workstations. Azure classes them ThirdParty and manages them anyway.' `
        -Display "az resource show -g $ResourceGroup -n $Cluster --resource-type $TYPE --query `"properties.reportedProperties.nodes[].{Node:name, Model:model, Cores:coreCount, GiB:memoryInGiB, Type:nodeType, OEM:oemActivation}`" -o table" `
        -Query {
            az resource show -g $ResourceGroup -n $Cluster --resource-type $TYPE `
                --query "properties.reportedProperties.nodes[].{Node:name, Model:model, Cores:coreCount, GiB:memoryInGiB, Type:nodeType, OEM:oemActivation}" -o table
        }
}

if (& $run 'Licence') {
    Show-Step -Title 'The licence' `
        -Why 'The cluster is running on a trial, and the clock is visible.' `
        -Display "az resource show -g $ResourceGroup -n $Cluster --resource-type $TYPE --query `"{Billing:properties.billingModel, TrialDaysLeft:properties.trialDaysRemaining, Status:properties.status, Connectivity:properties.connectivityStatus}`" -o table" `
        -Query {
            az resource show -g $ResourceGroup -n $Cluster --resource-type $TYPE `
                --query "{Billing:properties.billingModel, TrialDaysLeft:properties.trialDaysRemaining, Status:properties.status, Connectivity:properties.connectivityStatus}" -o table
        }
}

if (& $run 'Cluster') {
    Show-Step -Title 'The cluster itself' `
        -Why 'One OS build across every node, and the capabilities Azure will manage.' `
        -Display "az resource show -g $ResourceGroup -n $Cluster --resource-type $TYPE --query `"properties.reportedProperties.{Type:clusterType, Vendor:manufacturer, Class:hardwareClass, Version:clusterVersion, OS:nodes[0].osVersion, Nodes:length(nodes)}`" -o table" `
        -Query {
            az resource show -g $ResourceGroup -n $Cluster --resource-type $TYPE `
                --query "properties.reportedProperties.{Type:clusterType, Vendor:manufacturer, Class:hardwareClass, Version:clusterVersion, OS:nodes[0].osVersion, Nodes:length(nodes)}" -o table
        }

    Show-Step -Title 'What Azure is willing to do to it' `
        -Why 'Cloud managed updates, add a server, repair a server, add a network intent.' `
        -Display "az resource show -g $ResourceGroup -n $Cluster --resource-type $TYPE --query `"properties.reportedProperties.supportedCapabilities`" -o tsv" `
        -Query {
            az resource show -g $ResourceGroup -n $Cluster --resource-type $TYPE `
                --query "properties.reportedProperties.supportedCapabilities" -o tsv
        }
}

if (& $run 'Inventory') {
    Show-Step -Title 'Everything Azure can see' `
        -Why 'The resource group, counted by type rather than claimed.' `
        -Display "az resource list -g $ResourceGroup --query `"[].type`" -o tsv | Group-Object | Sort-Object Count -Descending | Format-Table Count, Name -AutoSize" `
        -Query {
            az resource list -g $ResourceGroup --query "[].type" -o tsv |
                Group-Object | Sort-Object Count -Descending | Format-Table Count, Name -AutoSize
        }

    Show-Step -Title 'The machines Azure knows about' `
        -Why 'Six physical, two of which never joined the cluster, plus two guests.' `
        -Display "az resource list -g $ResourceGroup --resource-type Microsoft.HybridCompute/machines --query `"[].name`" -o tsv | Sort-Object" `
        -Query {
            az resource list -g $ResourceGroup --resource-type Microsoft.HybridCompute/machines `
                --query "[].name" -o tsv | Sort-Object
        }
}

if (& $run 'Kubernetes') {
    Show-Step -Title 'Kubernetes, running on the cluster' `
        -Why 'AKS Arc, addressed as an ordinary Azure resource.' `
        -Display "az resource list -g $ResourceGroup --resource-type Microsoft.Kubernetes/connectedClusters --query `"[].{Name:name, Location:location}`" -o table" `
        -Query {
            az resource list -g $ResourceGroup --resource-type Microsoft.Kubernetes/connectedClusters `
                --query "[].{Name:name, Location:location}" -o table
        }
}

Write-Host ("=" * 78) -ForegroundColor DarkGray
Write-Host "  Read-only. Nothing above changed anything." -ForegroundColor DarkGray
Write-Host ("=" * 78) -ForegroundColor DarkGray
Write-Host ""
