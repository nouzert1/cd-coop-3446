$ErrorActionPreference = 'Continue'
$probe = "C:\Users\ACER\Downloads\Mods\CD-coop-3424\build\bin\RelWithDebInfo\cdmp_probe.exe"
$exe = "C:\Program Files (x86)\Steam\steamapps\common\Crimson Desert\bin64\CrimsonDesert.exe"

# Work in IMAGE-RELATIVE offsets throughout. The probe prints and accepts "exe+0xNNN",
# and the mod's own Site structs are relative, so there is no reason to add a base and
# subtract it again -- doing that is what produced the negative-overflow errors above.
$want = '48 89 5C 24 10 55 56 57 41 54 41 55 41 56 41 57'
$vtOff = 0x59388D0
$imgSize = 0x14268000

function Rel([int64]$o) { return 'exe+0x{0:X}' -f $o }

function Get-Bytes([int64]$off, [int]$n) {
    $o = & $probe --image $exe read (Rel $off) --type u8 --count $n 2>&1
    $b = @()
    foreach ($l in $o) {
        if ($l -match ':\s*\d+ \(0x([0-9A-Fa-f]+)\)') { $b += $matches[1].PadLeft(2, '0').ToUpper() }
    }
    return , $b
}

function Get-Ptr([int64]$off) {
    $b = Get-Bytes $off 8
    if ($b.Count -lt 8) { return [int64](-1) }
    $lit = [Convert]::ToInt64(($b[7] + $b[6] + $b[5] + $b[4] + $b[3] + $b[2] + $b[1] + $b[0]), 16)
    # Absolute VA -> relative offset.
    return $lit - 0x140000000
}

function Get-JmpTarget([int64]$off) {
    $b = Get-Bytes $off 5
    if ($b.Count -lt 5 -or $b[0] -ne 'E9') { return [int64](-1) }
    $disp = [Convert]::ToInt64(($b[4] + $b[3] + $b[2] + $b[1]), 16)
    if ($disp -ge 0x80000000) { $disp -= 0x100000000 }
    return $off + 5 + $disp
}

Write-Output "=== vtable de ClientCharacterControlActorComponent ($(Rel $vtOff)) ==="
Write-Output "    procurando o prologo do kCcUpdate: $want"
Write-Output ""

$found = @()
for ($i = 0; $i -lt 60; $i++) {
    $slot = $vtOff + $i * 8
    $target = Get-Ptr $slot
    if ($target -lt 0 -or $target -gt $imgSize) { continue }
    $real = $target
    $via = ''
    $bytes = Get-Bytes $real 16
    if ($bytes.Count -gt 0 -and $bytes[0] -eq 'E9') {
        $j = Get-JmpTarget $real
        if ($j -gt 0 -and $j -lt $imgSize) { $via = ' (thunk)'; $real = $j; $bytes = Get-Bytes $real 16 }
    }
    $hex = ($bytes -join ' ')
    $mark = ''
    if ($hex -eq $want) {
        $mark = '  *** MATCH ***'
        $found += ("slot {0} -> {1}{2}" -f $i, (Rel $real), $via)
    }
    Write-Output ("  slot {0,-3} {1,-16}{2}{3}" -f $i, (Rel $real), $via, $mark)
}

Write-Output ""
if ($found.Count -gt 0) {
    Write-Output 'ENCONTRADO:'
    $found | ForEach-Object { Write-Output "  $_" }
} else {
    Write-Output 'nenhum slot bate com o prologo do kCcUpdate'
}
