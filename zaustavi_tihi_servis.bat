@echo off
cd /d "%~dp0"

echo ========================================================
echo     Zaustavljanje VoiceStudio Tihog Servisa
echo ========================================================
echo.
echo Zaustavljam servis i oslobadjam portove (3900, 3905)...

call bun scripts/clear-dev-ports.mjs 3900 3905 >nul 2>&1

echo Servis i VoiceStudio backend su uspjesno zaustavljeni.
echo Resursi (GPU/RAM) su oslobodjeni.
echo ========================================================
echo.
pause
