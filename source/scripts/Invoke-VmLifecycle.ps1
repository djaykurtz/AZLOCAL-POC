<#
.SYNOPSIS
    Exercise an Azure Local VM lifecycle: stop (graceful, falling back to hard), start, restart.
.DESCRIPTION
    Reusable for any VM. Tries a graceful `stop` first; if the guest has no integration/agent to receive
    the shutdown (fails with 0x800710DF), retries with --skip-shutdown (immediate power-off). Logs to out\.
.EXAMPLE
    .\Invoke-VmLifecycle.ps1 -VmName rocky-testvm-01
#>
param(
    [Parameter(Mandatory)] [string]$VmName,
    [string]$ResourceGroup = 'rg-azlocal-poc-001'
)
$ErrorActionPreference = 'Stop'
$azCmd = (Get-Command az).Source
$py = Join-Path (Split-Path (Split-Path $azCmd)) 'python.exe'
function azpy { & $py -m azure.cli @args }
function Power { azpy stack-hci-vm show --name $VmName -g $ResourceGroup --query "properties.status.powerState" -o tsv 2>$null }

$log = ".\out\_vm-lifecycle-$VmName-$(Get-Date -Format yyyyMMdd-HHmmss).txt"
"== lifecycle for $VmName ==" | Tee-Object $log
"start state: $(Power)" | Tee-Object $log -Append

"---- stop (graceful) ----" | Tee-Object $log -Append
$out = azpy stack-hci-vm stop --name $VmName -g $ResourceGroup 2>&1
$out | Tee-Object $log -Append
if ("$out" -match '0x800710DF|failed to stop|Failed') {
    "  graceful stop failed (no guest agent) -> retrying with --skip-shutdown" | Tee-Object $log -Append
    azpy stack-hci-vm stop --name $VmName -g $ResourceGroup --skip-shutdown 2>&1 | Tee-Object $log -Append
}
"power after stop: $(Power)" | Tee-Object $log -Append

"---- start ----" | Tee-Object $log -Append
azpy stack-hci-vm start --name $VmName -g $ResourceGroup 2>&1 | Tee-Object $log -Append
"power after start: $(Power)" | Tee-Object $log -Append

"---- restart ----" | Tee-Object $log -Append
azpy stack-hci-vm restart --name $VmName -g $ResourceGroup 2>&1 | Tee-Object $log -Append
"power after restart: $(Power)" | Tee-Object $log -Append

"== final ==" | Tee-Object $log -Append
azpy stack-hci-vm show --name $VmName -g $ResourceGroup --query "{name:name,prov:properties.provisioningState,power:properties.status.powerState,host:properties.hostNodeName}" -o table | Tee-Object $log -Append
