# Local pcapng decoder for the BPDU capture (out/bpdu.pcapng). Extracts each BPDU's Ethernet
# src/dst, VLAN tag, and the STP root/bridge IDs so we can see whose bridge ID is inside.
$b = [IO.File]::ReadAllBytes("$PSScriptRoot\..\out\bpdu.pcapng")
function Mac([byte[]]$a,[int]$o){ ($a[$o..($o+5)] | ForEach-Object { $_.ToString('x2') }) -join '-' }
$i = 0; $frame = 0
while ($i -lt $b.Length - 12) {
    $btype = [BitConverter]::ToUInt32($b, $i)
    $blen  = [BitConverter]::ToUInt32($b, $i + 4)
    if ($blen -lt 12 -or $i + $blen -gt $b.Length) { break }
    if ($btype -eq 6) {  # Enhanced Packet Block
        $caplen = [BitConverter]::ToUInt32($b, $i + 20)   # correct offset
        $p = $b[($i + 28)..($i + 28 + $caplen - 1)]
        $dst = Mac $p 0; $src = Mac $p 6
        $et = '{0:x2}{1:x2}' -f $p[12], $p[13]
        if ($et -eq '8100') {
            $vlan = ((([int]$p[14]) * 256 + [int]$p[15]) -band 0xFFF)
            $llc = 18
        } else {
            $vlan = 'untagged'
            $llc = 14
        }
        # LLC = DSAP SSAP CTL (3 bytes); STP BPDU follows
        $dsap = '{0:x2}' -f $p[$llc]
        $stp = $llc + 3
        $bpduType = '{0:x2}' -f $p[$stp + 3]
        $rootPri = ([int]$p[$stp + 4]) * 256 + [int]$p[$stp + 5]
        $rootMac = Mac $p ($stp + 6)
        $brPri  = ([int]$p[$stp + 16]) * 256 + [int]$p[$stp + 17]
        $brMac  = Mac $p ($stp + 18)
        Write-Host ("frame $frame  dst=$dst  src=$src  vlan=$vlan  DSAP=$dsap  bpduType=$bpduType")
        Write-Host ("   ROOT   pri=$rootPri  mac=$rootMac")
        Write-Host ("   BRIDGE pri=$brPri  mac=$brMac")
        $frame++
        if ($frame -ge 6) { break }
    }
    $i += $blen
}
if ($frame -eq 0) { Write-Host "no BPDU frames parsed" }
Write-Host ""
Write-Host "Reference MACs: node01 Port3=00-00-5e-00-53-06 Port4=00-00-5e-00-53-01 ; SW1 chassis=00-00-5e-00-53-13 SW2 chassis=00-00-5e-00-53-14"
