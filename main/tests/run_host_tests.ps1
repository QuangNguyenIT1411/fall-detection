param(
    [Parameter(Mandatory=$true)][string]$Compiler,
    [Parameter(Mandatory=$true)][string]$IdfPath
)
$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$testOutput = Join-Path $projectRoot 'build/host-tests'
$jsonSource = Join-Path $IdfPath 'components/json/cJSON'
New-Item -ItemType Directory -Path $testOutput -Force | Out-Null
$compilerFlags = @('-DCJSON_HIDE_SYMBOLS')
if ([IO.Path]::GetFileNameWithoutExtension($Compiler) -eq 'tcc') {
    # Win64 has one calling convention; older TinyCC needs these aliases.
    $compilerFlags += @('-D__cdecl=', '-D__stdcall=')
}
& $Compiler @compilerFlags '-I' (Join-Path $PSScriptRoot 'stubs') '-I' $jsonSource `
    (Join-Path $PSScriptRoot 'buzzer_output_test.c') `
    (Join-Path $projectRoot 'main/buzzer_output.c') `
    (Join-Path $projectRoot 'main/manual_sos.c') `
    (Join-Path $jsonSource 'cJSON.c') '-o' (Join-Path $testOutput 'buzzer_output_test.exe')
if ($LASTEXITCODE -ne 0) { throw 'Buzzer host test compilation failed' }
& (Join-Path $testOutput 'buzzer_output_test.exe')
if ($LASTEXITCODE -ne 0) { throw 'Buzzer host tests failed' }
& $Compiler (Join-Path $PSScriptRoot 'manual_sos_test.c') `
    (Join-Path $projectRoot 'main/manual_sos.c') '-o' (Join-Path $testOutput 'manual_sos_test.exe')
if ($LASTEXITCODE -ne 0) { throw 'SOS host test compilation failed' }
& (Join-Path $testOutput 'manual_sos_test.exe')
if ($LASTEXITCODE -ne 0) { throw 'SOS host tests failed' }
