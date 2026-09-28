@echo off
chcp 65001 > nul
set FLUTTER_ROOT=C:\Users\Sterling\fvm\versions\3.41.9
set CARGO_HOME=C:\Users\Sterling\.cargo
set RUSTUP_HOME=C:\Users\Sterling\.rustup
set PATH=%FLUTTER_ROOT%\bin;%CARGO_HOME%\bin;%PATH%
cd /d "D:\localsend\src\app\windows"
call "%FLUTTER_ROOT%\bin\flutter.bat" run -d windows
