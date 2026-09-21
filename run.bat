@echo off
chcp 65001 >nul
setlocal
title DEWIN - Otimizador Pos-Instalacao
cd /d "%~dp0"

:: 1. Verifica se ja esta executando como Administrador
net session >nul 2>&1
if %errorLevel% == 0 (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\apply-dewin.ps1"
) else (
    echo [*] Solicitando privilegios de Administrador...
    powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Start-Process powershell.exe -ArgumentList '-NoProfile -ExecutionPolicy Bypass -File """"%~dp0scripts\apply-dewin.ps1""""' -WorkingDirectory """"%~dp0scripts"""" -Verb RunAs"
)

if %errorLevel% neq 0 (
    echo.
    echo [!] Ocorreu um erro durante a execucao.
    pause
)
