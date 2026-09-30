# Path-B stage 5: exercise VM lifecycle (stop/start/restart) via CLI python entrypoint.
$ErrorActionPreference = 'Stop'
$azCmd = (Get-Command az).Source
$py = Join-Path (Split-Path (Split-Path $azCmd)) 'python.exe'
function azpy { & $py -m azure.cli @args }
$rg = 'rg-azlocal-poc-001'
$vm = 'poc-testvm-01'
function Power { (azpy stack-hci-vm show --name $vm -g $rg --query "properties.status.powerState" -o tsv 2>$null) }

$log = ".\out\_vm-lifecycle-$vm-$(Get-Date -Format yyyyMMdd-HHmmss).txt"
"== S1 lifecycle for $vm (CirrOS has no guest agent, so stop uses --skip-shutdown = hard power-off) ==" | Tee-Object $log
"start state: $(Power)" | Tee-Object $log -Append
"---- stop (--skip-shutdown) ----" | Tee-Object $log -Append
azpy stack-hci-vm stop --name $vm -g $rg --skip-shutdown 2>&1 | Tee-Object $log -Append
"power after stop: $(Power)" | Tee-Object $log -Append
"---- start ----" | Tee-Object $log -Append
azpy stack-hci-vm start --name $vm -g $rg 2>&1 | Tee-Object $log -Append
"power after start: $(Power)" | Tee-Object $log -Append
"---- restart ----" | Tee-Object $log -Append
azpy stack-hci-vm restart --name $vm -g $rg 2>&1 | Tee-Object $log -Append
"power after restart: $(Power)" | Tee-Object $log -Append
"== final ==" | Tee-Object $log -Append
azpy stack-hci-vm show --name $vm -g $rg --query "{name:name,prov:properties.provisioningState,power:properties.instanceView.powerState,host:properties.hostNodeName}" -o table | Tee-Object $log -Append
