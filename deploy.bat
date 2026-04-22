@echo off
set SRC=%~dp0ExportTune
set DST=%LOCALAPPDATA%\Hondata\FlashPro\Plugins\ExportTune
xcopy /Y /I "%SRC%\*.lua" "%DST%\" >nul
xcopy /Y /I "%SRC%\info.xml" "%DST%\" >nul
echo Deployed to %DST%
