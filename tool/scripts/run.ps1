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

$args = @(
  '--dart-define=FLAVOR=' + $Flavor,
  '--dart-define=API_BASE_URL=' + $apiBase,
  '--dart-define=MEDIA_HOST=' + $mediaHost
)

# Gradle flavors only exist on Android; the web target takes dart-defines only.
if ($Device -eq 'chrome') {
  Write-Host "flutter run -d chrome ($Flavor)" -ForegroundColor Cyan
  & flutter run -d chrome @args
} else {
  $deviceArgs = if ($Device) { @('-d', $Device) } else { @() }
  Write-Host "flutter run --flavor $Flavor" -ForegroundColor Cyan
  & flutter run @deviceArgs '--flavor' $Flavor @args
}
