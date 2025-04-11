#!/bin/bash

# First check if slangc is already in PATH
if command -v slangc &> /dev/null; then
    COMPILER="slangc"
else
    # If not in PATH, check VULKAN_SDK
    if [ -z "$VULKAN_SDK" ]; then
        echo "Error: slangc not found in PATH and VULKAN_SDK environment variable is not set"
        exit 1
    fi

    COMPILER="$VULKAN_SDK/bin/slangc"

    # Check if slangc exists in Vulkan SDK
    if [ ! -f "$COMPILER" ]; then
        echo "Error: slangc not found in PATH or in $VULKAN_SDK/bin"
        exit 1
    fi
fi

# Check for watch argument
WATCH_MODE=false
if [ "$1" = "watch" ]; then
    WATCH_MODE=true
fi

# Create compiled directory if it doesn't exist
mkdir -p ../compiled

# Initial compilation of all files
echo "Compiling all shaders..."
count=0
errors=0

COMMON_ARGS="-entry main -profile glsl_450 -target spirv"

while IFS= read -r -d '' file; do
    filename=$(basename "$file")
    basename="${filename%.*}"

    # Skip files that start with inc_
    if [[ "$basename" == inc_* ]]; then
        continue
    fi

    echo "Compiling: $filename"

    "$COMPILER" "$file" $COMMON_ARGS -o "../compiled/$filename.spv"

    if [ $? -ne 0 ]; then
        echo "Failed to compile $filename"
        ((errors++))
    else
        ((count++))
    fi
done < <(find . -type f -name "*.slang" -print0)

echo "Compilation complete:"
echo "Successfully compiled: $count files"
if [ $errors -gt 0 ]; then
    echo "Failed to compile: $errors files"
    exit 1
fi

# If not in watch mode, exit here
if [ "$WATCH_MODE" != "true" ]; then
    exit 0
fi

# Watch mode starts here
echo "Starting shader watch..."
echo "Press Ctrl+C to stop watching"

# Create hash file directory if it doesn't exist
hash_dir="/tmp/shader_watch"
mkdir -p "$hash_dir"

# Store initial state of each file
while IFS= read -r -d '' file; do
    filename=$(basename "$file")
    basename="${filename%.*}"

    # Skip files that start with inc_
    if [[ "$basename" == inc_* ]]; then
        continue
    fi

    stat -c "%s%Y" "$file" > "$hash_dir/$filename.hash"
done < <(find . -type f -name "*.slang" -print0)

# Watch loop
while true; do
    changes=0

    while IFS= read -r -d '' file; do
        filename=$(basename "$file")
        basename="${filename%.*}"

        # Skip files that start with inc_
        if [[ "$basename" == inc_* ]]; then
            continue
        fi

        current_hash=$(stat -c "%s%Y" "$file")
        stored_hash=$(cat "$hash_dir/$filename.hash" 2>/dev/null || echo "")

        if [ "$current_hash" != "$stored_hash" ]; then
            echo "Change detected in: $filename"
            echo "Compiling: $filename"

            "$COMPILER" "$file" $COMMON_ARGS -o "../compiled/$filename.spv"

            if [ $? -ne 0 ]; then
                echo "Failed to compile $filename"
            else
                echo "Successfully compiled $filename"
            fi

            echo "$current_hash" > "$hash_dir/$filename.hash"
            changes=1
        fi
    done < <(find . -type f -name "*.slang" -print0)

    if [ $changes -eq 0 ]; then
        sleep 1
    fi
done
