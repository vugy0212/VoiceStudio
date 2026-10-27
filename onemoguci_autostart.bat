@echo off
cd /d "%~dp0"

echo ========================================================
echo     Uklanjanje automatskog pokretanja sa Windowsima
echo ========================================================
echo.

set "LNK=%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\VoiceStudio_Tihi_Servis.lnk"

if exist "%LNK%" (
    del /f /q "%LNK%"
    echo [USPJESNO] Automatsko pokretanje sa Windowsima je UKLONJENO.
) else (
    echo [INFO] Servis nije bio postavljen u Startup mapi.
)

echo ========================================================
echo.
pause
