@echo off
setlocal EnableDelayedExpansion
rem 一键启动最新一次出的对内测试包（全部解锁、只在内存，不写存档；存档在 %APPDATA%\ArknightsSurvivors_Internal）。
rem 包由 python tools/release_all.py 生成，解压目录在 build\release\final_<提交>\internal\（docs/33）。
set "REL=%~dp0build\release"
set "VER="
for /f "delims=" %%D in ('dir /b /ad /o-d "%REL%\final_*" 2^>nul') do (
  if not defined VER (
    if exist "%REL%\%%D\internal\game\ArknightsSurvivors.exe" set "VER=%%D"
  )
)
if not defined VER (
  echo 没找到对内测试包（build\release\final_*\internal）。
  echo 请先在仓库根目录运行：python tools/release_all.py --ref main --only internal
  pause
  exit /b 1
)
echo 启动对内测试版：!VER!
start "" /d "%REL%\!VER!\internal\game" "%REL%\!VER!\internal\game\ArknightsSurvivors.exe"
