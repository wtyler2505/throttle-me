@echo off
rem cmd.exe shim for throttle-me.ps1 — lets users type `throttle-me -e` from
rem any cmd window without invoking PowerShell explicitly.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0throttle-me.ps1" %*
