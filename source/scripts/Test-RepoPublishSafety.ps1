<#
.SYNOPSIS
    Pre-commit safety gate. Scans everything git would publish for credentials and internal identifiers.

.DESCRIPTION
    This runs LOCALLY by design. The repository is owned by an Enterprise Managed User account, and
    GitHub-hosted runners are not available to EMU user-owned repositories, so a GitHub Actions gate
    would never execute here.

    Exit codes:
      0  no credential findings
      1  credential findings present, do not commit

    Internal identifiers (hostnames, subnet IPs, subscription GUIDs) are REPORTED but never fail the
    build. The repository is structurally private under Enterprise Managed Users, so those values are
    in scope. The report exists so the counts stay visible before anything is copied into a wiki or a
    document that travels further than the repository.

.PARAMETER Detailed
    List every internal-identifier hit instead of the per-pattern summary.

.EXAMPLE
    .\scripts\Test-RepoPublishSafety.ps1
#>
[CmdletBinding()]
param(
    [switch]$Detailed
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
Push-Location $repoRoot

try {
    $textExtensions = @(
        '.txt', '.md', '.json', '.ps1', '.psm1', '.psd1', '.yml', '.yaml', '.tf', '.tfvars',
        '.bicep', '.bicepparam', '.html', '.js', '.css', '.cmd', '.bat', '.sh', '.xml', '.config'
    )

    # Union of tracked files and anything git would add. .gitignore is honored by both commands.
    $candidatePaths = @()
    $candidatePaths += git ls-files
    $candidatePaths += (git status --short --untracked-files=all) |
        ForEach-Object { ($_ -replace '^.{3}', '').Trim('"') }

    # The gate stores the very patterns it hunts for, so it must never scan itself.
    $selfPath = $MyInvocation.MyCommand.Path

    $files = $candidatePaths |
        Sort-Object -Unique |
        Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Leaf) } |
        Where-Object { $textExtensions -contains [IO.Path]::GetExtension($_).ToLowerInvariant() } |
        Where-Object { (Resolve-Path -LiteralPath $_).Path -ne $selfPath }

    Write-Host "Repo publish safety gate" -ForegroundColor Cyan
    Write-Host "Candidate files: $($files.Count)`n"

    # Keyword assignments. The capture group isolates the value so the allowlist can judge it.
    $valuePatterns = [ordered]@{
        'password-assign' = '(?i)(?:password|passwd|pwd)\s*[:=]\s*(\S.*)$'
        'secret-assign'   = '(?i)(?:client_secret|apikey|api_key|access_key|secret)\s*[:=]\s*(\S.*)$'
    }

    # Literal high-signal markers. Any match is a finding; there is no benign form.
    $literalPatterns = [ordered]@{
        'private-key'  = 'BEGIN (RSA |OPENSSH |EC )?PRIVATE KEY'
        'ssh-private'  = '(?i)ssh-(rsa|ed25519) AAAA'
        'storage-key'  = '(?i)(AccountKey=|SharedAccessSignature|[?&]sig=)'
        'jwt'          = 'eyJ0eXAiOiJKV1'
        'bearer-token' = 'Bearer [A-Za-z0-9_\-\.]{20,}'
    }

    # Values that look like credentials but resolve at runtime, name a vault entry, or describe policy.
    $benignValue = @(
        '^\$',                                  # PowerShell variable
        '^var\.',                               # Terraform variable
        '^[A-Z][a-zA-Z]+-[A-Z][a-zA-Z]+',       # cmdlet call, e.g. ConvertTo-SecureString
        '^\(', '^<', '^\{\{', '^\[',            # expression, placeholder, template, type literal
        '^null$', '^""$', "^''$", '^\*+$',
        '^\d+\+?\s*(characters|chars)',         # password POLICY prose, not a value
        '^kv-lab-secrets/',               # Key Vault secret name, not a value
        '^azl-cluster-01-kv/',
        # Capstone teaching content. Narrow on purpose: exact strings, not a relaxed pattern.
        '^hunter2\b',                           # stock joke placeholder in the kubectl secret demo
        '^use a managed identity'               # prose: "do not have the secret: use a managed identity"
    ) -join '|'

    Write-Host "=== Credential findings ===" -ForegroundColor Cyan
    $findings = @()

    foreach ($name in $valuePatterns.Keys) {
        $hits = Select-String -LiteralPath $files -Pattern $valuePatterns[$name] -ErrorAction SilentlyContinue
        foreach ($hit in $hits) {
            $value = $hit.Matches[0].Groups[1].Value.Trim().Trim('"', "'", ',')
            if ($value -match $benignValue) { continue }

            $findings += [pscustomobject]@{
                Pattern = $name
                File    = Resolve-Path -LiteralPath $hit.Path -Relative
                Line    = $hit.LineNumber
            }
        }
    }

    foreach ($name in $literalPatterns.Keys) {
        $hits = Select-String -LiteralPath $files -Pattern $literalPatterns[$name] -ErrorAction SilentlyContinue
        foreach ($hit in $hits) {
            $findings += [pscustomobject]@{
                Pattern = $name
                File    = Resolve-Path -LiteralPath $hit.Path -Relative
                Line    = $hit.LineNumber
            }
        }
    }

    if ($findings.Count -eq 0) {
        Write-Host "  none" -ForegroundColor Green
    }
    else {
        $findings | ForEach-Object {
            Write-Host ("  {0,-16} {1}:{2}" -f $_.Pattern, $_.File, $_.Line) -ForegroundColor Red
        }
        Write-Host "`n  Values are deliberately not printed. Open each location to confirm." -ForegroundColor Yellow
    }

    Write-Host "`n=== Internal identifier exposure (report only) ===" -ForegroundColor Cyan
    $identifierPatterns = [ordered]@{
        'lab-domain'      = 'lab\.example\.com'
        'sim-domain'      = 'sim\.example\.internal'
        'corp-domain'     = 'corp\.example\.com'
        'mgmt-subnet'     = '10\.10\.[0-3]\.\d+'
        'corp-dns'        = '10\.20\.(50|10)\.50'
        'subscription-id' = '00000000-0000-0000-0000-000000000001'
        'tenant-id'       = '00000000-0000-0000-0000-000000000002'
        'mac-address'     = '\b[0-9A-Fa-f]{2}([-:])[0-9A-Fa-f]{2}(\1[0-9A-Fa-f]{2}){4}\b'
        'non-example-email' = '[A-Za-z0-9._%+-]+@(?!example\.com)[A-Za-z0-9-]+\.[A-Za-z0-9.-]+'
    }

    foreach ($name in $identifierPatterns.Keys) {
        $hits = @(Select-String -LiteralPath $files -Pattern $identifierPatterns[$name] -ErrorAction SilentlyContinue)
        $fileCount = @($hits | Select-Object -ExpandProperty Path -Unique).Count
        Write-Host ("  {0,-16} hits={1,-6} files={2}" -f $name, $hits.Count, $fileCount)

        if ($Detailed -and $hits.Count) {
            $hits | ForEach-Object {
                Write-Host ("      {0}:{1}" -f (Resolve-Path -LiteralPath $_.Path -Relative), $_.LineNumber) -ForegroundColor DarkGray
            }
        }
    }

    if ($findings.Count -gt 0) {
        Write-Host "`nRESULT: FAIL - $($findings.Count) credential candidate(s). Resolve or allowlist before committing." -ForegroundColor Red
        exit 1
    }

    Write-Host "`nRESULT: PASS - no credential candidates." -ForegroundColor Green
    exit 0
}
finally {
    Pop-Location
}
