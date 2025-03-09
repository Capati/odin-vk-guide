@echo off
setlocal enabledelayedexpansion

:: Check if VULKAN_SDK is set
if "%VULKAN_SDK%" == "" (
    echo Error: VULKAN_SDK environment variable is not set
    exit /b 1
)

:: Check if dxc exists
if not exist "%VULKAN_SDK%\Bin\dxc.exe" (
    echo Error: dxc.exe not found in %VULKAN_SDK%\Bin
    exit /b 1
)

:: Check for watch argument
set "WATCH_MODE=false"
if "%1"=="watch" set "WATCH_MODE=true"

:: Create compiled directory if it doesn't exist
if not exist "..\compiled" mkdir "..\compiled"

:: Initial compilation of all files
echo Compiling all shaders...
set "count=0"
set "errors=0"

for /r %%i in (*.hlsl) do (
    set "shader_type=vs_6_1"
    set "filename=%%~nxi"

    :: Determine shader type based on filename prefix before .hlsl
    for %%F in ("!filename:.hlsl=!") do (
        if /i "%%~xF"==".comp" set "shader_type=cs_6_1"
        if /i "%%~xF"==".frag" set "shader_type=ps_6_1"
        if /i "%%~xF"==".vert" set "shader_type=vs_6_1"
        if /i "%%~xF"==".geom" set "shader_type=gs_6_1"
    )

    echo Compiling: %%~nxi [!shader_type!]
    call "%VULKAN_SDK%\Bin\dxc.exe" -spirv -T !shader_type! -E main "%%i" -Fo "..\compiled\%%~ni.spv"
    if !errorlevel! neq 0 (
        echo Failed to compile %%~nxi
        set /a "errors+=1"
    ) else (
        echo Successfully compiled %%~nxi
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
if not "!WATCH_MODE!"=="true" exit /b 0

:: Watch mode starts here
echo Starting shader watch...
echo Press Ctrl+C to stop watching

:: Create hash file directory if it doesn't exist
set "hash_dir=%TEMP%\shader_watch"
if not exist "!hash_dir!" mkdir "!hash_dir!"

:: Store initial state of each file
for /r %%i in (*.hlsl) do (
    echo %%~zi%%~ti>"!hash_dir!\%%~ni.hash"
)

:watch_loop
set "changes=0"

:: Check each file for changes
for /r %%i in (*.hlsl) do (
    set "current_hash=%%~zi%%~ti"
    set "filename=%%~nxi"

    if exist "!hash_dir!\%%~ni.hash" (
        set /p stored_hash=<"!hash_dir!\%%~ni.hash"
    ) else (
        set "stored_hash="
    )

    if not "!current_hash!"=="!stored_hash!" (
        echo Change detected in: %%~nxi

        set "shader_type=vs_6_1"
        :: Determine shader type based on filename prefix before .hlsl
        for %%F in ("!filename:.hlsl=!") do (
            if /i "%%~xF"==".comp" set "shader_type=cs_6_1"
            if /i "%%~xF"==".frag" set "shader_type=ps_6_1"
            if /i "%%~xF"==".vert" set "shader_type=vs_6_1"
            if /i "%%~xF"==".geom" set "shader_type=gs_6_1"
        )

        echo Compiling: %%~nxi [!shader_type!]
        call "%VULKAN_SDK%\Bin\dxc.exe" -spirv -T !shader_type! -E main "%%i" -Fo "..\compiled\%%~ni.spv"
        if !errorlevel! neq 0 (
            echo Failed to compile %%~nxi
        ) else (
            echo Successfully compiled %%~nxi
        )
        echo !current_hash!>"!hash_dir!\%%~ni.hash"
        set "changes=1"
    )
)

if !changes! equ 0 (
    timeout /t 1 /nobreak >nul
)
goto watch_loop

endlocal
