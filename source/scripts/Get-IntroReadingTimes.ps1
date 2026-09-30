<#
.SYNOPSIS
  Report how long each intro narration line is on screen against how long it takes to read.

.DESCRIPTION
  The intro's couplet timing is fixed, so a long line and a short line get the same dwell. This
  parses the pair() and say() calls out of intro.js and flags the lines that are on screen for
  less time than a cold reader needs.

  Dwell model, taken from the constants in intro.js:
    line A of a couplet  = PAIR + TOP_OUT
    line B of a couplet  = BOT_OUT
    a solo say()         = CYCLE
  all multiplied by PACE.

  Reading model: WordsPerMinute over the visible characters, plus a fixed cost for noticing the
  line has appeared at all.

.PARAMETER WordsPerMinute
  Cold-read speed for short display text. Default 160, deliberately slower than prose reading.

.PARAMETER Try
  Score candidate lines instead of reading intro.js. Use it to test a rewrite before pasting it in.

.EXAMPLE
  .\scripts\Get-IntroReadingTimes.ps1

.EXAMPLE
  .\scripts\Get-IntroReadingTimes.ps1 -OnlyTight

.EXAMPLE
  .\scripts\Get-IntroReadingTimes.ps1 -Try 'The 100GbE NICs were on stock MS drivers.'
#>
[CmdletBinding()]
param(
    [string]$Path = (Join-Path (Split-Path -Parent $PSScriptRoot) 'capstone\prototype\intro.js'),
    [int]$WordsPerMinute = 160,
    [int]$NoticeMs = 350,
    [string[]]$Try,
    [switch]$OnlyTight
)

$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath $Path)) { throw "intro.js not found: $Path" }

$src = Get-Content -LiteralPath $Path -Raw

function Get-Num([string]$name) {
    $m = [regex]::Match($src, "(?m)^\s*(?:const|let)\s+$name\s*=\s*([0-9.]+)")
    if (-not $m.Success) { throw "could not read $name from intro.js" }
    [double]$m.Groups[1].Value
}

$PACE    = Get-Num 'PACE'
$TOP_OUT = Get-Num 'TOP_OUT'
$BOT_OUT = Get-Num 'BOT_OUT'
$PAIR    = Get-Num 'PAIR'
$CYCLE   = Get-Num 'CYCLE'
$OPEN    = Get-Num 'OPEN'

$dwellA    = ($PAIR + $TOP_OUT) * $PACE
$dwellB    = $BOT_OUT * $PACE
$dwellSolo = $CYCLE * $PACE
$charsPerMs = ($WordsPerMinute * 5.5) / 60000.0

# A trial can carry its own multiplier on top of PACE, so dwell is not uniform across the intro.
$actPace = @{}
$actDur = @{}
$actsBlk = [regex]::Match($src, 'const ACTS = \[(.*?)\];', 'Singleline').Groups[1].Value
foreach ($m in [regex]::Matches($actsBlk, "run:\s*act(\w+)\s*,\s*dur:\s*(\d+)\s*(?:,\s*pace:\s*([0-9.]+))?")) {
    $actPace[$m.Groups[1].Value] = if ($m.Groups[3].Success) { [double]$m.Groups[3].Value } else { 1.0 }
    $actDur[$m.Groups[1].Value] = [int]$m.Groups[2].Value
}

