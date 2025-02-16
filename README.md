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
  - [Prerequisites](#prerequisites)
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

Before building an example, you need to build some libraries.

### Prerequisites

- [Git](http://git-scm.com/downloads)
- [Python](https://www.python.org/downloads/) - version 3.x is required
- C++ compiler - `MSVC` on Windows or `g++` on Unix

### Windows

1. Open a Command Prompt and navigate to the project directory

2. Rn the `prepare.bat` script to build the required libraries:

    ```batch
    prepare.bat
    ```

3. To run an example, use the build script:

    ```batch
    build.bat src\01_initializing_vulkan run
    ```

### Unix Systems (Linux/macOS)

1. Open a terminal and navigate to the project directory

2. Make the scripts `prepare.sh` and `build.sh` executable (if needed):

    ```bash
    chmod +x ./prepare.sh
    chmod +x ./build.sh
    ```

3. Rn the `prepare.sh` script to build the required libraries:

    ```batch
    ./prepare.sh
    ```

4. To run an example, use the build script:

    ```bash
    ./build.sh src/01_initializing_vulkan run
    ```

## Dependencies

- [odin-imgui](https://gitlab.com/L-4/odin-imgui/-/tree/main?ref_type=heads)
- [odin-vk-bootstrap](https://github.com/Capati/odin-vk-bootstrap)
- [odin-vma](https://github.com/Capati/odin-vma)
