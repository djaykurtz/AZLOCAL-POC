<#
.SYNOPSIS
  Self-activate (PIM elevate) an eligible Azure RBAC role with a reason.

.DESCRIPTION
  Guestbook-style PIM activator: pick a role, type why, you're in.
  Calls the ARM REST API directly (az rest) so no extra modules required.

  Defaults to the Azure Local POC subscription. By default lists every
  eligible role visible from your account at or below that subscription
  (sub-level, RG-level), filters out tenant/MG-scope noise, and lets
  you pick interactively. Pass -RoleName to narrow the menu, or -All
  to include MG and tenant scope.

  After PUT, polls the request status until the role goes Active or
  the request hits an error/timeout. Idempotent: if the role is
  already Active, prints the current end time and exits 0.

.PARAMETER Reason
  Required. Justification recorded in PIM (the "guestbook" entry).
  Free text, 5+ chars. Example: "node 02-06 post-image bringup".

.PARAMETER RoleName
  Optional. Case-insensitive substring match on the role display name.
  If omitted, you pick from the full eligible-at-this-scope menu.

.PARAMETER Hours
  Activation duration in hours. Default 8. PIM policy upper bound
  varies per role; if you ask for more than the policy allows the
  request will fail with a clear error.

.PARAMETER Subscription
  Subscription ID to constrain the search. Default = POC sub
  (00000000-0000-0000-0000-000000000001).

.PARAMETER All
  Include eligible roles at management-group and tenant scope.
  Default behavior hides them to keep the menu short.

.PARAMETER TicketNumber
  Optional ticket number recorded with the activation. PIM policy
  may require it on some roles (rare in our tenant); pass if needed.

.PARAMETER TicketSystem
  Free-text system label for -TicketNumber. Default 'Helpdesk'.

.EXAMPLE
  # Interactive: list eligible roles at the POC sub, pick one, supply reason
  .\Invoke-PimActivate.ps1 -Reason 'node 02-06 post-image bringup'

.EXAMPLE
  # Auto-pick the single match by name
  .\Invoke-PimActivate.ps1 -RoleName 'Stack HCI' -Reason 'wizard prereq verify'

.EXAMPLE
  # Wider scope, shorter window, with ticket
  .\Invoke-PimActivate.ps1 -All -RoleName 'User Access Admin' `
    -Hours 2 -Reason 'one-off role assignment' -TicketNumber 12345

.NOTES
  REST docs:
    PUT /{scope}/providers/Microsoft.Authorization/roleAssignmentScheduleRequests/{guid}
    api-version=2020-10-01, requestType=SelfActivate
  No external modules. Uses the existing az CLI session.

.EXAMPLE
  # Just answer 'am I elevated right now?' - no menu, no activation
  .\Invoke-PimActivate.ps1 -Status

.EXAMPLE
  # Disambiguate UAA at RG vs sub - exact role name + scope type pins it
  .\Invoke-PimActivate.ps1 -RoleName 'User Access Administrator' `
    -ScopeType resourcegroup -Reason 'POC day work'

.EXAMPLE
  # Or by scope display name (substring match)
  .\Invoke-PimActivate.ps1 -RoleName 'User Access Administrator' `
    -ScopeName 'rg-azlocal-poc' -Reason 'POC day work'
#>

[CmdletBinding(DefaultParameterSetName='Activate')]
param(
  [Parameter(Mandatory=$true, ParameterSetName='Activate')]
  [ValidateLength(5,400)]
  [string]$Reason,

  [Parameter(ParameterSetName='Status', Mandatory=$true)]
  [switch]$Status,

  [string]$RoleName,
  [ValidateSet('subscription','resourcegroup','managementgroup','tenant')]
  [string]$ScopeType,
  [string]$ScopeName,
  [int]$Hours = 8,
  [string]$Subscription = '00000000-0000-0000-0000-000000000001',
  [switch]$All,
  [string]$TicketNumber,
  [string]$TicketSystem = 'Helpdesk'
)

$ErrorActionPreference = 'Stop'

function Write-Step($n, $msg) { Write-Host "`n[$n] $msg" -ForegroundColor Cyan }
function Write-OK($msg)       { Write-Host "    OK  $msg" -ForegroundColor Green }
function Write-Skip($msg)     { Write-Host "    --  $msg" -ForegroundColor DarkGray }
function Write-Bad($msg)      { Write-Host "    !!  $msg" -ForegroundColor Red }

# az.cmd splits the URL at '&' and loses '$filter=asTarget()', which silently returns
# every principal's eligibility instead of the caller's. Go straight to ARM for reads.
function Invoke-ArmGet([string]$Url) {
  $token = az account get-access-token --resource https://management.azure.com --query accessToken -o tsv
  if (-not $token) { throw "Could not acquire an ARM token. Run: az login" }
  Invoke-RestMethod -Uri $Url -Headers @{ Authorization = "Bearer $token" }
}

