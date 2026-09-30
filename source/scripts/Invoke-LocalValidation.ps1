<#
.SYNOPSIS
  Runs local validation checks for the Azure Local POC repo.

.DESCRIPTION
  Hardware-free and Azure-safe validation for the artifacts we can test before
  the cluster exists. Checks PowerShell syntax, Bicep buildability, Terraform
  format/validate when .tf files exist, Dockerfile basics when Dockerfiles
  exist, and Kubernetes manifest client-side validation when manifests exist.

  The script skips optional tool families when no matching files are present.
  It does not run az deployment, terraform apply, docker push, or kubectl apply
  against a cluster.

.EXAMPLE
  .\scripts\Invoke-LocalValidation.ps1

.EXAMPLE
  .\scripts\Invoke-LocalValidation.ps1 -BuildDocker
#>

[CmdletBinding()]
param(
  [switch]$BuildDocker,
  [switch]$IncludeOutDirectory
)

$ErrorActionPreference = 'Stop'

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$outDir = Join-Path $repoRoot 'out'
if (-not (Test-Path -LiteralPath $outDir)) { New-Item -ItemType Directory -Path $outDir | Out-Null }
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$reportPath = Join-Path $outDir "_local-validation-$timestamp.txt"

$results = [System.Collections.Generic.List[object]]::new()

function Add-Result {
  param(
    [string]$Area,
    [string]$Name,
    [ValidateSet('PASS','FAIL','SKIP')]
    [string]$Status,
    [string]$Detail = ''
  )
  $results.Add([pscustomobject]@{
      Area = $Area
      Name = $Name
      Status = $Status
      Detail = $Detail
    })
}

function Invoke-LoggedCommand {
  param(
    [string]$Area,
    [string]$Name,
    [scriptblock]$Command
  )
  try {
    $global:LASTEXITCODE = 0
    $output = & $Command 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) {
      Add-Result -Area $Area -Name $Name -Status FAIL -Detail $output.Trim()
    } else {
      Add-Result -Area $Area -Name $Name -Status PASS -Detail $output.Trim()
    }
  } catch {
    Add-Result -Area $Area -Name $Name -Status FAIL -Detail $_.Exception.Message
  }
}

function Get-RepoFiles {
  param([string[]]$Include)
  $files = Get-ChildItem -Path $repoRoot -Recurse -File -Include $Include -Force |
    Where-Object {
      $_.FullName -notmatch '\\.git\\' -and
      $_.FullName -notmatch '\\.terraform\\' -and
      ($IncludeOutDirectory -or $_.FullName -notmatch '\\out\\')
    }
  @($files)
}

