@echo off
chcp 65001 >nul
title Z-Sync

:: 1. เคลียร์ Port 3000 ก่อนเริ่มเสมอ
echo  [*] Checking Port 3000...
for /f "tokens=5" %%a in ('netstat -aon ^| findstr :3000') do (
    taskkill /f /pid %%a >nul 2>&1
)

:: 2. ตรวจสอบ Node.js
where node >nul 2>&1
if %errorlevel% neq 0 (
    echo [ERROR] No Node.js found!
    pause
    exit /b 1
)

:: 3. เช็คและติดตั้ง Dependencies (npm i)
if not exist "node_modules" (
    echo  [*] node_modules missing. Running npm install...
    call npm install
)

:: 4. รันเมนู Z-Sync (ซ่อน Y/N ด้วย PowerShell)
powershell -NoProfile -ExecutionPolicy Bypass -Command "node core/cli.js"
exit
