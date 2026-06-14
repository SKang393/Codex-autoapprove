@echo off
setlocal
title Codex Auto Approve GUI
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0CodexAutoApproveGui.ps1"
