<#
.SYNOPSIS
  Rebuild capstone/intro-script-review.md from the current intro.js.

.DESCRIPTION
  The review document is a table of every narration line, card, banner and stamp in the intro, in
  order, with a Note column for markup. Keeping it in step by hand does not work, and a review
  document that disagrees with the thing it reviews is worse than none.

  This reads intro.js, extracts every authored string in source order, groups them by trial, and
  writes the tables. Prose sections at the top and bottom of the document are preserved verbatim,
  and any Note already written against an identical line is carried across.

  Ids are positional, so they change when lines are inserted. Quote the text when that matters.

.EXAMPLE
  .\scripts\New-IntroScriptReview.ps1

.EXAMPLE
  .\scripts\New-IntroScriptReview.ps1 -WhatIf
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$Source = (Join-Path (Split-Path -Parent $PSScriptRoot) 'capstone\prototype\intro.js'),
    [string]$Target = (Join-Path (Split-Path -Parent $PSScriptRoot) 'capstone\intro-script-review.md')
)

$ErrorActionPreference = 'Stop'
$src = Get-Content -LiteralPath $Source -Raw

# Existing notes, keyed on the exact line text, so review comments survive a rebuild.
$oldNotes = @{}
if (Test-Path -LiteralPath $Target) {
    foreach ($line in Get-Content -LiteralPath $Target) {
        if ($line -match '^\|\s*[\w.\-]+\s*\|\s*\w+\s*\|\s*(.+?)\s*\|\s*(.*?)\s*\|\s*$') {
            $text = $matches[1]; $note = $matches[2]
            if ($note -and $text -ne 'Text') { $oldNotes[$text] = $note }
        }
    }
}

# Trial order comes from the ACTS table, which is the order the audience sees.
$actsBlock = [regex]::Match($src, 'const ACTS = \[(.*?)\];', 'Singleline').Groups[1].Value
$acts = [regex]::Matches($actsBlock, "name:\s*'([^']+)'.*?run:\s*(\w+)") | ForEach-Object {
    [pscustomobject]@{ Title = $_.Groups[1].Value; Fn = $_.Groups[2].Value }
}

function Get-Body([string]$fn) {
    $start = $src.IndexOf("function $fn(")
    if ($start -lt 0) { return '' }
    $next = [regex]::Match($src.Substring($start + 10), '(?m)^  function \w+\(')
    $len = if ($next.Success) { $next.Index + 10 } else { $src.Length - $start }
    return $src.Substring($start, $len)
}

