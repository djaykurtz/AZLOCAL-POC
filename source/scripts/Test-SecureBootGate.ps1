[CmdletBinding()]
param(
    [string[]]$Nodes = @('azl-node-04','azl-node-06'),
    [string]$CredPath = '.\.creds\azloc-local-admin.cred'
)

$ErrorActionPreference = 'Stop'
$pw = ConvertTo-SecureString ((Get-Content $CredPath -Raw).Trim())

$stamp = (Get-Date).ToString('yyyyMMdd-HHmmss')
$outDir = Join-Path (Get-Location) 'out'
if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir | Out-Null }

foreach ($short in $Nodes) {
    $fqdn = "$short.lab.example.com"
    $cred = [pscredential]::new("$short\Administrator", $pw)
    Write-Host "==================== $short ====================" -ForegroundColor Cyan

    try {
        $o = New-PSSessionOption -OpenTimeout 15000 -OperationTimeout 900000
        $s = New-PSSession -ComputerName $fqdn -Credential $cred -Authentication Negotiate -SessionOption $o -ErrorAction Stop
    } catch {
        Write-Host "  UNREACHABLE: $($_.Exception.Message.Split([char]10)[0])" -ForegroundColor Yellow
        continue
    }

    try {
        $result = Invoke-Command -Session $s -ScriptBlock {
            # 1) Current Secure Boot / VBS state
            $sb = try { Confirm-SecureBootUEFI } catch { "ERR:$($_.Exception.Message.Split([char]10)[0])" }
            $vbs = try {
                (Get-CimInstance -Namespace root\Microsoft\Windows\DeviceGuard -ClassName Win32_DeviceGuard).VirtualizationBasedSecurityStatus
            } catch { 'ERR' }

            # 2) Full hardware validation — capture EVERY row, not just SecureBoot
            Import-Module AzStackHci.EnvironmentChecker -ErrorAction SilentlyContinue
            $rows = @()
            $sbRow = $null
            try {
                $res = @(Invoke-AzStackHciHardwareValidation -PassThru -ErrorAction SilentlyContinue 3>$null 4>$null 5>$null 6>$null)
                foreach ($r in $res) {
                    $status = "$($r.Status)"
                    $sev    = "$($r.Severity)"
                    $rows += [pscustomobject]@{
                        Name     = "$($r.Name)"
                        Status   = $status
                        Severity = $sev
                    }
                    if ("$($r.Name)" -match 'SecureBoot') {
                        $sbRow = [pscustomobject]@{
                            Name     = "$($r.Name)"
                            Status   = $status
                            Severity = $sev
                            Detail   = ("$($r.AdditionalData.Detail)" -replace '\s+',' ')
                        }
                    }
                }
            } catch {
                $rows += [pscustomobject]@{ Name='VALIDATOR-EXCEPTION'; Status="$($_.Exception.Message.Split([char]10)[0])"; Severity='' }
            }

            [pscustomobject]@{
                Node          = $env:COMPUTERNAME
                SecureBoot    = $sb
                VBS           = $vbs
                SecureBootRow = $sbRow
                AllRows       = $rows
            }
        }

        Write-Host "  SecureBoot(UEFI) = $($result.SecureBoot)   VBS = $($result.VBS) (2=running)"
        Write-Host ""
        Write-Host "  --- SecureBoot validator row ---" -ForegroundColor Green
        if ($result.SecureBootRow) {
            $result.SecureBootRow | Format-List | Out-String | Write-Host
        } else {
            Write-Host "  (no validator row matched 'SecureBoot' — check AllRows below)" -ForegroundColor Yellow
        }

        Write-Host "  --- ALL validator rows (every gate) ---" -ForegroundColor Green
        $result.AllRows | Sort-Object Severity, Status, Name |
            Format-Table Severity, Status, Name -AutoSize | Out-String | Write-Host

        $fails = @($result.AllRows | Where-Object { $_.Status -eq 'FAILURE' })
        $crit  = @($fails | Where-Object { $_.Severity -eq 'CRITICAL' })
        Write-Host ("  SUMMARY {0}: {1} rows, {2} FAILURE ({3} CRITICAL)" -f `
            $result.Node, $result.AllRows.Count, $fails.Count, $crit.Count) -ForegroundColor Cyan
        Write-Host ("  CRITICAL failures: " + (($crit.Name) -join ', '))

        $json = $result | ConvertTo-Json -Depth 6
        $path = Join-Path $outDir "_secureboot-gate-$short-$stamp.json"
        Set-Content -Path $path -Value $json -Encoding UTF8
        Write-Host "  saved -> $path"
    } catch {
        Write-Host "  ERROR during validation: $($_.Exception.Message.Split([char]10)[0])" -ForegroundColor Yellow
    } finally {
        Remove-PSSession $s
    }
    Write-Host ""
}
