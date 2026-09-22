@echo off
chcp 65001 >nul
setlocal
title DEWIN Booster - Otimizador do Sistema
cd /d "%~dp0"

:: 1. Se dewin.ps1 nao existir, compila a partir dos fontes
if not exist "%~dp0dewin.ps1" (
    echo [*] Compilando DEWIN Booster a partir do codigo-fonte...
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Compile.ps1"
)

:: 2. Verifica se ja possui privilegios de Administrador
net session >nul 2>&1
if %errorLevel% == 0 goto :RUN_ADMIN

:: 3. Se nao for Administrador, solicita elevacao via UAC e finaliza o processo chamador
echo [*] Solicitando privilegios de Administrador...
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Start-Process powershell.exe -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File',('%~dp0dewin.ps1') -Verb RunAs"
exit /b

:RUN_ADMIN
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0dewin.ps1"
set "EXIT_CODE=%errorLevel%"

if %EXIT_CODE% neq 0 (
    echo.
    echo [!] Ocorreu uma interrupcao durante a execucao (Codigo: %EXIT_CODE%).
    pause
)
