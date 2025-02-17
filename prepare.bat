@echo off
setlocal EnableDelayedExpansion

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

:: Set versions
set IMGUI_VERSION=v1.91.1-docking
set DEAR_BINDINGS_VERSION=81c906b
set GLFW_VERSION=3.4

:: Set directories
set BUILD_DIR=".\libs\imgui\temp"
if not exist "%BUILD_DIR%" mkdir "%BUILD_DIR%"

pushd %BUILD_DIR%

set IMGUI_DIR=.\imgui
set IMGUI_BACKENDS_DIR="%IMGUI_DIR%\backends"
set DEAR_BINDINGS_DIR=.\dear_bindings
set GLFW_DIR=.\glfw

set VENV_DIR=.\venv
if not exist "%VENV_DIR%" mkdir "%VENV_DIR%"

set GENERATED_DIR=.\generated
if exist %GENERATED_DIR% (
    rmdir /s /q %GENERATED_DIR%
)

set GENERATED_BACKENDS_DIR="%GENERATED_DIR%\backends"

mkdir %GENERATED_DIR%
mkdir %GENERATED_BACKENDS_DIR%

if not exist %IMGUI_DIR% (
    echo Cloning ImGui %IMGUI_VERSION%...
    git clone https://github.com/ocornut/imgui.git %IMGUI_DIR% || goto fail
	pushd %IMGUI_DIR%
    git checkout %IMGUI_VERSION% >nul 2>&1 || goto fail
	popd
)

if not exist %DEAR_BINDINGS_DIR% (
    echo Cloning Dear_Bindings %DEAR_BINDINGS_VERSION%...
    git clone https://github.com/dearimgui/dear_bindings.git %DEAR_BINDINGS_DIR% || goto fail
	pushd %DEAR_BINDINGS_DIR%
    git checkout %DEAR_BINDINGS_VERSION% >nul 2>&1 || goto fail
	popd
)

if not exist %GLFW_DIR% (
    echo Cloning GLFW %GLFW_VERSION%...
    git clone https://github.com/glfw/glfw.git %GLFW_DIR% || goto fail
	pushd %GLFW_DIR%
    git checkout %GLFW_VERSION% >nul 2>&1 || goto fail
	popd
)

:: Setup Python virtual environment
echo Setting up Python virtual environment...
python -m venv "%VENV_DIR%"
call "%VENV_DIR%\Scripts\activate.bat"
pip install -r "%DEAR_BINDINGS_DIR%\requirements.txt"

set DEAR_BINDINGS_CMD="%DEAR_BINDINGS_DIR%\dear_bindings.py"

echo Processing imgui.h
python %DEAR_BINDINGS_CMD% ^
	--nogeneratedefaultargfunctions ^
	-o %GENERATED_DIR%\dcimgui %IMGUI_DIR%\imgui.h
if errorlevel 1 goto fail

echo Processing imgui_internal.h
python %DEAR_BINDINGS_CMD% ^
	--nogeneratedefaultargfunctions ^
	-o %GENERATED_DIR%\dcimgui_internal ^
	--include %IMGUI_DIR%\imgui.h %IMGUI_DIR%\imgui_internal.h
if errorlevel 1 goto fail

:: Process backends
for %%n in (
	glfw
	vulkan
) do (
	echo Processing %%n backend
	python %DEAR_BINDINGS_CMD% ^
		--nogeneratedefaultargfunctions ^
		--backend ^
		--include %IMGUI_DIR%\imgui.h ^
		--imconfig-path %IMGUI_DIR%\imconfig.h ^
		-o %GENERATED_BACKENDS_DIR%\cimgui_impl_%%n %IMGUI_BACKENDS_DIR%\imgui_impl_%%n.h
	if errorlevel 1 goto fail
)

set OS_NAME=windows
set ARCH_NAME=x64
set LIB_EXTENSION=lib

if "%PROCESSOR_ARCHITECTURE%"=="ARM64" (
    set ARCH_NAME=arm64
)

set IMGUI_SOURCES=
for %%F in ("%IMGUI_DIR%\*.cpp") do (
    set IMGUI_SOURCES=!IMGUI_SOURCES! "%%F"
)

for %%F in ("%GENERATED_DIR%\*.cpp") do (
    set IMGUI_SOURCES=!IMGUI_SOURCES! "%%F"
)

for %%F in ("%GENERATED_BACKENDS_DIR%\*.cpp") do (
    set IMGUI_SOURCES=!IMGUI_SOURCES! "%%F"
)

set IMGUI_SOURCES=!IMGUI_SOURCES! "%IMGUI_BACKENDS_DIR%\imgui_impl_glfw.cpp"
set IMGUI_SOURCES=!IMGUI_SOURCES! "%IMGUI_BACKENDS_DIR%\imgui_impl_vulkan.cpp"

:: Remove existing build artifacts
del /Q *.obj

:: Compile with MSVC
cl /c /MT /EHsc /O2 ^
	/I"%IMGUI_DIR%" ^
	/I"%GENERATED_DIR%" ^
	/I"%IMGUI_BACKENDS_DIR%" ^
	/I"%GENERATED_BACKENDS_DIR%" ^
	/I"%VULKAN_SDK%\Include" ^
	/I"%GLFW_DIR%\include" ^
	/D"IMGUI_IMPL_API=extern \"C\"" ^
	/DVK_NO_PROTOTYPES ^
	%IMGUI_SOURCES%
if errorlevel 1 goto fail

:: Create static library
lib /OUT:"..\imgui_%OS_NAME%_%ARCH_NAME%.%LIB_EXTENSION%" *.obj
if errorlevel 1 goto fail

popd

echo All operations completed successfully.
goto end

:: Error handler
:fail
echo Preparation failed.
exit /b 1
:end
