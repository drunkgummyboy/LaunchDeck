@echo off
title Launch Activation Script
echo Requesting administrative privileges...

:: Check for administrative permissions
net session >nul 2>&1
if %errorLevel% neq 0 (
    powershell -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)

echo Running command: irm https://get.activated.win ^| iex
powershell -NoProfile -ExecutionPolicy Bypass -Command "irm https://get.activated.win | iex"

pause