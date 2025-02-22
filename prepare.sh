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
source ./build.sh 3 || {
    echo "Error occurred while building VMA"
    popd
    exit 1
}
popd

# Build ImGui
echo "Building ImGui..."
pushd libs/imgui || exit 1
source ./build.sh glfw vulkan || {
    echo "Error occurred while building ImGui"
    popd
    exit 1
}
popd

echo "All operations completed successfully."
