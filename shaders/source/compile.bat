@echo off
setlocal enabledelayedexpansion

:: Check if VULKAN_SDK is set
if "%VULKAN_SDK%" == "" (
    echo Error: VULKAN_SDK environment variable is not set
    exit /b 1
)

:: Check if glslc exists
if not exist "%VULKAN_SDK%\Bin\glslc.exe" (
    echo Error: glslc.exe not found in %VULKAN_SDK%\Bin
    exit /b 1
)

:: Check for watch argument
set "watch_mode=false"
if "%1"=="watch" set "watch_mode=true"

:: Initial compilation of all files
echo Compiling all shaders...
set "count=0"
set "errors=0"

for /r %%i in (*.frag *.vert *.comp) do (
    echo Compiling: %%~nxi
    %VULKAN_SDK%\Bin\glslc.exe "%%i" -o "..\compiled\%%~ni%%~xi.spv"
    if !errorlevel! neq 0 (
        echo Failed to compile %%~nxi
        set /a "errors+=1"
    ) else (
        set /a "count+=1"
    )
)

echo Compilation complete:
echo Successfully compiled: !count! files
if !errors! gtr 0 (
    echo Failed to compile: !errors! files
    exit /b 1
)

:: If not in watch mode, exit here
if not "!watch_mode!"=="true" exit /b 0

:: Watch mode starts here
echo Starting shader watch...
echo Press Ctrl+C to stop watching

:: Create hash file directory if it doesn't exist
set "hash_dir=%TEMP%\shader_watch"
if not exist "%hash_dir%" mkdir "%hash_dir%"

:: Store initial state of each file
for /r %%i in (*.frag *.vert *.comp) do (
    echo %%~zi%%~ti>"%hash_dir%\%%~ni%%~xi.hash"
)

:watch_loop
set "changes=0"

:: Check each file for changes
for /r %%i in (*.frag *.vert *.comp) do (
    set "current_hash=%%~zi%%~ti"
    set /p stored_hash=<"%hash_dir%\%%~ni%%~xi.hash"

    if not "!current_hash!"=="!stored_hash!" (
        echo Change detected in: %%~nxi
        echo Compiling: %%~nxi
        %VULKAN_SDK%\Bin\glslc.exe "%%i" -o "..\compiled\%%~ni%%~xi.spv"
        if !errorlevel! neq 0 (
            echo Failed to compile %%~nxi
        ) else (
            echo Successfully compiled %%~nxi
        )
        echo !current_hash!>"%hash_dir%\%%~ni%%~xi.hash"
        set "changes=1"
    )
)

if !changes! equ 0 (
    timeout /t 1 /nobreak >nul
)
goto watch_loop

endlocal
