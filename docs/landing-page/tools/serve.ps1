# Local preview of the landing page (localhost only).  Usage:  .\docs\landing-page\tools\serve.ps1 [-Port 8080]
param([int]$Port = 8080)
# This script lives in docs/landing-page/tools; the site is <repo>/landing-page.
$repo = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
$root = Join-Path $repo 'landing-page'
Write-Host "Yalla Cash landing page: http://localhost:$Port/  (Ctrl+C to stop)"
python -m http.server $Port --bind 127.0.0.1 --directory $root
