# Builds the Yalla Cash Customer release APK against the shared backend.
# Usage (from the project root):
#   powershell -ExecutionPolicy Bypass -File scripts\build-customer-release.ps1
# Signing uses apps\yalla_cash_customer\android\key.properties; this script
# never reads or changes credentials.

$ErrorActionPreference = 'Stop'
$ApiBaseUrl = 'https://yalla-cash-api.onrender.com'

$root = Split-Path -Parent $PSScriptRoot
$app = Join-Path $root 'apps\yalla_cash_customer'

# Gradle on Windows cannot build from paths that contain non-ASCII characters.
if ($root -match '[^\x00-\x7F]') {
  throw 'Move the project to an ASCII-only path such as C:\dev\yalla_cash_flutter_mvp.'
}

Push-Location $app
try {
  flutter pub get
  if ($LASTEXITCODE -ne 0) { throw "flutter pub get failed (exit $LASTEXITCODE)." }

  flutter build apk --release "--dart-define=YALLA_CASH_API_BASE_URL=$ApiBaseUrl"
  if ($LASTEXITCODE -ne 0) { throw "flutter build apk failed (exit $LASTEXITCODE)." }

  $apk = Join-Path $app 'build\app\outputs\flutter-apk\app-release.apk'
  if (-not (Test-Path $apk)) { throw 'The release APK was not produced.' }

  $sizeMb = [math]::Round((Get-Item $apk).Length / 1MB, 1)
  Write-Output "APK: $apk ($sizeMb MB)"
} finally {
  Pop-Location
}
