<#
.SYNOPSIS
  Запускает k6 из compose-стека с отметкой времени в качестве идентификатора прогона.

.EXAMPLE
  .\scripts\k6.ps1 -Script endpoints/demo.js
  .\scripts\k6.ps1 -Script endpoints/demo.js -Mode load -Rate 30 -TimeScale 0.2
  .\scripts\k6.ps1 -Script clinicweb/persons-getpage.js -Mode load -BaseUrl http://host.docker.internal:5210 -Env stand
#>
param(
    [Parameter(Mandatory = $true)][string]$Script,
    [ValidateSet('smoke', 'load', 'stress', 'spike', 'soak')][string]$Mode = 'smoke',
    [string]$BaseUrl = '',
    [string]$Project = '',
    [string]$Env = '',
    [string]$Version = '',
    [double]$TimeScale = 1,
    [int]$Rate = 20
)

$ErrorActionPreference = 'Continue'   # docker пишет статус в stderr, это не ошибка
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$deploy = Join-Path $PSScriptRoot '..\deploy'
$build = Get-Date -Format 'yyyyMMdd-HHmmss'

$envArgs = @(
    '-e', "QH_BUILD=$build",
    '-e', "K6_MODE=$Mode",
    '-e', "K6_TIME_SCALE=$TimeScale",
    '-e', "K6_RATE=$Rate"
)
if ($BaseUrl)  { $envArgs += @('-e', "BASE_URL=$BaseUrl") }
if ($Project)  { $envArgs += @('-e', "QH_PROJECT=$Project") }
if ($Env)      { $envArgs += @('-e', "QH_ENV=$Env") }
if ($Version)  { $envArgs += @('-e', "QH_VERSION=$Version") }

Write-Host "Прогон $build, режим $Mode, сценарий $Script"
Push-Location $deploy
try {
    docker compose --profile load run --rm @envArgs k6 run --quiet "/scripts/$Script"
    $code = $LASTEXITCODE
}
finally {
    Pop-Location
}
Write-Host "Код завершения k6: $code (0 - пороги выполнены, 99 - пороги нарушены)"
exit $code
