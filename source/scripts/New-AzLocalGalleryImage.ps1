<#
.SYNOPSIS
    Stage a custom OS image as an Azure Local gallery image (path B), reusable for ANY source image.
.DESCRIPTION
    One command: download (optional) -> normalize to VHDX -> copy to a cluster CSV -> create the
    gallery image. Handles these source formats automatically:
      .qcow2 / .img   -> qemu-img convert to dynamic VHDX (qemu-img auto-fetched to out\tools if missing)
      .vhd            -> Convert-VHD to dynamic VHDX
      .vhdx           -> used as-is
      .xz suffix      -> decompressed first (e.g. *.vhdfixed.xz -> *.vhd), then handled per above
    Everything heavy runs on the DevBox; only the finished VHDX is copied to the host CSV (keep the
    Azure Local host OS clean - do not install tooling on the nodes).
.EXAMPLE
    # CirrOS (tiny UEFI test image)
    .\New-AzLocalGalleryImage.ps1 -Name cirros-064 `
        -SourceUrl 'https://download.cirros-cloud.net/0.6.2/cirros-0.6.2-x86_64-disk.img'
.EXAMPLE
    # Rocky Linux 10.2 GenericCloud
    .\New-AzLocalGalleryImage.ps1 -Name rocky-10-2 `
        -SourceUrl 'https://download.rockylinux.org/pub/rocky/10/images/x86_64/Rocky-10-GenericCloud-Base.latest.x86_64.qcow2'
.EXAMPLE
    # From an already-downloaded local file
    .\New-AzLocalGalleryImage.ps1 -Name myimg -SourcePath C:\path\to\disk.qcow2
.NOTES
    Prereqs: az login + PIM active; stack-hci-vm CLI extension; WinRM to the cluster (lab.example.com name +
    sim\labadmin domain-admin cred at .creds\sim-example-internal-admin.cred). CSV must have free space.
#>
param(
    [Parameter(Mandatory)] [string]$Name,
    [string]$SourceUrl,
    [string]$SourcePath,
    [ValidateSet('Linux','Windows')] [string]$OsType = 'Linux',
    [string]$ResourceGroup   = 'rg-azlocal-poc-001',
    [string]$CustomLocation  = 'azl-cluster-01-cl',
    [string]$ConnectNode     = 'azl-node-01.lab.example.com',
    [string]$CsvImageDir     = 'C:\ClusterStorage\UserStorage_1\images'
)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$root  = Split-Path $PSScriptRoot -Parent
$img   = Join-Path $root 'out\img'
$tools = Join-Path $root 'out\tools'
New-Item -ItemType Directory -Force -Path $img,$tools | Out-Null

# CLI python entrypoint (bypasses az.cmd batch parsing; needed because vmSwitchName has parentheses).
$azCmd = (Get-Command az).Source
$py = Join-Path (Split-Path (Split-Path $azCmd)) 'python.exe'
function azpy { & $py -m azure.cli @args }

function Get-QemuImg {
    $q = Join-Path $tools 'qemu-img.exe'
    if (Test-Path $q) { return $q }
    $zip = Join-Path $tools 'qemu-img.zip'
    Invoke-WebRequest 'https://cloudbase.it/downloads/qemu-img-win-x64-2_3_0.zip' -OutFile $zip -UseBasicParsing
    Expand-Archive $zip -DestinationPath $tools -Force
    if (-not (Test-Path $q)) { $f = Get-ChildItem $tools -Recurse -Filter qemu-img.exe | Select-Object -First 1; if ($f) { Copy-Item $f.FullName $q -Force } }
    if (-not (Test-Path $q)) { throw 'qemu-img not obtained' }
    return $q
}

# 1. Resolve the source file on the DevBox.
if ($SourceUrl) {
    $leaf = ($SourceUrl -split '/')[-1]
    $src  = Join-Path $img $leaf
    if (-not (Test-Path $src)) { Write-Host "Downloading $SourceUrl ..."; Invoke-WebRequest $SourceUrl -OutFile $src -UseBasicParsing }
} elseif ($SourcePath) {
    $src = $SourcePath
} else { throw 'Provide -SourceUrl or -SourcePath' }
Write-Host ("source: {0} ({1} MB)" -f $src, [math]::Round((Get-Item $src).Length/1MB,1))

