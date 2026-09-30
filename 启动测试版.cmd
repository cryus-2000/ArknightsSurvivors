@echo off
setlocal
set "PROJECT=%~dp0game"
set "GODOT_BIN=%GODOT%"
if not defined GODOT_BIN set "GODOT_BIN=E:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe"
if not exist "%GODOT_BIN%" (
  echo Godot 4.7.2 not found: "%GODOT_BIN%"
  echo Set the GODOT environment variable to the Godot GUI executable.
  pause
  exit /b 1
)
if not exist "%PROJECT%\project.godot" (
  echo Project not found: "%PROJECT%"
  pause
  exit /b 1
)
echo Updating imported assets...
"%GODOT_BIN%" --headless --path "%PROJECT%" --import >nul 2>nul
echo Starting live test build...
start "" "%GODOT_BIN%" --path "%PROJECT%"
