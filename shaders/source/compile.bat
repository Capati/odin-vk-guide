@echo off
setLocal enableDelayedExpansion

:: First check if slangc is already in PATH
where slangc.exe >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    set "COMPILER=slangc.exe"
    goto :continue
)

:: If not in PATH, check VULKAN_SDK
if "%VULKAN_SDK%" == "" (
    echo Error: slangc.exe not found in PATH and VULKAN_SDK environment variable is not set
    exit /b 1
)

set "COMPILER=%VULKAN_SDK%\Bin\slangc.exe"

:: Check if slangc exists in Vulkan SDK
if not exist "%COMPILER%" (
    echo Error: slangc.exe not found in PATH or in %VULKAN_SDK%\Bin
    exit /b 1
)

:continue

:: Check for watch argument
set "watch_mode=false"
if "%1"=="watch" set "watch_mode=true"

:: Initial compilation of all files
echo Compiling all shaders...
set "count=0"
set "errors=0"

set "COMMON_ARGS=-entry main -profile glsl_450 -target spirv"

for /r %%i in (*.slang) do (
    :: Extract just the filename without path for easier pattern matching
    set "filename=%%~ni"

    :: Skip files that start with inc_
    echo !filename! | findstr /b "inc_" > nul
    if !errorlevel! neq 0 (
        echo Compiling: %%~nxi
        call %COMPILER% "%%i" %COMMON_ARGS% -o "..\compiled\%%~ni.spv"
        if !errorlevel! neq 0 (
            echo Failed to compile %%~nxi
            set /a "errors+=1"
        ) else (
            set /a "count+=1"
        )
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
for /r %%i in (*.slang) do (
    echo %%~zi%%~ti>"%hash_dir%\%%~ni%%~xi.hash"
)

:watch_loop
set "changes=0"

:: Check each file for changes
for /r %%i in (*.slang) do (
    :: Extract just the filename without path
    set "filename=%%~ni"

    :: Skip files that start with inc_
    echo !filename! | findstr /b "inc_" > nul
    if !errorlevel! neq 0 (
        set "current_hash=%%~zi%%~ti"
        set /p stored_hash=<"%hash_dir%\%%~ni%%~xi.hash" 2>nul || set "stored_hash="

        if not "!current_hash!"=="!stored_hash!" (
            echo Change detected in: %%~nxi
            echo Compiling: %%~nxi
            call %COMPILER% "%%i" %COMMON_ARGS% -o "..\compiled\%%~ni.spv"
            if !errorlevel! neq 0 (
                echo Failed to compile %%~nxi
            ) else (
                echo Successfully compiled %%~nxi
            )
            echo !current_hash!>"%hash_dir%\%%~ni%%~xi.hash"
            set "changes=1"
        )
    )
)

if !changes! equ 0 (
    timeout /t 1 /nobreak >nul
)
goto watch_loop

endLocal
