@echo off
cd /d "%~dp0"

echo ========================================================
echo     Status VoiceStudio Tihog Servisa
echo ========================================================
echo.

curl -s --connect-timeout 2 http://127.0.0.1:3900/gateway/status 2>nul | findstr /i "status" >nul
if %errorlevel% neq 0 (
    echo [STATUS] Servis NIJE pokrenut na portu 3900.
    echo Mozete ga pokrenuti pomocu 'pokreni_tiho_u_pozadini.bat'.
) else (
    echo [STATUS] Servis je AKTIVAN na portu 3900.
    echo.
    echo Detalji:
    curl -s http://127.0.0.1:3900/gateway/status
    echo.
)
echo ========================================================
echo.
pause
