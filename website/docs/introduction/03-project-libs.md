---
sidebar_position: 3
description: Folder structure and libraries used in the project.
---

# Project layout and Libraries

For the Vulkan engine, we use specific folders and filenames:

````text
├───build
│   ├───assets
├───libs
│   ├───imgui
│   ├───vkb
│   └───vma
├───shaders
├───src
└───tutorial
    ├───01_initializing_vulkan
    ├───02_drawing_with_compute
    ├───03_graphics_pipelines
    ├───04_textures_and_engine_architecture
    └───05_gltf_loading
````

- `build` is where the executables will get built
  - `assets` will contain textures and 3d models that we use over the guide, loaded at runtime
- `libs` contains additional libraries required for the project that are not included in
  `vendor`
- `shaders` will contain all our shader source files and their compiled output. These are not
  placed in `build/assets` because they will be loaded at compile time using `#load`
- `src` you can use this folder as the starting point to follow the tutorial and use the
  `tutorial` folder as a reference
- `tutorial` contain the code for each of the chapters of the guide, all files are in the same
package

## Libraries

On the engine, we use a set of libraries, some are in `vendor`, but other are stored in
`/libs`.

The Libraries we are using:

### Vendor

- [GLFW](https://www.glfw.org/) Windowing and input library. GLFW is a library for creating
  windows, contexts, and managing input, primarily for OpenGL, Vulkan, and other graphics APIs.
  It is widely used in the development of graphics applications and games. We use it in the
  project to easily create a window and handle input across multiple platforms.

  :::tip[GLFW]
  
  Note that the original tutorial uses SDL2, but we have replaced it with GLFW for ease of use.
  
  :::

- [STB Image](https://github.com/nothings/stb) Image loading library. Small and easy to use
  library to load image files. It can load common image formats such as BMP, PNG, JPEG, and
  others.

- [cgltf][] glTF model loader library. Fast and small
  library to load the glTF 3D model format that we will use when loading 3D models.

### External

- [dear IMGUI][] Easy to use immediate Graphical-User-Interface (GUI) library. This allows us
  to create editable widgets such as sliders and windows for the user interface. It's widely
  used in the game industry for debug tools. In the project, we use it to create interactive
  options for rendering.
  - Bindings: [odin-imgui](https://github.com/Capati/odin-imgui)

- [Vk Bootstrap][] Abstracts a big amount of boilerplate that Vulkan has when setting up. Most
  of that code is written once and never touched again, so we will skip most of it using this
  library. This library simplifies instance creation, swapchain creation, and extension
  loading. It will be removed from the project eventually in an optional chapter that explains
  how to initialize that Vulkan boilerplate the "manual" way.
  - Package: [odin-vk-bootstrap](https://github.com/Capati/odin-vk-bootstrap)

- [VMA (vulkan memory allocator)][] Implements memory allocators for Vulkan. In Vulkan, the
  user has to deal with the memory allocation of buffers, images, and other resources on their
  own. This can be very difficult to get right in a performant and safe way. Vulkan Memory
  Allocator does it for us and allows us to simplify the creation of images and other
  resources. Widely used in personal Vulkan engines or smaller scale projects like emulators.
  Very high end projects like Unreal Engine or AAA engines write their own memory allocators.
  - Bindings: [odin-vma](https://github.com/Capati/odin-vma)

[cgltf]: https://github.com/jkuhlmann/cgltf
[dear IMGUI]: https://github.com/ocornut/imgui
[Vk Bootstrap]: https://github.com/charles-lunarg/vk-bootstrap/blob/master/src/VkBootstrap.cpp
[VMA (vulkan memory allocator)]: https://github.com/GPUOpen-LibrariesAndSDKs/VulkanMemoryAllocator
