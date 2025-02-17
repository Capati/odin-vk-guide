#!/bin/bash

set -e  # Exit on error

echo "Starting preparation..."

# Check if git is available
if ! command -v git &> /dev/null; then
    echo "Error: git is not installed. Please install git and try again."
    exit 1
fi

# Check if .git directory exists
if [ ! -d ".git" ]; then
    echo "Error: Not a git repository"
    exit 1
fi

# Check git submodules status
echo "Checking git submodules..."
if git submodule status | grep '^-' &> /dev/null; then
    echo "Some submodules are not initialized. Initializing..."
    git submodule update --init --recursive --remote || {
        echo "Error initializing submodules"
        exit 1
    }
else
    echo "Updating submodules..."
    git submodule update --recursive --remote || {
        echo "Error updating submodules"
        exit 1
    }
fi

# Check for C++ compiler
if ! command -v g++ &> /dev/null; then
    echo "ERROR: C++ compiler not found"
    exit 1
fi

# Build VMA
echo "Building VMA..."
pushd libs/vma || exit 1
./build.sh || {
    echo "Error occurred while building VMA"
    popd
    exit 1
}
popd

# Build ImGui
echo "Building ImGui..."

# Set versions
IMGUI_VERSION="v1.91.1-docking"
DEAR_BINDINGS_VERSION="81c906b"
GLFW_VERSION="3.4"

# Set directories
BUILD_DIR="./libs/imgui/temp"
mkdir -p "${BUILD_DIR}"

pushd "${BUILD_DIR}" || exit 1

IMGUI_DIR="./imgui"
IMGUI_BACKENDS_DIR="${IMGUI_DIR}/backends"
DEAR_BINDINGS_DIR="./dear_bindings"
GLFW_DIR="./glfw"

VENV_DIR="./venv"
mkdir -p "${VENV_DIR}"

GENERATED_DIR="./generated"
rm -rf "${GENERATED_DIR}"
GENERATED_BACKENDS_DIR="${GENERATED_DIR}/backends"

mkdir -p "${GENERATED_DIR}"
mkdir -p "${GENERATED_BACKENDS_DIR}"

if [ ! -d "${IMGUI_DIR}" ]; then
    echo "Cloning ImGui ${IMGUI_VERSION}..."
    git clone https://github.com/ocornut/imgui.git "${IMGUI_DIR}" || exit 1
    pushd "${IMGUI_DIR}" || exit 1
    git checkout "${IMGUI_VERSION}" > /dev/null 2>&1 || exit 1
    popd || exit 1
fi

if [ ! -d "${DEAR_BINDINGS_DIR}" ]; then
    echo "Cloning Dear_Bindings ${DEAR_BINDINGS_VERSION}..."
    git clone https://github.com/dearimgui/dear_bindings.git "${DEAR_BINDINGS_DIR}" || exit 1
    pushd "${DEAR_BINDINGS_DIR}" || exit 1
    git checkout "${DEAR_BINDINGS_VERSION}" > /dev/null 2>&1 || exit 1
    popd || exit 1
fi

if [ ! -d "${GLFW_DIR}" ]; then
    echo "Cloning GLFW ${GLFW_VERSION}..."
    git clone https://github.com/glfw/glfw.git "${GLFW_DIR}" || exit 1
    pushd "${GLFW_DIR}" || exit 1
    git checkout "${GLFW_VERSION}" > /dev/null 2>&1 || exit 1
    popd || exit 1
fi

# Setup Python virtual environment
echo "Setting up Python virtual environment..."
python3 -m venv "${VENV_DIR}"
source "${VENV_DIR}/bin/activate"
pip install -r "${DEAR_BINDINGS_DIR}/requirements.txt"

DEAR_BINDINGS_CMD="${DEAR_BINDINGS_DIR}/dear_bindings.py"

echo "Processing imgui.h"
python "${DEAR_BINDINGS_CMD}" \
    --nogeneratedefaultargfunctions \
    -o "${GENERATED_DIR}/dcimgui" "${IMGUI_DIR}/imgui.h" || exit 1

echo "Processing imgui_internal.h"
python "${DEAR_BINDINGS_CMD}" \
    --nogeneratedefaultargfunctions \
    -o "${GENERATED_DIR}/dcimgui_internal" \
    --include "${IMGUI_DIR}/imgui.h" "${IMGUI_DIR}/imgui_internal.h" || exit 1

for backend in glfw vulkan; do
    echo "Processing ${backend}"
    python "${DEAR_BINDINGS_CMD}" \
        --nogeneratedefaultargfunctions \
        --backend \
        --include "${IMGUI_DIR}/imgui.h" \
        --imconfig-path "${IMGUI_DIR}/imconfig.h" \
        -o "${GENERATED_BACKENDS_DIR}/cimgui_impl_${backend}" \
        "${IMGUI_BACKENDS_DIR}/imgui_impl_${backend}.h" || exit 1
done

# Determine OS and architecture
OS_NAME=$(uname -s | tr '[:upper:]' '[:lower:]')
ARCH_NAME=$(uname -m)
case "${ARCH_NAME}" in
    x86_64) ARCH_NAME="x64" ;;
    aarch64) ARCH_NAME="arm64" ;;
esac
LIB_EXTENSION="a"  # Static library extension for Unix

# Collect source files
IMGUI_SOURCES=()
while IFS= read -r -d $'\0' file; do
    IMGUI_SOURCES+=("$file")
done < <(find "${IMGUI_DIR}" -maxdepth 1 -name "*.cpp" -print0)

while IFS= read -r -d $'\0' file; do
    IMGUI_SOURCES+=("$file")
done < <(find "${GENERATED_DIR}" "${GENERATED_BACKENDS_DIR}" -maxdepth 1 -name "*.cpp" -print0)

IMGUI_SOURCES+=("${IMGUI_BACKENDS_DIR}/imgui_impl_glfw.cpp")
IMGUI_SOURCES+=("${IMGUI_BACKENDS_DIR}/imgui_impl_vulkan.cpp")

rm -f *.o

# Compile with g++
MAX_JOBS=4
FAILED=0
for source in "${IMGUI_SOURCES[@]}"; do
    echo "Compiling $source"
    g++ -c -O2 -fPIC \
        -I"${IMGUI_DIR}" \
        -I"${GENERATED_DIR}" \
        -I"${IMGUI_BACKENDS_DIR}" \
        -I"${GENERATED_BACKENDS_DIR}" \
        -I"${VULKAN_SDK}/include" \
        -I"${GLFW_DIR}/include" \
        -D'IMGUI_IMPL_API=extern "C"' \
        -D'VK_NO_PROTOTYPES=0' \
        "${source}" || { FAILED=1; break; } &

    # Limit the number of parallel jobs
    if [[ $(jobs -r -p | wc -l) -ge $MAX_JOBS ]]; then
        wait -n || { FAILED=1; break; }
    fi
done

# Wait for all remaining jobs to finish
wait || FAILED=1

# Check if any job failed
if [[ $FAILED -eq 1 ]]; then
    echo "Error: Compilation failed."
    exit 1
fi

# Create static library
ar rcs "../imgui_${OS_NAME}_${ARCH_NAME}.${LIB_EXTENSION}" *.o

popd || exit 1

echo "All operations completed successfully."
