@echo off
chcp 65001 > nul
set FLUTTER_ROOT=C:\Users\Sterling\fvm\versions\3.41.9
set CARGO_HOME=C:\Users\Sterling\.cargo
set RUSTUP_HOME=C:\Users\Sterling\.rustup
rem VS 18 (2026) bundled CMake 4.3.1; the standalone C:\Program Files\CMake (3.27) is too
rem old to know the "Visual Studio 18 2026" generator and breaks the HEIC build script.
set VS_CMAKE=C:\Program Files\Microsoft Visual Studio\18\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin
set PATH=%VS_CMAKE%;%FLUTTER_ROOT%\bin;%CARGO_HOME%\bin;%PATH%
cd /d "D:\localsend\src\app\windows"
call "%FLUTTER_ROOT%\bin\flutter.bat" run -d windows

pause