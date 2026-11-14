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
# Inside that warning, and only there, "error" is reworded. The exit code is
# the tool's own, so a shader that really fails still fails the build.
param(
  [Parameter(Mandatory = $true)][string]$Backend,
  [Parameter(ValueFromRemainingArguments = $true)][string[]]$BackendArgs
)

$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$Backend = $Backend -replace '/', '\'
$quotedArgs = ($BackendArgs | ForEach-Object { '"' + $_ + '"' }) -join ' '
$inSkslWarning = $false

cmd.exe /d /s /c "`"$Backend`" $quotedArgs 2>&1" | ForEach-Object {
  $line = [string]$_
  if ($line -match 'is incompatible with SkSL') {
    $inSkslWarning = $true
  } elseif ($inSkslWarning) {
    $partOfIt = $line -match '^\s' -or $line -eq '' -or
      $line -match '^(impellerc failure|SkSL Error|Compilation failed|Full "|error:)'
    if ($partOfIt) {
      $line = $line -replace '(?i)\berror\b', 'issue'
      if ($line -match '^Full "') { $inSkslWarning = $false }
    } else {
      $inSkslWarning = $false
    }
  }
  [Console]::Out.WriteLine($line)
}
exit $LASTEXITCODE
