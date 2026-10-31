$ErrorActionPreference = 'Continue'
$probe = "C:\Users\ACER\Downloads\Mods\CD-coop-3424\build\bin\RelWithDebInfo\cdmp_probe.exe"
$exe = "C:\Program Files (x86)\Steam\steamapps\common\Crimson Desert\bin64\CrimsonDesert.exe"

# Find the other three containment hooks by their BEHAVIOUR, not by a byte signature.
#
# A byte signature failed: the 16-byte prologues the mod stores for kCcPost, kRestore and
# kPending each match 18-30+ places in a 332 MB binary, so a scan returns a haystack.
#
# What actually identifies these functions is that they operate on the same component
# struct as kCcUpdate. The mod's read_state() reads cc+0x08 (actor), cc+0x88/0x90
# (layers), cc+0xA8 (pending), cc+0x80 (pending list) and [[cc+0x40]+0x30] (restore).
# kCcUpdate was confirmed by finding four of those offsets in one function. So: walk the
# vtable, disassemble each method, and score it by how many of those offsets appear.
#
# The slot order in a vtable is stable across patch builds for the same compiler, so the
# slots adjacent to kCcUpdate (slot 16) are the natural candidates.

$vtOff = 0x59388D0
$imgSize = 0x14268000
$ccUpdate = 0x941D40

function Rel([int64]$o) { return 'exe+0x{0:X}' -f $o }

function Get-Bytes([int64]$off, [int]$n) {
    $o = & $probe --image $exe read (Rel $off) --type u8 --count $n 2>&1
    $b = @()
    foreach ($l in $o) { if ($l -match ':\s*\d+ \(0x([0-9A-Fa-f]+)\)') { $b += $matches[1].PadLeft(2, '0').ToUpper() } }
    return , $b
}

function Get-Ptr([int64]$off) {
    $b = Get-Bytes $off 8
    if ($b.Count -lt 8) { return [int64](-1) }
    return [Convert]::ToInt64(($b[7] + $b[6] + $b[5] + $b[4] + $b[3] + $b[2] + $b[1] + $b[0]), 16) - 0x140000000
}

function Get-JmpTarget([int64]$off) {
    $b = Get-Bytes $off 5
    if ($b.Count -lt 5 -or $b[0] -ne 'E9') { return [int64](-1) }
    $d = [Convert]::ToInt64(($b[4] + $b[3] + $b[2] + $b[1]), 16)
    if ($d -ge 0x80000000) { $d -= 0x100000000 }
    return $off + 5 + $d
}

# Score a function by how many distinctive cc offsets its code touches.
function Score-Cc([int64]$off) {
    $seen = @{}
    $len = 0
    for ($i = 0; $i -lt 24; $i++) {
        $chunk = Get-Bytes ($off + $len) 200
        if ($chunk.Count -lt 200) { break }
        $len += 200
        if ($len -ge 1200) { break }
    }
    $d = & $probe --image $exe disasm (Rel $off) --count 90 2>&1
    $text = ($d -join "`n")
    foreach ($pat in '\[r\w+\+0x88\]', '\[r\w+\+0x90\]', '\[r\w+\+0xA8\]', '\[r\w+\+0x80\]', '\[r\w+\+0x40\]', '\[r\w+\+0x08\]') {
        if ($text -match $pat) { $seen[$pat] = $true }
    }
    return $seen.Keys.Count
}

Write-Output "=== pontuando os metodos do CC pelos offsets da struct ==="
Write-Output "    (kCcUpdate = $ccUpdate, esperado: pontuacao alta)"
Write-Output ""

$rows = @()
for ($i = 0; $i -lt 60; $i++) {
    $target = Get-Ptr ($vtOff + $i * 8)
    if ($target -lt 0 -or $target -gt $imgSize) { continue }
    $real = $target
    $b = Get-Bytes $real 1
    if ($b.Count -gt 0 -and $b[0] -eq 'E9') {
        $j = Get-JmpTarget $real
        if ($j -gt 0 -and $j -lt $imgSize) { $real = $j }
    }
    $rows += [PSCustomObject]@{ Slot = $i; Off = $real; Score = (Score-Cc $real) }
}

foreach ($r in ($rows | Sort-Object Score -Descending | Select-Object -First 12)) {
    $tag = if ($r.Off -eq $ccUpdate) { '  <-- kCcUpdate (conhecido)' } else { '' }
    Write-Output ("  slot {0,-3} {1,-16} offsets={2}{3}" -f $r.Slot, (Rel $r.Off), $r.Score, $tag)
}