if ($Try) {
    Write-Host ""
    Write-Host "Candidate lines" -ForegroundColor Cyan
    Write-Host ("  dwell if first line {0} ms, if second line {1} ms" -f [int]$dwellA, [int]$dwellB)
    Write-Host ""
    foreach ($t in $Try) {
        $need = [math]::Round(($t.Length / $charsPerMs) + $NoticeMs)
        $mA = [int]($dwellA - $need)
        $mB = [int]($dwellB - $need)
        $colour = if ($mB -ge 0) { 'Green' } elseif ($mA -ge 0) { 'Yellow' } else { 'Red' }
        Write-Host ("  {0,3}ch  need {1,5}  as first {2,6}  as second {3,6}   {4}" -f `
            $t.Length, [int]$need, $mA, $mB, $t) -ForegroundColor $colour
    }
    Write-Host ""
    return
}

# Which trial a line belongs to, by source line number.
$acts = [regex]::Matches($src, "(?m)^\s*function\s+(act\w+)\s*\(") | ForEach-Object {
    [pscustomobject]@{
        Name = $_.Groups[1].Value
        Pos  = $_.Index
    }
}

function Get-Act([int]$pos) {
    $hit = $acts | Where-Object { $_.Pos -le $pos } | Select-Object -Last 1
    if ($hit) { $hit.Name -replace '^act', '' } else { 'top' }
}

$rows = New-Object System.Collections.Generic.List[object]

# pair(t, 'a', 'b') and pair(t, 'a') across newlines. Strings are single-quoted in this file.
$pairRx = [regex]"pair\(\s*[^,]+,\s*'((?:[^'\\]|\\.)*)'\s*(?:,\s*'((?:[^'\\]|\\.)*)'\s*)?(?:,\s*'[^']*'\s*)?\)"
foreach ($m in $pairRx.Matches($src)) {
    $act = Get-Act $m.Index
    $a = $m.Groups[1].Value -replace "\\'", "'"
    $rows.Add([pscustomobject]@{ Trial = $act; Slot = 'A'; Dwell = $dwellA; Text = $a })
    if ($m.Groups[2].Success) {
        $b = $m.Groups[2].Value -replace "\\'", "'"
        $rows.Add([pscustomobject]@{ Trial = $act; Slot = 'B'; Dwell = $dwellB; Text = $b })
    }
}

# Bare say('...') calls that are not inside a pair.
$sayRx = [regex]"(?<!\w)say\(\s*'((?:[^'\\]|\\.)*)'"
foreach ($m in $sayRx.Matches($src)) {
    $act = Get-Act $m.Index
    $t = $m.Groups[1].Value -replace "\\'", "'"
    if ($rows | Where-Object { $_.Text -eq $t }) { continue }
    $rows.Add([pscustomobject]@{ Trial = $act; Slot = 'solo'; Dwell = $dwellSolo; Text = $t })
}

$report = foreach ($r in $rows) {
    $need = [math]::Round(($r.Text.Length / $charsPerMs) + $NoticeMs)
    $p = if ($actPace.ContainsKey($r.Trial)) { $actPace[$r.Trial] } else { 1.0 }
    $dwell = [int]($r.Dwell * $p)
    [pscustomobject]@{
        Trial  = $r.Trial
        Slot   = $r.Slot
        Chars  = $r.Text.Length
        Dwell  = $dwell
        Need   = [int]$need
        Margin = [int]($dwell - $need)
        Text   = $r.Text
    }
}

$tight = $report | Where-Object { $_.Margin -lt 0 } | Sort-Object Margin

Write-Host ""
Write-Host "Intro reading times" -ForegroundColor Cyan
Write-Host ("  pace {0}   read {1} wpm   notice {2} ms" -f $PACE, $WordsPerMinute, $NoticeMs)
Write-Host ("  dwell: couplet line A {0} ms, line B {1} ms, solo {2} ms" -f [int]$dwellA, [int]$dwellB, [int]$dwellSolo)
Write-Host ("  {0} lines, {1} too fast to read" -f $report.Count, $tight.Count) -ForegroundColor $(if ($tight.Count) { 'Yellow' } else { 'Green' })
Write-Host ""

$show = if ($OnlyTight) { $tight } else { $report }
$show | ForEach-Object {
    $colour = if ($_.Margin -lt 0) { 'Red' } elseif ($_.Margin -lt 600) { 'Yellow' } else { 'DarkGray' }
    Write-Host ("  {0,-12} {1,-4} {2,3}ch  dwell {3,5}  need {4,5}  margin {5,6}  {6}" -f `
        $_.Trial, $_.Slot, $_.Chars, $_.Dwell, $_.Need, $_.Margin, $_.Text) -ForegroundColor $colour
}

Write-Host ""
Write-Host "Per trial" -ForegroundColor Cyan
$report | Group-Object Trial | ForEach-Object {
    $bad = @($_.Group | Where-Object { $_.Margin -lt 0 }).Count
    Write-Host ("  {0,-12} {1,3} lines, {2,2} too fast, worst margin {3}" -f `
        $_.Name, $_.Count, $bad, ($_.Group | Measure-Object Margin -Minimum).Minimum)
}
Write-Host ""

# ---- trial length audit ----
# dur in ACTS is declared, not derived from the cues. Nothing in intro.js checks the two agree, so
# a trial can schedule narration past the point where the next trial's clearField() wipes it, or
# run out of cues and sit on a still frame. Both only show up on screen.

$bounds = @([regex]::Matches($src, '(?m)^\s*function\s+\w+') | ForEach-Object { $_.Index }) + $src.Length | Sort-Object
$calc = New-Object System.Data.DataTable

# Offsets are arithmetic over the timing constants plus whatever locals the trial declares, so they
# are resolved by substitution and evaluated as arithmetic rather than executed.
function Resolve-Offset([string]$expr, [hashtable]$syms) {
    $e = $expr.Trim()
    foreach ($k in ($syms.Keys | Sort-Object -Property Length -Descending)) {
        $e = [regex]::Replace($e, "\b$([regex]::Escape($k))\b", [string]$syms[$k])
    }
    if ($e -notmatch '^[\d\s\.\+\-\*\/\(\)]+$') { return $null }
    try { [double]$calc.Compute($e, $null) } catch { $null }
}

$timing = foreach ($a in $acts) {
    $short = $a.Name -replace '^act', ''
    if (-not $actDur.ContainsKey($short)) { continue }

    $end = ($bounds | Where-Object { $_ -gt $a.Pos } | Select-Object -First 1)
    $body = $src.Substring($a.Pos, $end - $a.Pos)

    $syms = @{ OPEN = $OPEN; PAIR = $PAIR; CYCLE = $CYCLE }
    foreach ($c in [regex]::Matches($body, '(?m)^\s*const\s+(\w+)\s*=\s*([^;]+);')) {
        $v = Resolve-Offset $c.Groups[2].Value $syms
        if ($null -ne $v) { $syms[$c.Groups[1].Value] = $v }
    }

    $last = 0.0
    $unresolved = 0
    foreach ($c in [regex]::Matches($body, '(?<!\w)(at|pair)\(\s*([^,]+),')) {
        $v = Resolve-Offset $c.Groups[2].Value $syms
        if ($null -eq $v) { $unresolved++; continue }
        # A couplet's second line lands PAIR after the offset it was scheduled at.
        if ($c.Groups[1].Value -eq 'pair') { $v += $PAIR }
        if ($v -gt $last) { $last = $v }
    }

    [pscustomobject]@{
        Trial      = $short
        Dur        = $actDur[$short]
        LastCue    = [int]$last
        Slack      = [int]($actDur[$short] - $last)
        Unresolved = $unresolved
    }
}

Write-Host "Trial length" -ForegroundColor Cyan
Write-Host ("  last cue needs {0} ms after it for the closing line to be read" -f [int]$BOT_OUT)
Write-Host ""
$timing | ForEach-Object {
    $verdict =
        if ($_.Slack -lt 0) { 'OVERRUN, cues fire after the next trial starts' }
        elseif ($_.Slack -lt $BOT_OUT) { 'TIGHT, closing line is cut short' }
        elseif ($_.Slack -gt ($BOT_OUT + $CYCLE)) { 'DEAD AIR on a still frame' }
        else { 'ok' }
    $colour =
        if ($_.Slack -lt 0) { 'Red' }
        elseif ($_.Slack -lt $BOT_OUT -or $_.Slack -gt ($BOT_OUT + $CYCLE)) { 'Yellow' }
        else { 'DarkGray' }
    Write-Host ("  {0,-12} dur {1,6}  last cue {2,6}  slack {3,6}  {4}" -f `
        $_.Trial, $_.Dur, $_.LastCue, $_.Slack, $verdict) -ForegroundColor $colour
}
if (@($timing | Where-Object { $_.Unresolved -gt 0 }).Count) {
    Write-Host ""
    $timing | Where-Object { $_.Unresolved -gt 0 } | ForEach-Object {
        Write-Host ("  {0}: {1} offsets could not be resolved, so the last cue may be later" -f `
            $_.Trial, $_.Unresolved) -ForegroundColor Yellow
    }
}
Write-Host ""
