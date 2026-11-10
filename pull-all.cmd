@echo off
rem pull-all.cmd - Ad Astra UC3M
rem Double-click to download the latest changes from GitHub for every
rem repository in this folder (and one level of subfolders). It only runs
rem "git pull --ff-only": it never pushes and never touches local changes.
rem Repositories with uncommitted work are skipped and reported.
rem
rem Plain batch on purpose: opens with a double-click on any Windows, with no
rem PowerShell execution policy involved. Keep it ASCII with CRLF line endings.
setlocal EnableExtensions
set "ROOT=%~dp0"
set /a UPDATED=0
set /a SKIPPED=0
set /a FAILED=0

where git >nul 2>nul
if errorlevel 1 (
  echo Git no esta instalado. Ejecuta primero el setup de Ad Astra.
  goto :end
)

for /d %%D in ("%ROOT%*") do (
  if exist "%%D\.git" (
    call :pull "%%D"
  ) else (
    for /d %%S in ("%%D\*") do if exist "%%S\.git" call :pull "%%S"
  )
)

echo.
echo Resumen: %UPDATED% actualizados, %SKIPPED% saltados, %FAILED% con fallo.

:end
if /i not "%~1"=="/nopause" pause
exit /b 0

:pull
echo.
echo == %~nx1
set "DIRTY="
for /f "delims=" %%L in ('git -C "%~1" status --porcelain 2^>nul') do set "DIRTY=1"
if defined DIRTY (
  echo    Saltado: tienes cambios sin commit. Haz commit o descartalos y vuelve a ejecutar.
  set /a SKIPPED+=1
  exit /b 0
)
git -C "%~1" rev-parse --verify --quiet HEAD >nul 2>nul
if errorlevel 1 (
  echo    Repositorio vacio todavia, nada que descargar.
  set /a SKIPPED+=1
  exit /b 0
)
git -C "%~1" pull --ff-only
if errorlevel 1 (
  echo    Fallo: no se pudo actualizar. Rama sin remoto, conflicto o sin conexion.
  set /a FAILED+=1
) else (
  set /a UPDATED+=1
)
exit /b 0
