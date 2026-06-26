@echo off
echo [AUTO-PUSH] Surveillance du dossier en cours... (Ctrl+C pour arreter)
echo.

:loop
timeout /t 10 /nobreak >nul
cd /d "C:\Users\Asus Tuf F15\Claude\Projects\pixel web design agency\new-pizza-reims"
git add -A >nul 2>&1
git diff --cached --quiet
if %errorlevel% neq 0 (
    for /f "tokens=1-5 delims=/:. " %%a in ("%date% %time%") do set dt=%%a-%%b-%%c %%d:%%e
    git commit -m "auto-update %dt%" >nul 2>&1
    git push origin main >nul 2>&1
    echo [%time%] Push effectue !
)
goto loop
