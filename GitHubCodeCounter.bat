@echo off
setlocal
cd /d "%~dp0"
title GitHubCodeCounter v0.0.4

chcp 65001 >nul 2>&1

echo.
echo ================================================================================
echo  Starting GitHubCodeCounter v0.0.4
echo  cloc is checked automatically and installed with winget when missing.
echo ================================================================================
echo.

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0GitHubCodeCounter.ps1"
set "EXITCODE=%ERRORLEVEL%"

echo.
echo ================================================================================
if "%EXITCODE%"=="0" (
    echo  Finished successfully.
) else if "%EXITCODE%"=="2" (
    echo  Finished with warnings. Review the messages above.
) else (
    echo  FAILED. Exit code: %EXITCODE%
    echo  Check logs\latest_error.log if it was created.
)
echo ================================================================================
echo.
pause

exit /b %EXITCODE%
