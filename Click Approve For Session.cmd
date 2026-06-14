@echo off
setlocal
title Auto Approve For Session
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0ApproveForSessionClicker.ps1" -IntervalSeconds 30
echo.
echo Clicker stopped.
pause