function Test-YamlManifestShape {
  param([System.IO.FileInfo]$Manifest)

  $content = Get-Content -LiteralPath $Manifest.FullName -Raw
  $documents = @($content -split '(?m)^---\s*$' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
  $errors = [System.Collections.Generic.List[string]]::new()

  foreach ($document in $documents) {
    if ($document -notmatch '(?m)^apiVersion\s*:') { $errors.Add('missing apiVersion') }
    if ($document -notmatch '(?m)^kind\s*:') { $errors.Add('missing kind') }
    if ($document -notmatch '(?m)^metadata\s*:') { $errors.Add('missing metadata') }
    if ($document -notmatch '(?ms)^metadata\s*:\s*(?:\r?\n[ \t]+[^\r\n]*)*?\r?\n[ \t]+name\s*:') { $errors.Add('missing metadata.name') }
  }

  @($errors | Select-Object -Unique)
}

function Test-TerraformPocSmokeShape {
  param([System.IO.FileInfo]$TerraformFile)

  $content = Get-Content -LiteralPath $TerraformFile.FullName -Raw
  $errors = [System.Collections.Generic.List[string]]::new()
  if ($content -notmatch 'variable\s+"node_count"') { $errors.Add('missing node_count variable') }
  if ($content -notmatch 'contains\(\[4,\s*6\],\s*var\.node_count\)') { $errors.Add('node_count validation does not allow exactly 4 and 6') }
  if ($content -notmatch 'default\s*=\s*4') { $errors.Add('node_count default is not 4') }
  if ($content -notmatch 'range\(var\.node_count\)') { $errors.Add('node_names are not generated from node_count') }
  if ($content -match '(?m)^\s*resource\s+"') { $errors.Add('starter module must remain no-deploy and define no resources') }
  @($errors | Select-Object -Unique)
}

Push-Location $repoRoot
try {
  Write-Host "Azure Local POC local validation" -ForegroundColor Cyan
  Write-Host "Repo:   $repoRoot"
  Write-Host "Report: $reportPath"

  # PowerShell parser validation.
  $psScripts = Get-RepoFiles -Include @('*.ps1')
  if ($psScripts.Count -eq 0) {
    Add-Result -Area PowerShell -Name 'scripts' -Status SKIP -Detail 'No .ps1 files found.'
  } else {
    foreach ($script in $psScripts) {
      try {
        $tokens = $null
        $errors = $null
        [System.Management.Automation.Language.Parser]::ParseFile($script.FullName, [ref]$tokens, [ref]$errors) | Out-Null
        if ($errors.Count -gt 0) {
          Add-Result -Area PowerShell -Name $script.FullName.Substring($repoRoot.Path.Length + 1) -Status FAIL -Detail (($errors | Out-String).Trim())
        } else {
          Add-Result -Area PowerShell -Name $script.FullName.Substring($repoRoot.Path.Length + 1) -Status PASS
        }
      } catch {
        Add-Result -Area PowerShell -Name $script.FullName.Substring($repoRoot.Path.Length + 1) -Status FAIL -Detail $_.Exception.Message
      }
    }
  }

  # Bicep build validation. Use --outfile under out\ to avoid module-side artifacts.
  $bicepFiles = Get-RepoFiles -Include @('*.bicep')
  if ($bicepFiles.Count -eq 0) {
    Add-Result -Area Bicep -Name 'templates' -Status SKIP -Detail 'No .bicep files found.'
  } elseif (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    Add-Result -Area Bicep -Name 'az bicep build' -Status SKIP -Detail 'Azure CLI not found in PATH.'
  } else {
    foreach ($bicep in $bicepFiles) {
      $safeName = ($bicep.FullName.Substring($repoRoot.Path.Length + 1) -replace '[\\/:*?"<>| ]','_')
      $outfile = Join-Path $outDir "_bicep-$safeName-$timestamp.json"
      Invoke-LoggedCommand -Area Bicep -Name $bicep.FullName.Substring($repoRoot.Path.Length + 1) -Command {
        az bicep build --file $bicep.FullName --outfile $outfile
      }
    }
  }

  # Bicep parameter validation when supported by the installed CLI.
  $bicepParamFiles = Get-RepoFiles -Include @('*.bicepparam')
  if ($bicepParamFiles.Count -gt 0 -and (Get-Command az -ErrorAction SilentlyContinue)) {
    foreach ($paramFile in $bicepParamFiles) {
      $safeName = ($paramFile.FullName.Substring($repoRoot.Path.Length + 1) -replace '[\\/:*?"<>| ]','_')
      $outfile = Join-Path $outDir "_bicepparam-$safeName-$timestamp.json"
      Invoke-LoggedCommand -Area BicepParam -Name $paramFile.FullName.Substring($repoRoot.Path.Length + 1) -Command {
        az bicep build-params --file $paramFile.FullName --outfile $outfile
      }
    }
  }

  # Terraform format and validate. TF_DATA_DIR keeps provider/cache writes out of source dirs.
  $tfFiles = Get-RepoFiles -Include @('*.tf')
  if ($tfFiles.Count -eq 0) {
    Add-Result -Area Terraform -Name 'terraform files' -Status SKIP -Detail 'No .tf files found yet.'
  } else {
    foreach ($tfFile in $tfFiles) {
      $relative = $tfFile.FullName.Substring($repoRoot.Path.Length + 1)
      if ($relative -eq 'tests\terraform\poc-smoke\main.tf') {
        $shapeErrors = Test-TerraformPocSmokeShape -TerraformFile $tfFile
        if ($shapeErrors.Count -gt 0) {
          Add-Result -Area TerraformStatic -Name $relative -Status FAIL -Detail ($shapeErrors -join '; ')
        } else {
          Add-Result -Area TerraformStatic -Name $relative -Status PASS -Detail 'No-deploy 4-node default / 6-node option shape is present.'
        }
      }
    }

    if (-not (Get-Command terraform -ErrorAction SilentlyContinue)) {
      Add-Result -Area Terraform -Name 'terraform' -Status SKIP -Detail 'terraform not found in PATH.'
    } else {
    Invoke-LoggedCommand -Area Terraform -Name 'fmt -check -recursive' -Command {
      terraform fmt -check -recursive
    }

    $tfDirs = $tfFiles | ForEach-Object { $_.Directory.FullName } | Sort-Object -Unique
    foreach ($dir in $tfDirs) {
      $relativeDir = $dir.Substring($repoRoot.Path.Length + 1)
      $dataDir = Join-Path $env:TEMP "azloc-tfdata-$($relativeDir -replace '[\\/:*?"<>| ]','_')-$timestamp"
      Invoke-LoggedCommand -Area Terraform -Name "init/validate $relativeDir" -Command {
        $oldDataDir = $env:TF_DATA_DIR
        try {
          $env:TF_DATA_DIR = $dataDir
          $initOutput = terraform -chdir=$dir init -backend=false -input=false -no-color 2>&1 | Out-String
          if ($LASTEXITCODE -ne 0) { throw $initOutput.Trim() }
          $validateOutput = terraform -chdir=$dir validate -no-color 2>&1 | Out-String
          if ($LASTEXITCODE -ne 0) { throw $validateOutput.Trim() }
          ($initOutput + $validateOutput).Trim()
        } finally {
          $env:TF_DATA_DIR = $oldDataDir
          Remove-Item -LiteralPath $dataDir -Recurse -Force -ErrorAction SilentlyContinue
        }
      }
    }
    }
  }

  # Dockerfile static checks, optional build check.
  $dockerfiles = @(Get-ChildItem -Path $repoRoot -Recurse -File -Force |
      Where-Object {
        ($_.Name -eq 'Dockerfile' -or $_.Name -like '*.Dockerfile') -and
        $_.FullName -notmatch '\\.git\\' -and
        ($IncludeOutDirectory -or $_.FullName -notmatch '\\out\\')
      })
  if ($dockerfiles.Count -eq 0) {
    Add-Result -Area Docker -Name 'Dockerfiles' -Status SKIP -Detail 'No Dockerfiles found yet.'
  } else {
    foreach ($dockerfile in $dockerfiles) {
      $relative = $dockerfile.FullName.Substring($repoRoot.Path.Length + 1)
      $text = Get-Content -LiteralPath $dockerfile.FullName -Raw
      if ($text -match '(?im)^\s*FROM\s+\S+') {
        Add-Result -Area Docker -Name $relative -Status PASS -Detail 'Contains FROM instruction.'
      } else {
        Add-Result -Area Docker -Name $relative -Status FAIL -Detail 'No FROM instruction found.'
      }

      if ($BuildDocker) {
        if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
          Add-Result -Area Docker -Name "build $relative" -Status SKIP -Detail 'docker not found in PATH.'
        } else {
          $tag = "azloc-poc-local:$($timestamp.ToLowerInvariant())"
          Invoke-LoggedCommand -Area Docker -Name "build $relative" -Command {
            docker build --file $dockerfile.FullName --tag $tag $dockerfile.Directory.FullName
          }
        }
      }
    }
  }

  # Kubernetes manifests: only files that look like k8s resources.
  $yamlFiles = Get-RepoFiles -Include @('*.yaml','*.yml')
  $k8sManifests = @($yamlFiles | Where-Object {
      $content = Get-Content -LiteralPath $_.FullName -Raw
      $content -match '(?m)^apiVersion\s*:' -and $content -match '(?m)^kind\s*:'
    })
  if ($k8sManifests.Count -eq 0) {
    Add-Result -Area Kubernetes -Name 'manifests' -Status SKIP -Detail 'No Kubernetes manifests found yet.'
  } else {
    foreach ($manifest in $k8sManifests) {
      $relativeManifest = $manifest.FullName.Substring($repoRoot.Path.Length + 1)
      $shapeErrors = Test-YamlManifestShape -Manifest $manifest
      if ($shapeErrors.Count -gt 0) {
        Add-Result -Area KubernetesStatic -Name $relativeManifest -Status FAIL -Detail ($shapeErrors -join '; ')
      } else {
        Add-Result -Area KubernetesStatic -Name $relativeManifest -Status PASS
      }
    }

    if (-not (Get-Command kubectl -ErrorAction SilentlyContinue)) {
      Add-Result -Area Kubernetes -Name 'kubectl dry-run' -Status SKIP -Detail 'kubectl not found in PATH.'
    } else {
    foreach ($manifest in $k8sManifests) {
      Invoke-LoggedCommand -Area Kubernetes -Name $manifest.FullName.Substring($repoRoot.Path.Length + 1) -Command {
        kubectl apply --dry-run=client --validate=false -f $manifest.FullName
      }
    }
    }
  }

  $summary = $results | Group-Object Status | ForEach-Object { "{0}: {1}" -f $_.Name, $_.Count }
  Write-Host "`nSummary: $($summary -join ', ')" -ForegroundColor Cyan
  $results | Sort-Object Area, Name | Format-Table -AutoSize | Out-String -Width 240 | Write-Host
  $results | Sort-Object Area, Name | Format-Table -AutoSize | Out-String -Width 240 | Set-Content -Path $reportPath -Encoding ascii

  if (($results | Where-Object Status -eq 'FAIL').Count -gt 0) {
    throw "Local validation failed. See report: $reportPath"
  }
} finally {
  Pop-Location
}