# Runs Flutter's tool_backend.bat for flutter_assemble. Called from
# CMakeLists.txt next to this file.
#
# When a shader cannot be compiled for Skia, Flutter compiles it without Skia
# and carries on, but prints the Skia compiler's output as a warning, and that
# output has lines like "error: 58: loop index ...". MSBuild treats any line of
# that shape as a build error and fails the step with code -1 even though the
# tool exited 0. liquid_glass_renderer's shaders do this; they only run on
# Impeller, never on desktop.
#
# Those compiler lines ("error: <line>: ...") are reworded. The exit code is the
# tool's own, so a shader that really fails still fails the build.
param(
  [Parameter(Mandatory = $true)][string]$Backend,
  [Parameter(ValueFromRemainingArguments = $true)][string[]]$BackendArgs
)

$ErrorActionPreference = 'Continue'

$Backend = $Backend -replace '/', '\'
$quotedArgs = ($BackendArgs | ForEach-Object { '"' + $_ + '"' }) -join ' '
[Console]::Out.WriteLine("tool_backend.ps1: $Backend $quotedArgs")

cmd.exe /d /s /c "`"$Backend`" $quotedArgs 2>&1" | ForEach-Object {
  $line = [string]$_
  if ($line -match '^\s*error:\s*\d+:') {
    $line = $line -replace '^(\s*)error:', '$1shader compiler (Skia):'
  }
  [Console]::Out.WriteLine($line)
}
exit $LASTEXITCODE
