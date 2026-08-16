# 豆图 · 一键打包 APK 脚本
#
# 背景：项目路径「F:\拼豆图转化器」含中文，Windows 上 Android Gradle 的
# AOT 快照阶段（dart.exe）读 .dart_tool 路径会出现编码乱码，无法在原路径直接打包。
# 本脚本自动把源码同步到纯 ASCII 路径（F:\doutu_build）构建，再把 APK 拷回项目根目录。
#
# 用法：
#   正式版：powershell -ExecutionPolicy Bypass -File tools\build_apk.ps1
#   试用版：powershell -ExecutionPolicy Bypass -File tools\build_apk.ps1 -Trial `
#             -SupabaseUrl https://xxxx.supabase.co -SupabaseKey eyJ...
#
# 产物：项目根目录 豆图_v<版本>_<abi>.apk（arm64-v8a / armeabi-v7a / x86_64）
#       试用版前缀为 豆图试用版_v<版本>_<abi>.apk（独立 applicationId .trial，可与正式版共存）

param(
  [switch]$Trial,
  [string]$SupabaseUrl = '',
  [string]$SupabaseKey = ''
)

$ErrorActionPreference = 'Stop'

$Source = Split-Path -Parent $PSScriptRoot   # 项目根（F:\拼豆图转化器）
$Build  = 'F:\doutu_build'                    # 纯 ASCII 构建目录

# 1) 读版本号
$pubspec = Get-Content (Join-Path $Source 'pubspec.yaml') -Raw -Encoding utf8
if ($pubspec -match 'version:\s*([0-9]+\.[0-9]+\.[0-9]+)') {
  $Version = $Matches[1]
} else {
  throw '无法从 pubspec.yaml 解析版本号'
}
$Label = if ($Trial) { '豆图试用版' } else { '豆图' }
Write-Host "==> $Label v$Version 打包开始" -ForegroundColor Cyan
if ($Trial -and (-not $SupabaseUrl -or -not $SupabaseKey)) {
  Write-Warning '试用版需要 -SupabaseUrl 与 -SupabaseKey（激活服务），否则激活功能不可用'
}

# 2) 同步源码到 ASCII 路径（排除构建产物/大目录）
robocopy $Source $Build /E /XD .git .dart_tool build docs output supabase android\.gradle android\app\build `
  /XF *.apk *.lock /NFL /NDL /NJH /NJS /NP | Out-Null
if ($LASTEXITCODE -ge 8) { throw "robocopy 失败（exit=$LASTEXITCODE）" }
Write-Host '==> 源码已同步到 F:\doutu_build' -ForegroundColor Cyan

# 3) 组装 dart-defines 并构建
$defines = @()
if ($Trial) {
  $defines += '--dart-define=TRIAL_MODE=true'
  if ($SupabaseUrl)  { $defines += "--dart-define=SUPABASE_URL=$SupabaseUrl" }
  if ($SupabaseKey)  { $defines += "--dart-define=SUPABASE_ANON_KEY=$SupabaseKey" }
}
Push-Location $Build
try {
  # 用 dart pub get（flutter pub get 在 Windows 上会检查开发者模式）
  dart pub get | Out-Null
  flutter build apk --release --split-per-abi --obfuscate `
    --split-debug-info=./build/symbols --tree-shake-icons @defines
  if ($LASTEXITCODE -ne 0) { throw 'flutter build 失败' }
} finally {
  Pop-Location
}

# 4) 拷回项目根目录
$apkDir = Join-Path $Build 'build\app\outputs\flutter-apk'
$prefix = if ($Trial) { '豆图试用版' } else { '豆图' }
$map = @{
  'app-arm64-v8a-release.apk'    = "${prefix}_v${Version}_arm64-v8a.apk"
  'app-armeabi-v7a-release.apk'  = "${prefix}_v${Version}_armeabi-v7a.apk"
  'app-x86_64-release.apk'       = "${prefix}_v${Version}_x86_64.apk"
}
foreach ($k in $map.Keys) {
  $p = Join-Path $apkDir $k
  if (Test-Path $p) {
    Copy-Item $p (Join-Path $Source $map[$k]) -Force
    Write-Host "    $($map[$k])" -ForegroundColor Green
  }
}
Write-Host "==> 完成：APK 已输出到项目根目录" -ForegroundColor Cyan
