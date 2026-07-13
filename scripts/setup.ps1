<#
  setup.ps1 — Prepara el proyecto Flutter para compilar.

  Qué hace (idempotente, puedes re-ejecutarlo):
    1. Verifica que 'flutter' esté en el PATH.
    2. Genera la carpeta nativa android/ (scaffold en carpeta temporal y copia),
       SIN pisar lib/, pubspec.yaml ni los archivos escritos a mano.
    3. Habilita cleartext HTTP en el manifest (para backend http://... en dev).
    4. flutter pub get.
    5. Genera el código de drift (build_runner).
    6. (Opcional) analyze + test.

  Uso:
    cd C:\Users\geoal\Documents\SoftwareDev\layerflow-mobile
    powershell -ExecutionPolicy Bypass -File .\scripts\setup.ps1
#>

param(
  [switch]$SkipTests
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

function Assert-LastExit($msg) {
  if ($LASTEXITCODE -ne 0) { throw $msg }
}

Write-Host '==> Verificando Flutter...' -ForegroundColor Cyan
$flutter = Get-Command flutter -ErrorAction SilentlyContinue
if (-not $flutter) {
  throw "No se encontró 'flutter' en el PATH. Instala el Flutter SDK y agrega <flutter>\bin al PATH. Ver README.md."
}
flutter --version
Assert-LastExit 'flutter --version falló.'

# --- 2. Scaffold nativo android/ sin pisar el código ---
if (-not (Test-Path (Join-Path $root 'android'))) {
  Write-Host '==> Generando carpeta nativa android/ (scaffold temporal)...' -ForegroundColor Cyan
  $tmp = Join-Path $root '.flutter_scaffold_tmp'
  if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }

  flutter create --platforms=android --org com.layerflow --project-name layerflow_capture "$tmp"
  Assert-LastExit 'flutter create (scaffold) falló.'

  Copy-Item (Join-Path $tmp 'android') -Destination $root -Recurse -Force
  if (-not (Test-Path (Join-Path $root '.metadata'))) {
    Copy-Item (Join-Path $tmp '.metadata') -Destination $root -Force
  }
  Remove-Item $tmp -Recurse -Force
  Write-Host '    android/ creado.' -ForegroundColor Green
} else {
  Write-Host '==> android/ ya existe; se conserva.' -ForegroundColor Yellow
}

# --- 3. Habilitar cleartext HTTP en el manifest (dev) ---
$manifest = Join-Path $root 'android\app\src\main\AndroidManifest.xml'
if (Test-Path $manifest) {
  $content = Get-Content $manifest -Raw
  if ($content -notmatch 'usesCleartextTraffic') {
    $content = $content -replace '<application', '<application android:usesCleartextTraffic="true"'
    Set-Content $manifest $content -Encoding utf8
    Write-Host '==> Cleartext HTTP habilitado en el manifest (dev).' -ForegroundColor Green
  } else {
    Write-Host '==> Cleartext ya estaba habilitado.' -ForegroundColor Yellow
  }
}

# --- 4. Dependencias ---
Write-Host '==> flutter pub get...' -ForegroundColor Cyan
flutter pub get
Assert-LastExit 'flutter pub get falló.'

# --- 5. Codegen (drift) ---
Write-Host '==> Generando código (build_runner)...' -ForegroundColor Cyan
dart run build_runner build --delete-conflicting-outputs
Assert-LastExit 'build_runner falló.'

# --- 6. Verificación opcional ---
if (-not $SkipTests) {
  Write-Host '==> flutter analyze...' -ForegroundColor Cyan
  flutter analyze
  Write-Host '==> flutter test...' -ForegroundColor Cyan
  flutter test
}

Write-Host ''
Write-Host 'Listo. Para correr en un dispositivo/emulador Android:' -ForegroundColor Green
Write-Host '    flutter devices'
Write-Host '    flutter run'
Write-Host 'Para un APK instalable:' -ForegroundColor Green
Write-Host '    flutter build apk --release'
