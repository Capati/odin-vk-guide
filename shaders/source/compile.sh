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

# Create compiled directory if it doesn't exist
mkdir -p ../compiled

# Initial compilation of all files
echo "Compiling all shaders..."
count=0
errors=0

find . -type f \( -name "*.frag" -o -name "*.vert" -o -name "*.comp" \) | while read -r file; do
    filename=$(basename "$file")
    echo "Compiling: $filename"

    "$VULKAN_SDK/bin/glslc" "$file" -o "../compiled/$(basename "$file").spv"

    if [ $? -ne 0 ]; then
        echo "Failed to compile $filename"
        ((errors++))
    else
        ((count++))
    fi
done

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

# Create hash file directory if it doesn't exist
hash_dir="/tmp/shader_watch"
mkdir -p "$hash_dir"

# Store initial state of each file
find . -type f \( -name "*.frag" -o -name "*.vert" -o -name "*.comp" \) | while read -r file; do
    filename=$(basename "$file")
    stat -c "%s%Y" "$file" > "$hash_dir/$filename.hash"
done

# Watch loop
while true; do
    changes=0

    find . -type f \( -name "*.frag" -o -name "*.vert" -o -name "*.comp" \) | while read -r file; do
        filename=$(basename "$file")
        current_hash=$(stat -c "%s%Y" "$file")
        stored_hash=$(cat "$hash_dir/$filename.hash")

        if [ "$current_hash" != "$stored_hash" ]; then
            echo "Change detected in: $filename"
            echo "Compiling: $filename"

            "$VULKAN_SDK/bin/glslc" "$file" -o "../compiled/$filename.spv"

            if [ $? -ne 0 ]; then
                echo "Failed to compile $filename"
            else
                echo "Successfully compiled $filename"
            fi

            echo "$current_hash" > "$hash_dir/$filename.hash"
            changes=1
        fi
    done

    if [ $changes -eq 0 ]; then
        sleep 1
    fi
done
