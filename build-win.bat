@echo off

set "OUTPUT_DIR=build"
set "EXECUTABLE_NAME=engine_debug.exe"

set "type=%~1"
if "%type%"=="" set type=build

if not exist %OUTPUT_DIR% mkdir %OUTPUT_DIR%

odin build .\src ^
	-debug ^
	-vet ^
    -strict-style ^
	-o:none ^
	-max-error-count:1 ^
	-use-separate-modules ^
	-out:%OUTPUT_DIR%/%EXECUTABLE_NAME%

set compiler_error_code=%errorlevel%

if %compiler_error_code% neq 0 (
	echo Failed to compile!
	exit 1
)

echo Compiled successfully!

if "%type%"=="run" (
	cd %OUTPUT_DIR%
	.\%EXECUTABLE_NAME%
)
