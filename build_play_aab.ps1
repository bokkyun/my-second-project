# Google Play 콘솔 업로드용 Android App Bundle(.aab) 생성
# APK(app-release.apk)가 아니라 반드시 이 스크립트로 만든 .aab를 올려야 합니다.
# 사용: PowerShell에서 프로젝트 루트(my-second-project)로 이동 후:
#   .\build_play_aab.ps1

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

Write-Host "flutter build appbundle --release 실행 중..." -ForegroundColor Cyan
flutter build appbundle --release
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$out = Join-Path $PSScriptRoot "build\app\outputs\bundle\release\app-release.aab"
Write-Host ""
Write-Host "완료: $out" -ForegroundColor Green
Write-Host "Play Console 'App Bundle' 업로드 영역에 위 .aab 파일을 드래그하세요." -ForegroundColor Yellow