# 2. Decompress .xz if needed (uses the CLI python's stdlib lzma; no extra tooling).
if ($src -match '\.xz$') {
    $dec = $src -replace '\.xz$',''
    if (-not (Test-Path $dec)) {
        Write-Host "Decompressing .xz ..."
        & $py -c "import lzma,shutil,sys; f=open(sys.argv[2],'wb'); shutil.copyfileobj(lzma.open(sys.argv[1]),f); f.close()" $src $dec
    }
    $src = $dec
    Write-Host ("decompressed: {0} ({1} MB)" -f $src, [math]::Round((Get-Item $src).Length/1MB,1))
}

# 2b. A .vhdfixed (Azure fixed-VHD variant, e.g. Rocky-*-Azure-Base) is just a fixed VHD; give it a
#     .vhd extension so Convert-VHD accepts it.
if ($src -match '\.vhdfixed$') {
    $renamed = $src -replace '\.vhdfixed$','.vhd'
    if (Test-Path $renamed) { Remove-Item $renamed -Force }
    Rename-Item -Path $src -NewName (Split-Path $renamed -Leaf)
    $src = $renamed
    Write-Host "renamed .vhdfixed -> .vhd"
}

# 3. Normalize to a dynamic VHDX on the DevBox.
$vhdx = Join-Path $img "$Name.vhdx"
if (Test-Path $vhdx) { Remove-Item $vhdx -Force }
switch -Regex ($src) {
    '\.vhdx$'        { Copy-Item $src $vhdx -Force }
    '\.vhd$'         { $q = Get-QemuImg; Write-Host "qemu-img convert (vpc) .vhd -> dynamic .vhdx ..."; & $q convert -f vpc -O vhdx $src $vhdx }
    '\.(qcow2|img)$' { $q = Get-QemuImg; Write-Host "qemu-img convert -> .vhdx ..."; & $q convert -f qcow2 -O vhdx $src $vhdx }
    default          { throw "Unhandled source extension for $src" }
}
if (-not (Test-Path $vhdx)) { throw 'VHDX not produced' }
Write-Host ("vhdx: {0} ({1} MB)" -f $vhdx, [math]::Round((Get-Item $vhdx).Length/1MB,1))

# 4. Copy the VHDX to the cluster CSV over WinRM.
$pw = ConvertTo-SecureString ((Get-Content "$root\.creds\sim-example-internal-admin.cred" -Raw).Trim())
$cred = [pscredential]::new('sim\labadmin', $pw)
$csvPath = "$CsvImageDir\$Name.vhdx"
$s = New-PSSession $ConnectNode -Credential $cred -Authentication Negotiate
try {
    Invoke-Command -Session $s -ScriptBlock { param($d) New-Item -ItemType Directory -Force -Path $d | Out-Null } -ArgumentList $CsvImageDir
    Write-Host "Copying VHDX to $csvPath (over WinRM; large images take a while) ..."
    Copy-Item -Path $vhdx -Destination $csvPath -ToSession $s -Force
    $sz = Invoke-Command -Session $s -ScriptBlock { param($p) [math]::Round((Get-Item $p).Length/1MB,1) } -ArgumentList $csvPath
    Write-Host "on-CSV size: $sz MB"
} finally { Remove-PSSession $s }

# 5. Create the gallery image.
$clId = azpy customlocation show -g $ResourceGroup -n $CustomLocation --query id -o tsv
$loc  = azpy customlocation show -g $ResourceGroup -n $CustomLocation --query location -o tsv
Write-Host "Creating gallery image $Name ..."
azpy stack-hci-vm image create --resource-group $ResourceGroup --custom-location $clId --location $loc `
    --name $Name --os-type $OsType --image-path $csvPath 2>&1 | Tee-Object -FilePath "$root\out\_image-create-$Name.txt"
azpy stack-hci-vm image show -g $ResourceGroup --name $Name --query "{name:name,prov:properties.provisioningState}" -o table
