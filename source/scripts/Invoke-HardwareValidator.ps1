[CmdletBinding()]
param(
  [int[]]$NodeNumbers = @(1,2,3,4),
  [string]$Username   = 'Administrator',
  [string]$CredFile   = (Join-Path (Split-Path -Parent $PSScriptRoot) '.creds\azloc-local-admin.cred'),
  [string]$OutDir     = (Join-Path (Split-Path -Parent $PSScriptRoot) 'out')
)

$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Path $OutDir -Force | Out-Null

$ts     = Get-Date -Format 'yyyyMMdd-HHmmss'
$cipher = Get-Content -Path $CredFile -Raw
$pw     = ConvertTo-SecureString $cipher.Trim()

$summary = foreach ($n in $NodeNumbers) {
  $short = 'azl-node-{0:00}' -f $n
  $fqdn  = "$short.lab.example.com"
  Write-Host ""
  Write-Host "===== $short =====" -ForegroundColor Cyan
  $cred = [pscredential]::new("$short\$Username", $pw)

  try {
    $s = New-PSSession -ComputerName $fqdn -Credential $cred -Authentication Negotiate -ErrorAction Stop
  } catch {
    Write-Host "  session error: $($_.Exception.Message.Split([char]10)[0])" -ForegroundColor Red
    [pscustomobject]@{ Node=$short; Tests=0; Failed=0; Critical=0; Report="ERROR: $($_.Exception.Message)" }
    continue
  }

  try {
    $raw = Invoke-Command -Session $s -ScriptBlock {
      Import-Module AzStackHci.EnvironmentChecker -Force -ErrorAction Stop
      Invoke-AzStackHciHardwareValidation -PassThru
    }

    $jsonPath = Join-Path $OutDir "_hardware-$short-$ts.json"
    $raw | ConvertTo-Json -Depth 10 | Set-Content -Path $jsonPath -Encoding utf8

    $checks   = @($raw | Where-Object { $_ -and $_.PSObject.Properties.Name -contains 'Status' -and $_.Status })
    $failed   = @($checks | Where-Object { $_.Status -notin @('SUCCESS','Succeeded') })
    $critical = @($failed | Where-Object { $_.Severity -in @('CRITICAL','Critical') })

    Write-Host ("  tests:    {0}" -f $checks.Count)
    Write-Host ("  failed:   {0}" -f $failed.Count) -ForegroundColor $(if ($failed.Count) { 'Yellow' } else { 'Green' })
    Write-Host ("  critical: {0}" -f $critical.Count) -ForegroundColor $(if ($critical.Count) { 'Red' } else { 'Green' })

    if ($failed.Count) {
      Write-Host "  -- failures --" -ForegroundColor Yellow
      $failed | Select-Object @{n='Sev';e={$_.Severity}}, Name, @{n='Target';e={$_.TargetResourceName}}, @{n='Msg';e={ ($_.AdditionalData.message, $_.Description -ne $null | Select-Object -First 1) }} |
        Format-Table -AutoSize -Wrap | Out-String -Width 200 | Write-Host
    }

    [pscustomobject]@{
      Node     = $short
      Tests    = $checks.Count
      Failed   = $failed.Count
      Critical = $critical.Count
      Report   = $jsonPath
    }
  } catch {
    Write-Host "  invoke error: $($_.Exception.Message.Split([char]10)[0])" -ForegroundColor Red
    [pscustomobject]@{ Node=$short; Tests=0; Failed=0; Critical=0; Report="ERROR: $($_.Exception.Message)" }
  } finally {
    Remove-PSSession $s -ErrorAction SilentlyContinue
  }
}

Write-Host ""
Write-Host "================ SUMMARY ================" -ForegroundColor Cyan
$tableText = $summary | Format-Table -AutoSize | Out-String -Width 200
$tableText | Write-Host
$tableText | Set-Content (Join-Path $OutDir "_hardware-summary-$ts.txt")
$summary | Export-Csv -NoTypeInformation -Path (Join-Path $OutDir "_hardware-summary-$ts.csv")
Write-Host ""
Write-Host "JSON per node: $OutDir\_hardware-<node>-$ts.json"
Write-Host "Summary CSV:   $OutDir\_hardware-summary-$ts.csv"
