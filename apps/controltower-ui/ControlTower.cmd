@echo off
setlocal
set "ROOT=C:\AI_ControlTower"
set "APP=%ROOT%\apps\controltower-ui"
set "VENV=%APP%\.venv"

if not exist "%VENV%\Scripts\python.exe" (
  py -3 -m venv "%VENV%"
  if errorlevel 1 python -m venv "%VENV%"
)

"%VENV%\Scripts\python.exe" -m pip install --upgrade pip >nul
"%VENV%\Scripts\python.exe" -m pip install -r "%APP%\requirements.txt"

"%VENV%\Scripts\python.exe" "%APP%\app.py" --project-path "%ROOT%"
