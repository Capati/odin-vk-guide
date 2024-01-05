#!/bin/bash

# Set the path to Vulkan SDK
# VULKAN_SDK="/path/to/your/vulkan/sdk"

# Iterate over files with specified extensions
find . -type f \( -name '*.frag' -o -name '*.vert' -o -name '*.comp' \) -print0 |
while IFS= read -r -d '' file; do
    # Extract file name without extension
    filename=$(basename -- "$file")
    filename_no_ext="${filename%.*}"

    # Run glslangValidator command
    glslangValidator -V "$file" -o "$filename_no_ext.spv"
    # Additional commands for each iteration can be added here
done
