# Compara os xrefs de um global entre dois builds.
#
# Feito para NAO repetir o erro que produziu a saida ilegivel "071138 refs": a linha de
# resumo do probe e' "N reference(s)" e um -replace '\D','' nela cola o hexadecimal do
# endereco junto com o N, porque a linha inteira tem digitos nos dois lugares.
# Aqui a contagem e' extraida do campo certo e o endereco nunca entra no numero.
param(
    [Parameter(Mandatory)][string] $OldExe,
    [Parameter(Mandatory)][string] $NewExe,
    [Parameter(Mandatory)][string[]] $Globals   # "nome:0xRVA"
)

$ErrorActionPreference = 'Stop'
$probe = "C:\Users\ACER\Downloads\Mods\CD-coop-3424\build\bin\RelWithDebInfo\cdmp_probe.exe"
$imageBase = 0x140000000

function Get-XrefCount([string] $exe, [uint64] $abs) {
    $addr = "0x{0:X}" -f $abs
    $out = & $probe --image $exe xrefs $addr --max 200 2>&1
    foreach ($line in $out) {
        # "3 reference(s)"  -- a contagem e' o primeiro token numerico seguido de "reference"
        if ([string]$line -match '^\s*(\d+)\s+reference') { return [int]$matches[1] }
    }
    return 0
}

Write-Output ("{0,-22} {1,-12} {2,-12} {3}" -f 'global', '3446 refs', '3460 refs', 'veredito')
Write-Output ('-' * 62)

foreach ($g in $Globals) {
    $parts = $g -split ':'
    $name = $parts[0]
    $rva = [Convert]::ToUInt64($parts[1], 16)
    $abs = $imageBase + $rva

    $a = Get-XrefCount $OldExe $abs
    $b = Get-XrefCount $NewExe $abs

    $verdict = if ($a -gt 0 -and $b -gt 0) { 'MESMO ENDERECO' }
               elseif ($a -eq 0 -and $b -eq 0) { 'nenhum dos dois' }
               elseif ($a -gt 0) { 'PERDIDO no 3460' }
               else { 'novo no 3460' }

    Write-Output ("{0,-22} 0x{1:X}  {2,-12} {3,-12} {4}" -f $name, $rva, $a, $b, $verdict)
}
