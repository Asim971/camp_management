<#
.SYNOPSIS
  Runs the app with a Gradle flavor and its MATCHING dart-defines.

.DESCRIPTION
  Gradle flavors and --dart-define are independent: nothing stops
  `--flavor dev --dart-define=FLAVOR=prod`, which installs a dev-ID app
  pointed at the production API. This script derives both from one argument
  so they cannot disagree. Values come from tool/scripts/flavors.env.

.EXAMPLE
  ./tool/scripts/run.ps1 -Flavor dev -Device chrome
  ./tool/scripts/run.ps1 -Flavor stg
#>
param(
  [ValidateSet('dev', 'stg', 'prod')][string]$Flavor = 'dev',
  [string]$Device = ''
)

$ErrorActionPreference = 'Stop'
$envFile = Join-Path $PSScriptRoot 'flavors.env'

$map = @{}
foreach ($line in Get-Content $envFile) {
  if ($line -match '^\s*#' -or $line -notmatch '=') { continue }
  $parts = $line -split '=', 2
  $map[$parts[0].Trim()] = $parts[1].Trim()
}

$apiBase = $map["${Flavor}_API_BASE_URL"]
$mediaHost = $map["${Flavor}_MEDIA_HOST"]
if (-not $apiBase -or -not $mediaHost) {
  throw "flavors.env is missing entries for flavor '$Flavor'"
}

# NOTE: each element MUST be parenthesized. Without the parens, PowerShell's
# comma operator binds tighter than `+`, so `@('--x=' + $a, '--y=' + $b)`
# silently collapses into a ONE-element array (the entries get string-joined
# instead of separated) and Flutter only ever sees a single, garbled
# --dart-define. Verified: with parens, `$dartDefines.Count` is 3.
$dartDefines = @(
  ('--dart-define=FLAVOR=' + $Flavor),
  ('--dart-define=API_BASE_URL=' + $apiBase),
  ('--dart-define=MEDIA_HOST=' + $mediaHost)
)

# NOTE: build this as a typed array via direct assignment, not
# `$x = if (...) { @(...) } else { @() }`. That form pipes the branch's
# output through PowerShell's success-stream, which unrolls an empty array
# to NOTHING and the resulting assignment becomes $null rather than @() —
# splatting a $null variable then injects one stray empty-string argument.
[string[]]$deviceArgs = @()
if ($Device) { $deviceArgs = @('-d', $Device) }

# Gradle flavors only exist on Android; web targets take dart-defines only.
# Every Chromium-family web device Flutter can launch, not just 'chrome'.
$webDevices = @('chrome', 'edge', 'web-server')
if ($Device -in $webDevices) {
  Write-Host "flutter run $deviceArgs ($Flavor)" -ForegroundColor Cyan
  & flutter run @deviceArgs @dartDefines
} else {
  Write-Host "flutter run --flavor $Flavor" -ForegroundColor Cyan
  & flutter run @deviceArgs '--flavor' $Flavor @dartDefines
}
