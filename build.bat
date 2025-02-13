@echo off
setlocal enabledelayedexpansion

:: Set default values
set ARGS=-debug -collection:libs=./libs/
set RELEASE_MODE=false
set BUILD_TARGET=%1
set ERROR_OCCURRED=false
set RUN_AFTER_BUILD=false
set CLEAN_BUILD=false
set ADDITIONAL_ARGS=

:: Check for arguments
set ARG_COUNTER=0
for %%i in (%*) do (
    if !ARG_COUNTER! equ 0 (
        rem Skip the first argument
    ) else (
        if /i "%%i"=="release" (
            set RELEASE_MODE=true
        ) else if /i "%%i"=="run" (
            set RUN_AFTER_BUILD=true
        ) else if /i "%%i"=="clean" (
            set CLEAN_BUILD=true
        ) else (
            set "ADDITIONAL_ARGS=!ADDITIONAL_ARGS! %%i"
        )
    )
    set /a ARG_COUNTER+=1
)

:: Set mode string
if "%RELEASE_MODE%"=="true" (
    set MODE=RELEASE
) else (
    set MODE=DEBUG
)

:: Set build arguments based on mode
if "%RELEASE_MODE%"=="true" (
    set ARGS=-collection:libs=./libs/ ^
		-o:speed ^
        -disable-assert ^
        -no-bounds-check
)

set BUILD_DIR=".\build"

if not exist "%BUILD_DIR%" (
	mkdir "%BUILD_DIR%"
)

set OUT=-out:%BUILD_DIR%

:: Check if a build target was provided
if "%BUILD_TARGET%"=="" (
    echo [BUILD] --- Error: Please provide a folder name to build
    echo [BUILD] --- Usage: build.bat folder_name [release] [run]
    exit /b 1
)

for %%i in ("%BUILD_TARGET:\=" "%") do set TARGET_NAME=%%~ni

:: Clean build if requested
if "%CLEAN_BUILD%"=="true" (
    echo [BUILD] --- Cleaning artifacts...
    if exist "build\*.exe" del /F /Q build\*.exe
    if exist "build\*.pdb" del /F /Q build\*.pdb
)

:: Build the target
echo [BUILD] --- Building '%TARGET_NAME%' in %MODE% mode...
call odin build .\%BUILD_TARGET% %ARGS% %ADDITIONAL_ARGS% %OUT%\%TARGET_NAME%.exe
if errorlevel 1 (
    echo [BUILD] --- Error building '%TARGET_NAME%'
    set ERROR_OCCURRED=true
)

if "%ERROR_OCCURRED%"=="true" (
    echo [BUILD] --- Build process failed.
    exit /b 1
) else (
    echo [BUILD] --- Build process completed successfully.
    if "%RUN_AFTER_BUILD%"=="true" (
		echo [BUILD] --- Running %TARGET_NAME%...
		pushd build
		%TARGET_NAME%.exe
		popd
    )
    exit /b 0
)
