@echo off
cd /d "%~dp0"

echo ========================================================
echo     Pokretanje VoiceStudio Servisa U Pozadini
echo ========================================================
echo.
echo Pokrecem tihi servis (nece biti otvorenog terminal prozora)...
cscript //nologo pokreni_tiho_u_pozadini.vbs

timeout /t 2 /nobreak >nul

echo.
echo Servis je pokrenut u pozadini!
echo - Slusa na portu 3900 (povezano na Cloudflare Tunnel)
echo - Trosi 0%% GPU i minimalno RAM-a dok spava
echo - Automatski pali VoiceStudio engine cim stigne poziv s mobitela
echo.
echo Za provjeru statusa pokrenite: status_servisa.bat
echo Za zaustavljanje servisa pokrenite: zaustavi_tihi_servis.bat
echo ========================================================
echo.
pause
