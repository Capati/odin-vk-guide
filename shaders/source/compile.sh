#!/bin/bash

# Check if VULKAN_SDK is set
if [ -z "$VULKAN_SDK" ]; then
    echo "Error: VULKAN_SDK environment variable is not set"
    exit 1
fi

# Check if glslc exists
if [ ! -f "$VULKAN_SDK/bin/glslc" ]; then
    echo "Error: glslc not found in $VULKAN_SDK/bin"
    exit 1
fi

# Check for watch argument
watch_mode=false
if [ "$1" = "watch" ]; then
    watch_mode=true
fi

# Function to compile a shader
compile_shader() {
    local shader=$1
    local filename=$(basename "$shader")
    echo "Compiling: $filename"
    "$VULKAN_SDK/bin/glslc" "$shader" -o "${shader%.*}.spv"
    return $?
}

# Initial compilation of all files
echo "Compiling all shaders..."
count=0
errors=0

# Find all shader files and compile them
while IFS= read -r -d '' shader; do
    if compile_shader "$shader"; then
        ((count++))
    else
        ((errors++))
        echo "Failed to compile $(basename "$shader")"
    fi
done < <(find . -type f \( -name "*.frag" -o -name "*.vert" -o -name "*.comp" \) -print0)

echo "Compilation complete:"
echo "Successfully compiled: $count files"
if [ $errors -gt 0 ]; then
    echo "Failed to compile: $errors files"
    exit 1
fi

# If not in watch mode, exit here
if [ "$watch_mode" != "true" ]; then
    exit 0
fi

# Watch mode starts here
echo "Starting shader watch..."
echo "Press Ctrl+C to stop watching"

# Create hash directory in /tmp
hash_dir="/tmp/shader_watch"
mkdir -p "$hash_dir"

# Function to get file hash (modification time + size)
get_file_hash() {
    stat -f "%m%z" "$1" 2>/dev/null || stat -c "%Y%s" "$1" 2>/dev/null
}

# Store initial state of each file
while IFS= read -r -d '' shader; do
    filename=$(basename "$shader")
    get_file_hash "$shader" > "$hash_dir/${filename%.*}.hash"
done < <(find . -type f \( -name "*.frag" -o -name "*.vert" -o -name "*.comp" \) -print0)

# Watch loop
while true; do
    changes=0

    while IFS= read -r -d '' shader; do
        filename=$(basename "$shader")
        current_hash=$(get_file_hash "$shader")
        stored_hash=$(cat "$hash_dir/${filename%.*}.hash" 2>/dev/null)

        if [ "$current_hash" != "$stored_hash" ]; then
            echo "Change detected in: $filename"
            if compile_shader "$shader"; then
                echo "Successfully compiled $filename"
            else
                echo "Failed to compile $filename"
            fi
            echo "$current_hash" > "$hash_dir/${filename%.*}.hash"
            changes=1
        fi
    done < <(find . -type f \( -name "*.frag" -o -name "*.vert" -o -name "*.comp" \) -print0)

    if [ $changes -eq 0 ]; then
        sleep 1
    fi
done
