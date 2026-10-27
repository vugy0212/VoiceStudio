@echo off
cd /d "%~dp0"

echo ========================================================
echo     Postavljanje automatskog pokretanja sa Windowsima
echo ========================================================
echo.

powershell -NoProfile -Command "& { $ws = New-Object -ComObject WScript.Shell; $s = $ws.CreateShortcut(\"$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup\VoiceStudio_Tihi_Servis.lnk\"); $s.TargetPath = 'wscript.exe'; $s.Arguments = '\"%~dp0pokreni_tiho_u_pozadini.vbs\"'; $s.WorkingDirectory = '%~dp0'; $s.Description = 'VoiceStudio On-Demand Tihi Servis'; $s.Save(); }"

if %errorlevel% equ 0 (
    echo [USPJESNO] VoiceStudio tihi servis je postavljen za automatsko pokretanje sa Windowsima!
    echo.
    echo Lokacija precaca:
    echo %%APPDATA%%\Microsoft\Windows\Start Menu\Programs\Startup\VoiceStudio_Tihi_Servis.lnk
    echo.
    echo Napomena: Servis trosi 0%% GPU i tek ~15MB RAM-a dok ceka poziv s mobitela.
) else (
    echo [GRESKA] Nije uspjelo kreiranje precaca u Startup mapi.
)

echo.
echo Za ponistavanje pokrenite 'onemoguci_autostart.bat'.
echo ========================================================
echo.
pause
