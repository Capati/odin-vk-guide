@echo off
setLocal EnableDelayedExpansion

echo Starting preparation...

:: Check if git is available
where git >nul 2>&1 || (
	echo Error: git is not installed or not in PATH. Please install git and try again.
	goto fail
)

:: Check if .git directory exists
if not exist ".git" (
    echo Error: Not a git repository
    goto fail
)

:: Check git submodules status
echo Checking git submodules...
git submodule status | findstr "^-" > nul
if not errorlevel 1 (
    echo Some submodules are not initialized. Initializing...
    call git submodule update --init --recursive --remote
    if errorlevel 1 (
        echo Error initializing submodules
        goto fail
    )
) else (
    echo Updating submodules...
    call git submodule update --recursive --remote
    if errorlevel 1 (
        echo Error updating submodules
        goto fail
    )
)

:: Check for MSVC compiler
where /Q cl.exe || (
	set __VSCMD_ARG_NO_LOGO=1
	for /f "tokens=*" %%i in ('"C:\Program Files (x86)\Microsoft Visual Studio\Installer\vswhere.exe" -latest -requires Microsoft.VisualStudio.Workload.NativeDesktop -property installationPath') do set VS=%%i
	if "!VS!" equ "" (
		echo ERROR: Visual Studio installation not found
		goto fail
	)
	call "!VS!\VC\Auxiliary\Build\vcvarsall.bat" amd64 || goto fail
)

if "%VSCMD_ARG_TGT_ARCH%" neq "x64" (
    if "%ODIN_IGNORE_MSVC_CHECK%" == "" (
        echo ERROR: please run this from MSVC x64 native tools command prompt, ^
			32-bit target is not supported!
        exit /b 1
    )
)

:: Build VMA
echo Building VMA...
pushd libs\vma
call build.bat 3
popd
if errorlevel 1 (
    echo Error occurred while building VMA
    goto fail
)

:: Build ImGui
echo Building ImGui...
pushd libs\imgui
call build.bat glfw vulkan
popd
if errorlevel 1 (
    echo Error occurred while building ImGui
    goto fail
)

echo All operations completed successfully.
goto end

:: Error handler
:fail
echo Preparation failed.
exit /b 1
:end
