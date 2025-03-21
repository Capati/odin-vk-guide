# Odin Vulkan Guide Tutorial

This repository contains the tutorial code and website for [odin-vk-guide][], an Odin language
adaptation of the popular [vkguide.dev][] Vulkan tutorial. Full credit for the original content
goes to the authors of vkguide.dev.

> [!WARNING]
> This project is a **work in progress**. Until all sections are complete, I may need to
> refactor earlier chapters. If you're reading a chapter that has been affected by changes,
> please revisit previous sections to understand what has been updated.

## Table of Contents

- [Progress](#progress)
  - [0. Project Setup](#0-project-setup)
  - [1. Initializing Vulkan](#1-initializing-vulkan)
  - [2. Drawing with Compute](#2-drawing-with-compute)
  - [3. Graphics Pipelines](#3-graphics-pipelines)
  - [4. Textures and Engine Architecture](#4-textures-and-engine-architecture)
  - [5. Scene Graph (Extra Chapter)](#5-scene-graph-extra-chapter)
  - [6. GLTF loading](#6-gltf-loading)
  - [7. GPU Driven Rendering](#7-gpu-driven-rendering)
- [Contributing](#contributing)
- [License](#license)

## Progress

Here is the progress of each chapter and section in the guide:

### 0. Project Setup

In this chapter, we setup the build toolchain to compile the project.

- [x] Building Project
- [x] Code Walkthrough

### 1. Initializing Vulkan

In this chapter, we are going to start the tutorial code, and configure the initial Vulkan
structures needed to support rendering. We will also be writing the initial render loop,
including command buffer and render image management.

- [x] Vulkan Initialization
- [x] Vulkan Initialization Code
- [x] Executing Vulkan Commands
- [x] Setting up Vulkan commands
- [x] Rendering Loop
- [x] Mainloop Code

### 2. Drawing with Compute

In this chapter, we are going to begin drawing using compute shaders. As part of the chapter,
we will also setup DearImgui library to get some user interface.

- [x] Improving the render loop
- [x] Vulkan Shaders
- [x] Vulkan Shaders - Code
- [x] Setting up IMGUI
- [x] Push Constants and new shaders
- [x] Fixing Input Lag (**Extra section**)

### 3. Graphics Pipelines

We have already drawn with compute shaders, but in this chapter, we will use the real
capabilities of a GPU to draw meshes using the rasterizer systems and the normal graphics
pipeline.

- [x] The graphics pipeline
- [x] Setting up render pipeline
- [x] Mesh buffers
- [x] Mesh Loading
- [x] Blending
- [x] Window Resizing
- [x] Split Engine Logic (**Extra section**)

### 4. Textures and Engine Architecture

We are able to draw meshes now, but there are still some things that need doing. This chapter
sets up image loading from files to use in shaders, and sets up a rendering architecture that
is fast and extensible.

- [x] Descriptor Abstractions
- [x] Textures
- [x] Engine Architecture
- [x] Setting up Materials
- [x] Meshes and Camera

### 5. Scene Graph (Extra Chapter)

- [x] Improving The Scene Graph
- [ ] Render Scene Tree UI
- [ ] Loading and Saving a Scene Graph

### 6. GLTF loading

With the basics of the engine done, this chapter focuses on loading GLTF files and setting up
more advanced rendering features.

- [ ] Interactive Camera
- [ ] GLTF Scene Nodes
- [ ] GLTF Textures
- [ ] Faster Draw

### 7. GPU Driven Rendering

In this chapter, we are going to continue the evolution of the engine after the 5 core chapters
by implementing high performance rendering techniques.

- [ ] GPU Driven Rendering Overview
- [ ] Engine architecture overview
- [ ] Draw Indirect
- [ ] Compute Shaders
- [ ] Material System
- [ ] Mesh Rendering
- [ ] Compute based Culling

## Contributing

Everyone is welcome to contribute to the project. If you find any problems, you can submit them
using [GitHub's issue system](https://github.com/Capati/odin-vk-guide/issues). If you want to
contribute code or the guide, you should fork the project and then send a pull request.

## License

MIT License, the same from [vkguide.dev][].

[odin-vk-guide]: https://capati.github.io/odin-vk-guide/
[vkguide.dev]: https://vkguide.dev/