function Get-Rows([string]$body) {
    $hits = New-Object System.Collections.Generic.List[object]
    $add = { param($pos, $type, $text) $hits.Add([pscustomobject]@{ Pos = $pos; Type = $type; Text = $text }) }

    # pair(offset, 'a', 'b'[, tone]) and pair(offset, 'a')
    $rx = [regex]"pair\(\s*[^,]+,\s*'((?:[^'\\]|\\.)*)'\s*(?:,\s*'((?:[^'\\]|\\.)*)'\s*)?(?:,\s*'[^']*'\s*)?\)"
    foreach ($m in $rx.Matches($body)) {
        & $add $m.Index 'say' ($m.Groups[1].Value -replace "\\'", "'")
        if ($m.Groups[2].Success) { & $add ($m.Index + 1) 'say' ($m.Groups[2].Value -replace "\\'", "'") }
    }
    foreach ($m in [regex]::Matches($body, "(?<!\w)say\(\s*'((?:[^'\\]|\\.)*)'")) {
        $t = $m.Groups[1].Value -replace "\\'", "'"
        if (-not ($hits | Where-Object { $_.Text -eq $t })) { & $add $m.Index 'say' $t }
    }
    foreach ($m in [regex]::Matches($body, "(?<!\w)card\(\s*'((?:[^'\\]|\\.)*)'")) {
        & $add $m.Index 'card' ($m.Groups[1].Value -replace "\\'", "'")
    }
    foreach ($m in [regex]::Matches($body, "(?<!\w)slam\(\s*'((?:[^'\\]|\\.)*)'")) {
        & $add $m.Index 'slam' ($m.Groups[1].Value -replace "\\'", "'")
    }
    foreach ($m in [regex]::Matches($body, "banner\(\s*'((?:[^'\\]|\\.)*)'\s*,\s*'((?:[^'\\]|\\.)*)'")) {
        & $add $m.Index 'banner' (($m.Groups[1].Value -replace "\\'", "'") + '  [' + $m.Groups[2].Value + ']')
    }
    foreach ($m in [regex]::Matches($body, "stampOn\(\s*'[^']*'\s*,\s*'((?:[^'\\]|\\.)*)'")) {
        & $add $m.Index 'stamp' ($m.Groups[1].Value -replace "\\'", "'")
    }
    foreach ($m in [regex]::Matches($body, "stamp\(\s*\w+\(?\)?[^,]*,\s*'((?:[^'\\]|\\.)*)'")) {
        & $add $m.Index 'stamp' ($m.Groups[1].Value -replace "\\'", "'")
    }
    foreach ($m in [regex]::Matches($body, "plate\(\s*MEDIA \+ '[^']*'\s*,\s*\r?\n?\s*'((?:[^'\\]|\\.)*)'")) {
        & $add $m.Index 'plate' ($m.Groups[1].Value -replace "\\'", "'")
    }
    foreach ($m in [regex]::Matches($body, "slate\(\s*'((?:[^'\\]|\\.)*)'\s*,\s*'((?:[^'\\]|\\.)*)'")) {
        $sub = $m.Groups[2].Value
        if ($sub) { & $add $m.Index 'slate' $sub }
    }
    return $hits | Sort-Object Pos
}

# Keep everything the humans wrote, drop only the generated tables. Accepts either heading, since
# the first run renamed Act to Trial and the split has to survive its own output.
$doc = Get-Content -LiteralPath $Target -Raw
$cut = @("`n## Trial ", "`n## Act ") | ForEach-Object { $doc.IndexOf($_) } | Where-Object { $_ -ge 0 } |
    Sort-Object | Select-Object -First 1
if ($null -eq $cut) { throw "No generated section found in $Target. Expected a '## Trial' or '## Act' heading." }
$head = $doc.Substring(0, $cut)
$tailIdx = $doc.IndexOf("`n## Open questions")
$tail = if ($tailIdx -ge 0) { $doc.Substring($tailIdx) } else { '' }

$sb = New-Object System.Text.StringBuilder
[void]$sb.Append($head.TrimEnd())
[void]$sb.AppendLine()

$n = 0
foreach ($a in $acts) {
    $n++
    $rows = Get-Rows (Get-Body $a.Fn)
    if (-not $rows) { continue }
    [void]$sb.AppendLine()
    [void]$sb.AppendLine("---")
    [void]$sb.AppendLine()
    [void]$sb.AppendLine("## Trial $n - $($a.Title)")
    [void]$sb.AppendLine()
    [void]$sb.AppendLine('| id | Type | Text | Note |')
    [void]$sb.AppendLine('| --- | --- | --- | --- |')
    $i = 0
    foreach ($r in $rows) {
        $i++
        $id = 't{0}-{1:00}' -f $n, $i
        $note = if ($oldNotes.ContainsKey($r.Text)) { $oldNotes[$r.Text] } else { '' }
        [void]$sb.AppendLine("| $id | $($r.Type) | $($r.Text) | $note |")
    }
}

if ($tail) { [void]$sb.AppendLine(); [void]$sb.Append($tail.TrimEnd()); [void]$sb.AppendLine() }

if ($PSCmdlet.ShouldProcess($Target, 'rewrite script review')) {
    Set-Content -LiteralPath $Target -Value $sb.ToString() -Encoding ascii
    Write-Host "Rebuilt $Target" -ForegroundColor Green
    Write-Host ("  {0} trials, {1} rows, {2} notes carried over" -f $n,
        ([regex]::Matches($sb.ToString(), '(?m)^\| t\d')).Count,
        ($oldNotes.Count)) -ForegroundColor DarkGray
}