# -------- Identity ----------------------------------------------------------
Write-Step '1/4' 'Resolve signed-in user'
$me = az ad signed-in-user show --query id -o tsv 2>$null
if (-not $me) { throw "Not logged in. Run: az login" }
$upn = az ad signed-in-user show --query userPrincipalName -o tsv
Write-OK "$upn (oid $me)"

# -------- Enumerate eligibility --------------------------------------------
Write-Step '2/4' 'List eligible role assignments (PIM)'

# Backtick escape keeps pwsh from expanding $filter before the string is built.
$eligUrl = "https://management.azure.com/subscriptions/$Subscription/providers/Microsoft.Authorization/roleEligibilityScheduleInstances?api-version=2020-10-01&`$filter=asTarget()"
$eligList = Invoke-ArmGet $eligUrl

$elig = $eligList.value | ForEach-Object {
  # When az.cmd mishandles the OData filter, ARM can return direct eligibilities
  # for other principals at the same scope. Never pick another principal's
  # direct schedule for self-activation.
  if ($_.properties.memberType -eq 'Direct' -and $_.properties.principalId -ne $me) {
    return
  }

  [pscustomobject]@{
    RoleName        = $_.properties.expandedProperties.roleDefinition.displayName
    Scope           = $_.properties.scope
    ScopeName       = $_.properties.expandedProperties.scope.displayName
    ScopeType       = $_.properties.expandedProperties.scope.type   # subscription|resourcegroup|managementgroup
    RoleDefinitionId = $_.properties.roleDefinitionId
    EligibilityId   = if ($_.properties.roleEligibilityScheduleId) { $_.properties.roleEligibilityScheduleId } else { $_.id }
    EndsUtc         = $_.properties.endDateTime
  }
}

if (-not $All) {
  $elig = $elig | Where-Object { $_.ScopeType -in @('subscription','resourcegroup') }
}

if ($RoleName) {
  # Prefer exact (case-insensitive) match. Fall back to substring only if no
  # exact hit, so '-RoleName Contributor' picks "Contributor", not also
  # "Resource Policy Contributor".
  $exact = $elig | Where-Object { $_.RoleName -ieq $RoleName }
  if ($exact) {
    $elig = $exact
  } else {
    $elig = $elig | Where-Object { $_.RoleName -like "*$RoleName*" }
  }
}
if ($ScopeType) {
  $elig = $elig | Where-Object { $_.ScopeType -ieq $ScopeType }
}
if ($ScopeName) {
  $elig = $elig | Where-Object { $_.ScopeName -like "*$ScopeName*" }
}

# Dedupe: PIM returns one instance per group-grant; same role+scope -> single row
$elig = $elig |
  Group-Object RoleName, Scope |
  ForEach-Object { $_.Group | Select-Object -First 1 } |
  Sort-Object ScopeType, ScopeName, RoleName

if (-not $elig -or $elig.Count -eq 0) {
  throw "No eligible roles matched (scope=$Subscription, all=$All, role='$RoleName')."
}

# -------- Annotate already-active state on each eligibility ---------------
# One round-trip up-front lets the menu show [ACTIVE until ...] per row.
$activeAllUrl = "https://management.azure.com/subscriptions/$Subscription/providers/Microsoft.Authorization/roleAssignmentScheduleInstances?api-version=2020-10-01&`$filter=asTarget()"
$activeAll = Invoke-ArmGet $activeAllUrl
$activeIndex = @{}
foreach ($a in $activeAll.value) {
  if ($a.properties.assignmentType -eq 'Activated') {
    $key = "$($a.properties.roleDefinitionId)|$($a.properties.scope)"
    $activeIndex[$key] = $a.properties.endDateTime
  }
}
foreach ($e in $elig) {
  $key = "$($e.RoleDefinitionId)|$($e.Scope)"
  if ($activeIndex.ContainsKey($key)) {
    $e | Add-Member -NotePropertyName ActiveUntil -NotePropertyValue $activeIndex[$key] -Force
  } else {
    $e | Add-Member -NotePropertyName ActiveUntil -NotePropertyValue $null -Force
  }
}

# -------- Status mode: print and exit -------------------------------------
if ($Status) {
  Write-Host ""
  Write-Host "Eligible roles (scope=$Subscription, all=$All):" -ForegroundColor Cyan
  $rows = $elig | ForEach-Object {
    [pscustomobject]@{
      Active     = if ($_.ActiveUntil) { 'YES' } else { '' }
      Until      = if ($_.ActiveUntil) { ([datetime]$_.ActiveUntil).ToLocalTime().ToString('MM-dd HH:mm') } else { '' }
      Role       = $_.RoleName
      ScopeType  = $_.ScopeType
      Scope      = $_.ScopeName
    }
  }
  $rows | Format-Table -AutoSize
  $activeCount = ($elig | Where-Object ActiveUntil).Count
  Write-Host ("Active: {0} / Eligible: {1}" -f $activeCount, $elig.Count) -ForegroundColor Green
  $global:LASTEXITCODE = 0
  return
}

