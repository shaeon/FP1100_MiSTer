@echo off
rem Compila FP1100 para MiSTer con Quartus 17.0 desde linea de comandos
set QUARTUS=C:\altera_lite\17.0\quartus\bin64
"%QUARTUS%\quartus_sh.exe" --flow compile FP1100 -c FP1100
if errorlevel 1 goto :error
for /f %%i in ('powershell -nologo -noprofile -command "Get-Date -Format yyyyMMdd"') do set DT=%%i
copy /y output_files\FP1100.rbf releases\FP1100_%DT%.rbf >nul
echo Hecho: releases\FP1100_%DT%.rbf
goto :eof
:error
echo Error de compilacion
exit /b 1
