@echo off
chcp 65001 >nul
SETLOCAL EnableDelayedExpansion

echo ==========================================
echo   Z-Sync v2.0 - จัดการโปรเจกต์
echo ==========================================
echo.

:: ล้าง Port 3000 ก่อนเริ่มเสมอ
echo  [*] กำลังเคลียร์ Port 3000...
for /f "tokens=5" %%a in ('netstat -aon ^| findstr :3000') do (
    taskkill /f /pid %%a >nul 2>&1
)
echo  [OK] พร้อมใช้งาน
echo.

:: แสดงรายชื่อโปรเจกต์ที่มีอยู่
if exist "projects" (
    echo   โปรเจกต์เดิมที่มี:
    for /D %%d in (projects\*) do (
        echo     - %%~nxd
    )
    echo.
)

:: ถามชื่อโปรเจกต์
set /p PROJECT_NAME="  ระบุชื่อโปรเจกต์ (Map Name): "

if "%PROJECT_NAME%"=="" (
    echo  [ERROR] ชื่อโปรเจกต์ห้ามเป็นค่าว่าง
    pause & exit /b 1
)

echo.
echo  โปรเจกต์ที่เลือก: %PROJECT_NAME%
echo.

:: Step 1: ติดตั้งปลั๊กอินไปยัง Roblox Studio
echo  [1/3] กำลังติดตั้งปลั๊กอิน...
set "PLUGIN_DIR=%LOCALAPPDATA%\Roblox\Plugins\AIBridge"

if exist "%PLUGIN_DIR%" ( rmdir /S /Q "%PLUGIN_DIR%" )
mkdir "%PLUGIN_DIR%"

copy /Y "studio\plugin.lua" "%PLUGIN_DIR%\init.server.lua" >nul
echo  [OK] ติดตั้งปลั๊กอินสำเร็จ: %PLUGIN_DIR%
echo.

:: Step 2: ตรวจสอบ Dependencies
echo  [2/3] ตรวจสอบระบบ Node.js...
if not exist "node_modules" (
    echo  [!] กำลังติดตั้งไลบรารีที่จำเป็น...
    powershell -ExecutionPolicy Bypass -Command "npm install"
) else (
    echo  [OK] ระบบพร้อมทำงาน
)
echo.

:: Step 3: เริ่มการทำงานของเซิร์ฟเวอร์
echo  [3/3] กำลังเริ่มเซิร์ฟเวอร์สำหรับโปรเจกต์: %PROJECT_NAME%
echo.
echo  =========================================
echo  [TIP] หากปลั๊กอินไม่ขึ้น ให้รีสตาร์ท Studio
echo  [TIP] กดปุ่ม Push ในเกมเพื่อเขียนไฟล์ลงที่:
echo        projects\%PROJECT_NAME%\src\
echo  [TIP] แก้ไขไฟล์สคริปต์บนคอมเพื่อ Sync ทันที!
echo  [TIP] กด Ctrl+C เพื่อหยุดการทำงาน
echo  =========================================
echo.
powershell -ExecutionPolicy Bypass -Command "node core/main.js '%PROJECT_NAME%'"

echo.
echo  [INFO] ปิดเซิร์ฟเวอร์แล้ว
pause