# -------- Select target ----------------------------------------------------
$selected = $null
if ($elig.Count -eq 1) {
  $selected = $elig[0]
  Write-OK "Single match: $($selected.RoleName) @ $($selected.ScopeName)"
} else {
  Write-Host "    Pick a role to activate (0 or blank to cancel):" -ForegroundColor White
  for ($i = 0; $i -lt $elig.Count; $i++) {
    $tag = if ($elig[$i].ActiveUntil) { '[ACTIVE]' } else { '        ' }
    "{0,3}. {1} {2,-44} {3,-14} {4}" -f ($i + 1), $tag, $elig[$i].RoleName, $elig[$i].ScopeType, $elig[$i].ScopeName | Write-Host
  }
  $idx = Read-Host "Enter number"
  if ([string]::IsNullOrWhiteSpace($idx) -or $idx -eq '0') {
    Write-Skip 'Cancelled.'
    $global:LASTEXITCODE = 0
    return
  }
  if (-not ($idx -as [int]) -or [int]$idx -lt 1 -or [int]$idx -gt $elig.Count) {
    throw "Invalid selection."
  }
  $selected = $elig[[int]$idx - 1]
}

# -------- Already-active check ---------------------------------------------
if ($selected.ActiveUntil) {
  Write-OK "$($selected.RoleName) @ $($selected.ScopeName) is ALREADY ACTIVE until $($selected.ActiveUntil). Nothing to do."
  $global:LASTEXITCODE = 0
  return
}

# -------- Submit activation ------------------------------------------------
Write-Step '3/4' "Activate $($selected.RoleName) for $Hours h"
Write-Host "    Scope:  $($selected.ScopeName) ($($selected.ScopeType))"
Write-Host "    Reason: $Reason"
if ($TicketNumber) { Write-Host "    Ticket: $TicketSystem #$TicketNumber" }

$body = @{
  properties = @{
    principalId                     = $me
    roleDefinitionId                = $selected.RoleDefinitionId
    requestType                     = 'SelfActivate'
    linkedRoleEligibilityScheduleId = $selected.EligibilityId
    justification                   = $Reason
    scheduleInfo = @{
      startDateTime = $null
      expiration    = @{
        type     = 'AfterDuration'
        duration = "PT${Hours}H"
      }
    }
  }
}
if ($TicketNumber) {
  $body.properties.ticketInfo = @{
    ticketNumber = $TicketNumber
    ticketSystem = $TicketSystem
  }
}

$reqGuid = [guid]::NewGuid().Guid
$bodyFile = Join-Path $env:TEMP "pim-activate-$reqGuid.json"
($body | ConvertTo-Json -Depth 6) | Out-File -FilePath $bodyFile -Encoding ascii -Force

try {
  $resp = az rest `
    --method PUT `
    --url "https://management.azure.com$($selected.Scope)/providers/Microsoft.Authorization/roleAssignmentScheduleRequests/$($reqGuid)?api-version=2020-10-01" `
    --body "@$bodyFile" `
    -o json 2>&1 | Out-String
} finally {
  Remove-Item $bodyFile -Force -ErrorAction SilentlyContinue
}

# az rest writes errors to stderr but Out-String captures both; parse defensively
try {
  $respObj = $resp | ConvertFrom-Json -ErrorAction Stop
} catch {
  Write-Bad $resp.Trim()
  throw "PIM activation request rejected."
}

Write-OK "Submitted. Request status: $($respObj.properties.status)"

# -------- Poll for Active --------------------------------------------------
Write-Step '4/4' 'Wait for status = Provisioned/Active (max 90s)'
$deadline = (Get-Date).AddSeconds(90)
$lastStatus = $respObj.properties.status
do {
  Start-Sleep -Seconds 5
  $poll = az rest `
    --method GET `
    --url "https://management.azure.com$($selected.Scope)/providers/Microsoft.Authorization/roleAssignmentScheduleRequests/$($reqGuid)?api-version=2020-10-01" `
    -o json | ConvertFrom-Json
  $s = $poll.properties.status
  if ($s -ne $lastStatus) { Write-Host "    status: $s"; $lastStatus = $s }
  $done = $s -in @('Provisioned','Accepted','Granted','Failed','Canceled','Denied','PendingApproval')
} while (-not $done -and (Get-Date) -lt $deadline)

switch ($lastStatus) {
  'Provisioned'      { Write-OK "Role is ACTIVE. Window: $Hours h."; break }
  'Accepted'         { Write-OK "Accepted; PIM is provisioning. Recheck with: az role assignment list --assignee $me --scope $($selected.Scope)" }
  'Granted'          { Write-OK "Granted." }
  'PendingApproval'  { Write-Bad "Role requires approver. Request submitted; track in portal."; exit 2 }
  'Failed'           { Write-Bad "PIM rejected: $($poll.properties.statusDetails)"; exit 3 }
  default            { Write-Bad "Final status: $lastStatus. Inspect: $($poll | ConvertTo-Json -Depth 6)"; exit 4 }
}
