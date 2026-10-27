@echo off
title VoiceStudio Tihi Servis (On-Demand Gateway)
cd /d "%~dp0"

echo ========================================================
echo     VoiceStudio Tihi Pozadinski Servis (On-Demand)
echo ========================================================
echo.
echo Ovaj servis slusa na portu 3900 (Cloudflare Tunnel).
echo VoiceStudio engine i modeli se NE ucitavaju odmah (0%% GPU).
echo Pokrenut ce se automatski cim stigne poziv s mobitela!
echo.
echo Za gasenje pritisnite CTRL + C ili zatvorite prozor.
echo ========================================================
echo.

bun scripts/on-demand-gateway.mjs

pause
