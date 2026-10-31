# Configures and builds the project with the installed Visual Studio Build
# Tools, then runs the unit tests.
#
#   .\scripts\build.ps1                    # RelWithDebInfo + tests
#   .\scripts\build.ps1 -Config Debug
#   .\scripts\build.ps1 -SkipTests

param(
    [ValidateSet('Debug', 'Release', 'RelWithDebInfo')]
    [string]$Config = 'RelWithDebInfo',
    [switch]$SkipTests
)
# Native tools write warnings to stderr; with 'Stop' PowerShell 5.1 would turn
# those into terminating errors. Failures are detected via $LASTEXITCODE.
$ErrorActionPreference = 'Continue'
$root = Split-Path $PSScriptRoot -Parent

$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
$vs = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if (-not $vs) { throw 'Visual Studio / Build Tools with the C++ x64 toolset not found' }
$cmakeBin = Join-Path $vs 'Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin'
$cmake = Join-Path $cmakeBin 'cmake.exe'
$ctest = Join-Path $cmakeBin 'ctest.exe'

# The build id is written by `configure_file`, which CMake only re-runs when the INPUT
# changes -- not when HEAD moves. So without this the binary keeps reporting the commit the
# last configure happened to see.
#
# This bit me on 2026-10-30: a fresh build reported "build 0DBA86A6 + local changes" while
# the correctly-fixed binary was installed and running, which reads exactly like a stale
# install and sends you chasing the wrong thing. The running code was right; only the label
# was old. Deleting the generated header forces the regenerate.
$idHeader = Join-Path $root 'build\generated\build_id.h'
if (Test-Path $idHeader) { Remove-Item $idHeader -Force }

& $cmake -S $root -B "$root\build" -G 'Visual Studio 17 2022' -A x64 -Wno-dev -Wno-deprecated
if ($LASTEXITCODE) { throw "CMake configure failed ($LASTEXITCODE)" }

& $cmake --build "$root\build" --config $Config --parallel
if ($LASTEXITCODE) { throw "Build failed ($LASTEXITCODE)" }

if (-not $SkipTests) {
    & $ctest --test-dir "$root\build" -C $Config --output-on-failure
    if ($LASTEXITCODE) { throw "Tests failed ($LASTEXITCODE)" }
}

Write-Host "Build OK: $root\build\bin\$Config"
