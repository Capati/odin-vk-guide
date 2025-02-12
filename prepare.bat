@echo off
echo Starting preparation...

rem Set error handling
setlocal EnableDelayedExpansion
set "ERROR_OCCURRED=0"

rem Check if .git directory exists
if not exist ".git" (
    echo Error: Not a git repository
    set "ERROR_OCCURRED=1"
    goto :error_handler
)

rem Check git submodules status
echo Checking git submodules...
git submodule status | findstr "^-" > nul
if not errorlevel 1 (
    echo Some submodules are not initialized. Initializing...
    call git submodule update --init --recursive --remote
    if errorlevel 1 (
        echo Error initializing submodules
        set "ERROR_OCCURRED=1"
        goto :error_handler
    )
) else (
    echo Updating submodules...
    call git submodule update --recursive --remote
    if errorlevel 1 (
        echo Error updating submodules
        set "ERROR_OCCURRED=1"
        goto :error_handler
    )
)

rem Build VMA
echo Building VMA...
pushd libs\vma
call build.bat
popd
if errorlevel 1 (
    echo Error occurred while building VMA
    set "ERROR_OCCURRED=1"
    goto :error_handler
)

rem Success handler
:success
if %ERROR_OCCURRED%==0 (
    echo All operations completed successfully.
    exit /b 0
)

rem Error handler
:error_handler
echo Preparation failed.
exit /b 1
