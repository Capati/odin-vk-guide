# Odin Vulkan Guide Tutorial 2.0

In progress tutorial of [vkguide.dev](https://vkguide.dev/) using Odin Language.

## Table of Contents

- [Progress](#progress)
  - [1. Initializing Vulkan](#1-initializing-vulkan)
  - [2. Drawing with Compute](#2-drawing-with-compute)
  - [3. Graphics Pipelines](#3-graphics-pipelines)
  - [4. Textures and Engine Architecture](#4-textures-and-engine-architecture)
  - [5. GLTF loading](#5-gltf-loading)
- [Building](#building)
  - [Windows](#windows)
  - [Unix Systems (Linux/macOS)](#unix-systems-linuxmacos)
- [Dependencies](#dependencies)

## Progress

### 1. Initializing Vulkan

- [x] Vulkan Initialization
- [x] Vulkan Initialization Code
- [x] Executing Vulkan Commands
- [x] Setting up Vulkan commands
- [x] Rendering Loop
- [x] Mainloop Code

![image info](./docs/section-1.jpg)

### 2. Drawing with Compute

- [x] Improving the render loop
- [x] Vulkan Shaders
- [x] Vulkan Shaders - Code
- [x] Setting up IMGUI
- [x] Push Constants and new shaders

![image info](./docs/section-2.jpg)

### 3. Graphics Pipelines

- [ ] The graphics pipeline
- [ ] Setting up render pipeline
- [ ] Mesh buffers
- [ ] Mesh Loading
- [ ] Blending
- [ ] Window Resizing

### 4. Textures and Engine Architecture

- [ ] Descriptor Abstractions
- [ ] Textures
- [ ] Engine Architecture
- [ ] Setting up Materials
- [ ] Meshes and Camera

### 5. GLTF loading

- [ ] Interactive Camera
- [ ] GLTF Scene Nodes
- [ ] GLTF Textures
- [ ] Faster Draw

## Building

### Windows

1. Open a Command Prompt
2. Navigate to the project directory
3. Run the build script:

```batch
build.bat src\01_initializing_vulkan run
```

### Unix Systems (Linux/macOS)

1. Open a terminal
2. Navigate to the project directory
3. Make the script executable (if needed):

    ```bash
    chmod +x build.sh
    ```

4. Run the build script:

    ```bash
    ./build.sh src/01_initializing_vulkan run
    ```

Note: Make sure you have the Odin compiler installed and properly configured in
your system PATH.

## Dependencies

- [odin-imgui](https://gitlab.com/L-4/odin-imgui/-/tree/main?ref_type=heads)
- [odin-vk-bootstrap](https://github.com/Capati/odin-vk-bootstrap)
- [odin-vma](https://github.com/Capati/odin-vma)
