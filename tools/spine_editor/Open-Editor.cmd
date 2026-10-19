@echo off
powershell.exe -NoProfile -File "%~dp0Start-Editor.ps1"
if errorlevel 1 pause
