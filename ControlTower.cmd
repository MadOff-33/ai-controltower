@echo off
setlocal
set "ROOT=%~dp0"
set "ROOT=%ROOT:~0,-1%"
call "%ROOT%\apps\controltower-ui\ControlTower.cmd"
