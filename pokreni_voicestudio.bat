@echo off
title VoiceStudio
cd /d "%~dp0"

echo ===================================================
echo               Pokretanje VoiceStudio
echo ===================================================
echo.

echo [1/3] Oslobadjanje portova (3900, 3901)...
call bun scripts/clear-dev-ports.mjs 3900 3901 5173 >nul 2>&1

echo [2/3] Pokretanje automatskog otvaranja preglednika...
start "" /b cmd /c "timeout /t 6 /nobreak >nul & start http://localhost:3901"

echo [3/3] Pokretanje VoiceStudio servisa...
echo.
echo Za zaustavljanje pritisnite tipke CTRL + C ili zatvorite ovaj prozor.
echo ===================================================
echo.

call bun scripts/dev-runner.mjs

pause
