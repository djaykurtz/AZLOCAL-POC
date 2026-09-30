# Path-B stage 1 (DevBox side): get qemu-img, download CirrOS qcow2, convert to VHDX.
# Output: out\img\cirros.vhdx  (dynamic VHDX, ready to copy to a cluster CSV).
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$tools = Join-Path $root 'out\tools'
$img   = Join-Path $root 'out\img'
New-Item -ItemType Directory -Force -Path $tools,$img | Out-Null
$ProgressPreference = 'SilentlyContinue'

# 1. qemu-img (standalone, no install). Cloudbase publishes a small standalone build.
$qemu = Join-Path $tools 'qemu-img.exe'
if (-not (Test-Path $qemu)) {
    $zip = Join-Path $tools 'qemu-img.zip'
    $url = 'https://cloudbase.it/downloads/qemu-img-win-x64-2_3_0.zip'
    Write-Host "Downloading qemu-img from $url ..."
    Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing
    Expand-Archive -Path $zip -DestinationPath $tools -Force
    if (-not (Test-Path $qemu)) {
        # find it wherever it extracted
        $found = Get-ChildItem $tools -Recurse -Filter qemu-img.exe | Select-Object -First 1
        if ($found) { Copy-Item $found.FullName $qemu -Force }
    }
}
if (-not (Test-Path $qemu)) { throw "qemu-img.exe not obtained" }
Write-Host "qemu-img: $qemu"
& $qemu --version

# 2. CirrOS UEFI-capable cloud image (qcow2, ~20MB).
$src = Join-Path $img 'cirros.img'
if (-not (Test-Path $src)) {
    $curl = 'https://download.cirros-cloud.net/0.6.2/cirros-0.6.2-x86_64-disk.img'
    Write-Host "Downloading CirrOS from $curl ..."
    Invoke-WebRequest -Uri $curl -OutFile $src -UseBasicParsing
}
Write-Host ("cirros.img size: {0} MB" -f [math]::Round((Get-Item $src).Length/1MB,1))

# 3. Convert qcow2 -> dynamic VHDX.
$vhdx = Join-Path $img 'cirros.vhdx'
if (Test-Path $vhdx) { Remove-Item $vhdx -Force }
Write-Host "Converting to VHDX ..."
& $qemu convert -f qcow2 -O vhdx $src $vhdx
if (-not (Test-Path $vhdx)) { throw "VHDX not produced" }
Write-Host ("cirros.vhdx size: {0} MB" -f [math]::Round((Get-Item $vhdx).Length/1MB,1))
Write-Host "DONE. VHDX ready at: $vhdx"
