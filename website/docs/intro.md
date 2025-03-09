---
slug: /
sidebar_position: 1
sidebar_label: "Home"
---

# Welcome to VulkanGuide

![scene](./img/fullscene.png)
End stage after the tutorial

:::tip[Odin Version]

This page presents an [Odin](https://odin-lang.org/) adaptation of the
[vkguide.dev](https://vkguide.dev/) tutorial. Full credit goes to the original authors.

:::

Welcome to a new work-in-progress Vulkan guide. The focus of this guide is to understand Vulkan
correctly, and act as a stepping stone for then working in your own projects. Unlike most
samples and other Vulkan guides, which like to hardcode rendering loops, in here we will have a
focus around dynamic rendering, so that it can act as a better base code for a game engine.

While the guide is focused around game rendering, its concepts can be used in CAD and
visualization just fine.

This guide is meant for the people who already know the basics about 3d graphics, and have
worked with either OpenGL or DirectX in the past. This guide will not explain 3d rendering
basics such as linear algebra math.

:::warning[Vulkan API Version]

The code uses **Vulkan 1.3**, and directly uses those new features to simplify the tutorial and
engine architecture.

:::

The guide is separated into multiple sections for code organization.

- **[Introduction](/category/introduction)** - Overview about Vulkan API and the libraries used
  by this project
- **[Chapter 0](/category/0-project-setup)** - Setting up the guide initial code
- **[Chapter 1](/category/1-initializing-vulkan)** - Vulkan initialization and render loop
  setup. (Draws a flashing clear color)
- **[Chapter 2](/category/2-drawing-with-compute)** - Vulkan compute shaders and drawing (Uses
  a compute shader to draw)
- **Chapter 3** - Vulkan mesh drawing (Draws meshes using the graphics pipeline)
- **Chapter 4** - Textures and better descriptor set management
- **Chapter 5** - Full GLTF scene loading and high performance rendering
