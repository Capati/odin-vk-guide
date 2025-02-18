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
    - [Configuring ImGui Backends](#configuring-imgui-backends)
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

- [x] The graphics pipeline
- [x] Setting up render pipeline
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

> [!NOTE]
> This project requires some dependencies that are included as Git submodules. Follow the build
> instructions below to set up all required libraries and properly build an example.

### Prerequisites

- [Git](http://git-scm.com/downloads)
- [Python](https://www.python.org/downloads/) - version 3.x is required
- C++ compiler - `MSVC` on Windows or `g++` on Unix

#### Configuring ImGui Backends

The guide uses `SDL2` for windowing and platform, but we are going to use `glfw`. To configure
the ImGui build script to use only the `glfw` and `vulkan` backends, follow these steps:

1. **Locate the Build Script**

   Open the `build.py` file located in the `libs/imgui/` directory.

2. **Find the Backend Configuration**

   Look for the following line in the script:

    ```python
    wanted_backends = ["vulkan", "sdl2", "opengl3", "sdlrenderer2", "glfw", "dx11", "dx12", "win32", "osx", "metal", "wgpu"]
    ```

3. **Modify the Backend List**

    Update the `wanted_backends` list to include only the `glfw` and `vulkan` backends:

    ```python
    wanted_backends = ["vulkan", "glfw"]
    ```

4. **Save and Proceed**

    Save the changes to the `build.py` file.

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
    chmod +x .,/libs/vma/build.sh
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
