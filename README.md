# Odin Vulkan Guide Tutorial

This repository contains the tutorial code and website for [odin-vk-guide][], an Odin language
adaptation of the popular [vkguide.dev][] Vulkan tutorial. Full credit for the original content
goes to the authors of vkguide.dev.

## Table of Contents

- [Progress](#progress)
  - [0. Project Setup](#0-project-setup)
  - [1. Initializing Vulkan](#1-initializing-vulkan)
  - [2. Drawing with Compute](#2-drawing-with-compute)
  - [3. Graphics Pipelines](#3-graphics-pipelines)
  - [4. Textures and Engine Architecture](#4-textures-and-engine-architecture)
  - [5. GLTF loading](#5-gltf-loading)
  - [6. GPU Driven Rendering](#6-gpu-driven-rendering)
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

### 3. Graphics Pipelines

We have already drawn with compute shaders, but in this chapter, we will use the real
capabilities of a GPU to draw meshes using the rasterizer systems and the normal graphics
pipeline.

- [ ] The graphics pipeline
- [ ] Setting up render pipeline
- [ ] Mesh buffers
- [ ] Mesh Loading
- [ ] Blending
- [ ] Window Resizing

### 4. Textures and Engine Architecture

We are able to draw meshes now, but there are still some things that need doing. This chapter
sets up image loading from files to use in shaders, and sets up a rendering architecture that
is fast and extensible.

- [ ] Descriptor Abstractions
- [ ] Textures
- [ ] Engine Architecture
- [ ] Setting up Materials
- [ ] Meshes and Camera

### 5. GLTF loading

With the basics of the engine done, this chapter focuses on loading GLTF files and setting up
more advanced rendering features.

- [ ] Interactive Camera
- [ ] GLTF Scene Nodes
- [ ] GLTF Textures
- [ ] Faster Draw

### 6. GPU Driven Rendering

In this chapter, we are going to continue the evolution of the engine after the 5 core chapters
by implementing high performance rendering techniques.

- [ ] GPU Driven Rendering Overview
- [ ] Engine architecture overview
- [ ] Draw Indirect
- [ ] Compute Shaders
- [ ] Material System
- [ ] Mesh Rendering
- [ ] Compute based Culling

## License

MIT License, the same from [vkguide.dev][].

[odin-vk-guide]: https://capati.github.io/odin-vk-guide/
[vkguide.dev]: https://vkguide.dev/
