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

# Set the maximum number of parallel worker processes to use
MAX_WORKERS=$(nproc || echo 4)  # Use number of CPU cores, fallback to 4

# Common compilation arguments
COMMON_ARGS="-entry main -profile glsl_450 -target spirv"

# Check for watch argument
WATCH_MODE=false
if [ "$1" = "watch" ]; then
    WATCH_MODE=true
fi

# Create compiled directory if it doesn't exist
mkdir -p ../compiled

should_skip_file() {
    local file="$1"
	local filename=$(basename "$file")
	local basename="${filename%.*}"
	# Skip files that start with inc_
	if [[ "$basename" == inc_* ]]; then
		return 0
	fi
	return 1
}

# Function to compile a single shader file
compile_shader() {
    local file="$1"

	if should_skip_file "$file"; then
		return 0
	fi

    echo "Compiling: $file"
    "$COMPILER" "$file" $COMMON_ARGS -o "../compiled/$basename.spv"
    return $?
}

# Function to perform initial compilation of all shaders using workers
compile_all_shaders_parallel() {
    local shader_files=("$@")  # Accept shader files as arguments
    echo "Compiling ${#shader_files[@]} shaders using $MAX_WORKERS workers..."

    local total_files=${#shader_files[@]}
    local successful=0
    local failed=0
    local active_workers=0
    declare -A jobs  # Use an associative array to track PIDs and their indices

    for file in "${shader_files[@]}"; do
        # Wait if we've reached maximum worker count
        while [ $active_workers -ge $MAX_WORKERS ]; do
            for pid in "${!jobs[@]}"; do
                if ! kill -0 "$pid" 2>/dev/null; then
                    wait "$pid"
                    result=$?
                    ((result == 0 ? successful++ : failed++))
                    unset jobs["$pid"]
                    ((active_workers--))
                fi
            done
            sleep 0.1
        done

        # Start a new worker
        compile_shader "$file" &
        pid=$!
        jobs["$pid"]=1
        ((active_workers++))
    done

    # Wait for remaining workers to finish
    for pid in "${!jobs[@]}"; do
        wait "$pid"
        result=$?
        ((result == 0 ? successful++ : failed++))
        unset jobs["$pid"]
        ((active_workers--))
    done

    echo "Compilation complete:"
    echo "Successfully compiled: $successful files"
    if [ $failed -gt 0 ]; then
        echo "Failed to compile: $failed files"
        return 1
    fi

    return 0
}

shader_files=()
while IFS= read -r -d '' file; do
    if ! should_skip_file "$file"; then
        shader_files+=("$file")
    fi
done < <(find . -type f -name "*.slang" -print0)

# Initial compilation of all files using workers
compile_all_shaders_parallel "${shader_files[@]}"
initial_compile_status=$?

# If not in watch mode, exit here
if [ "$WATCH_MODE" != "true" ]; then
    exit $initial_compile_status
fi

# Watch mode starts here
echo "Starting shader watch..."
echo "Press Ctrl+C to stop watching"

# Create hash file directory if it doesn't exist
hash_dir="/tmp/shader_watch"
mkdir -p "$hash_dir"

# Store initial state of each file
while IFS= read -r -d '' file; do
	# Skip files that start with inc_
	if should_skip_file "$file"; then
		continue
	fi
    stat -c "%s%Y" "$file" > "$hash_dir/$file.hash"
done < <(find . -type f -name "*.slang" -print0)

# Watch loop
while true; do
    changes=0

    while IFS= read -r -d '' file; do
        # Skip files that start with inc_
		if should_skip_file "$file"; then
			continue
		fi

        current_hash=$(stat -c "%s%Y" "$file")
        stored_hash=$(cat "$hash_dir/$file.hash" 2>/dev/null || echo "")

        if [ "$current_hash" != "$stored_hash" ]; then
            echo "Change detected in: $file"
            echo "Compiling: $file"

            "$COMPILER" "$file" $COMMON_ARGS -o "../compiled/$file.spv"

            if [ $? -ne 0 ]; then
                echo "Failed to compile $file"
            else
                echo "Successfully compiled $file"
            fi

            echo "$current_hash" > "$hash_dir/$file.hash"
            changes=1
        fi
    done < <(find . -type f -name "*.slang" -print0)

    if [ $changes -eq 0 ]; then
        sleep 1
    fi
done
