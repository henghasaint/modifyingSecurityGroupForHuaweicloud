@echo off
setlocal enabledelayedexpansion

REM Set code page to UTF-8 to support log output
chcp 65001

REM Change to the directory where this script is located
cd /d "%~dp0"

REM Create logs directory if it does not exist
if not exist "logs\" mkdir logs

REM Generate timestamp for log filename (YYYYMMDD_HHMMSS) using PowerShell (more reliable on Windows 11)
for /f "delims=" %%a in ('powershell -Command "Get-Date -Format yyyyMMdd_HHmmss"') do set "datetime=%%a"
set "logfile=logs\execution_!datetime!.log"

echo Running program... Log file: !logfile!

REM Execute program and log output
echo [Start Time] !date! !time! >> "!logfile!"
modifyingSecurityGroupForHuaweicloud.exe --minRequiredIPs 1 --maxRequiredIPs 2 >> "!logfile!" 2>&1
echo [End Time] !date! !time! >> "!logfile!"

echo Execution completed. Please check log file: !logfile!
pause