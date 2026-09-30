# Reusable timeout wrapper for calls that can hang (az CLI extensions, cluster/Arc VM RP, WinRM, etc.).
# Dot-source this file, then use Invoke-WithTimeout. Runs the scriptblock as a background job so a hang
# can be broken after a bounded wait instead of stalling the shell.
#
#   . .\scripts\Invoke-WithTimeout.ps1
#   $r = Invoke-WithTimeout -TimeoutSec 60 -Label 'lnet list' -Script { az stack-hci-vm network lnet list -g RG -o json }
#   if ($r.TimedOut) { "gave up" } else { $r.Output }
#
# Notes:
# - The job runs in a separate pwsh process. It inherits the on-disk az login (token cache in ~/.azure),
#   so az commands stay authenticated.
# - On timeout the job (and its child process tree, including the az python process) is stopped.
# - Returns an object: TimedOut (bool), Output (result or timeout message), DurationSec.

function Invoke-WithTimeout {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [scriptblock] $Script,
        [int]    $TimeoutSec = 120,
        [string] $Label = 'command'
    )
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $job = Start-Job -ScriptBlock $Script
    $done = Wait-Job -Job $job -Timeout $TimeoutSec
    $sw.Stop()
    if ($done) {
        $out = Receive-Job -Job $job -ErrorAction SilentlyContinue 2>&1
        Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
        [pscustomobject]@{ Label=$Label; TimedOut=$false; DurationSec=[math]::Round($sw.Elapsed.TotalSeconds,1); Output=$out }
    } else {
        Stop-Job -Job $job -ErrorAction SilentlyContinue
        Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
        Write-Warning "[$Label] did not finish within ${TimeoutSec}s - stopped."
        [pscustomobject]@{ Label=$Label; TimedOut=$true; DurationSec=[math]::Round($sw.Elapsed.TotalSeconds,1); Output="TIMEOUT after ${TimeoutSec}s" }
    }
}
