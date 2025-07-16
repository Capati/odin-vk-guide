#!/bin/bash

# Exit on any error
set -e

# Set default values
ARGS="\
	-vet \
	-debug \
	-vet-cast \
	-vet-style \
	-vet-using-param \
	-strict-style \
	-disallow-do \
	-warnings-as-errors \
	-collection:libs=./libs/"
RELEASE_MODE=false
BUILD_TARGET="$1"
ERROR_OCCURRED=false
RUN_AFTER_BUILD=false
CLEAN_BUILD=false
ADDITIONAL_ARGS=""
MODE="DEBUG"

# Check if a build target was provided
if [ -z "$BUILD_TARGET" ]; then
	echo "[BUILD] --- Error: Please provide a folder name to build"
	echo "[BUILD] --- Usage: $0 folder_name [release] [run]"
	exit 1
fi

# Extract target name (last part of path)
TARGET_NAME=$(basename "$BUILD_TARGET")

# Process remaining arguments (skip first argument)
shift
while [ $# -gt 0 ]; do
	case "$1" in
	release)
		RELEASE_MODE=true
		MODE="RELEASE"
		;;
	run)
		RUN_AFTER_BUILD=true
		;;
	clean)
		CLEAN_BUILD=true
		;;
	*)
		ADDITIONAL_ARGS="$ADDITIONAL_ARGS $1"
		;;
	esac
	shift
done

# Set build arguments based on mode
if [ "$RELEASE_MODE" = true ]; then
	ARGS="-o:speed \
        -disable-assert \
        -no-bounds-check \
		-collection:libs=./libs/"
fi

BUILD_DIR="./build"

# Check if the build directory exists, create if not
if [ ! -d "$BUILD_DIR" ]; then
	mkdir "$BUILD_DIR"
fi

OUT="-out:$BUILD_DIR"

# Clean build if requested
if [ "$CLEAN_BUILD" = true ]; then
	echo "[BUILD] --- Cleaning artifacts..."
	rm -f build/*.o     # Object files
	rm -f build/*.a     # Static libraries
	rm -f build/*.so    # Shared objects/dynamic libraries
	rm -f build/*.so.*  # Versioned shared objects
	rm -f build/*.dylib # macOS dynamic libraries
	rm -f build/*.out   # Default executable name (a.out)
	rm -f build/*~      # Backup files
	rm -f build/*.dSYM  # macOS debug symbols directory
fi

# Build the target
echo "[BUILD] --- Building '$TARGET_NAME' in $MODE mode..."
if ! odin build "./$BUILD_TARGET" $ARGS $ADDITIONAL_ARGS $OUT/$TARGET_NAME; then
	echo "[BUILD] --- Error building '$TARGET_NAME'"
	ERROR_OCCURRED=true
fi

if [ "$ERROR_OCCURRED" = true ]; then
	echo "[BUILD] --- Build process failed."
	exit 1
else
	echo "[BUILD] --- Build process completed successfully."
	if [ "$RUN_AFTER_BUILD" = true ]; then
		echo "[BUILD] --- Running $TARGET_NAME..."
		(cd build && ./$TARGET_NAME)
	fi
	exit 0
fi
