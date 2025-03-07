---
sidebar_position: 2
description: An overview of Vulkan's main objects and their usage.
---

# Vulkan Usage

## Vulkan main objects and their use

- `vk.Instance` : The Vulkan context, used to access drivers.
- `vk.PhysicalDevice` : A GPU. Used to query physical GPU details, like features, capabilities,
  memory size, etc.
- `vk.Device` : The "logical" GPU context that you actually execute things on.
- `vk.Buffer` : A chunk of GPU visible memory.
- `vk.Image` : A texture you can write to and read from.
- `vk.Pipeline` : Holds the state of the gpu needed to draw. For example: shaders, rasterization options, depth settings.
- `vk.RenderPass` : Holds information about the images you are rendering into. All drawing
  commands have to be done inside a renderpass. Only used in legacy vkguide
- `vk.FrameBuffer` : Holds the target images for a renderpass. Only used in legacy vkguide
- `vk.CommandBuffer` : Encodes GPU commands. All execution that is performed on the GPU itself
  (not in the driver) has to be encoded in a `vk.CommandBuffer`.
- `vk.Queue` : Execution "port" for commands. GPUs will have a set of queues with different
  properties. Some allow only graphics commands, others only allow memory commands, etc.
  Command buffers are executed by submitting them into a queue, which will copy the rendering
  commands onto the GPU for execution.
- `vk.DescriptorSet` : Holds the binding information that connects shader inputs to data such as
  `vk.Buffer` resources and `vk.Image` textures. Think of it as a set of gpu-side pointers that
  you bind once.
- `vk.SwapchainKHR` : Holds the images for the screen. It allows you to render things into a
  visible window. The `KHR` suffix shows that it comes from an extension, which in this case is
  `VK_KHR_swapchain`
- `vk.Semaphore` : Synchronizes GPU to GPU execution of commands. Used for syncing multiple
  command buffer submissions one after other.
- `vk.Fence` : Synchronizes GPU to CPU execution of commands. Used to know if a command buffer
  has finished being executed on the GPU.

## High level Vulkan application flow

### Engine initialization

First, everything is initialized. To initialize Vulkan, you start by creating a `vk.Instance`.
From the `vk.Instance`, you query the list of `vk.PhysicalDevice` handles available in the
machine. For example, if the computer had both a dedicated GPU and integrated graphics, there
would be a `vk.PhysicalDevice` for each. After querying the limits and features of the
available `vk.PhysicalDevice` handles, you create a `vk.Device` from it. With a `vk.Device`,
you then get `vk.Queue` handles from it, allowing you to execute commands. Then you initialize
the `vk.SwapchainKHR`. Alongside the `vk.Queue` handles, you create `vk.CommandPool` objects
that enable you to allocate command buffers from them.

### Asset initialization

Once the core structures are initialized, you initialize the resources you need for whatever
you will be rendering. The materials are loaded, and you create a set of `vk.Pipeline` objects
for the shader combinations and parameters needed to render the materials. For the meshes, you
upload their vertex data into `vk.Buffer` resources, and you upload their textures into
`vk.Image` resources, making sure that the images are in "readable" layout. You also create
`vk.RenderPass` objects for whatever your main rendering passes you have. For example, there may
be a `vk.RenderPass` for the main rendering, and another for a shadow pass. On a real engine,
much of this can be parallelized and done in background threads, especially since pipeline
creation can be quite expensive.

### Render Loop

Now that everything is ready for rendering, you first ask the `vk.SwapchainKHR` for an image to
render to. Then you allocate a `vk.CommandBuffer` from a `vk.CommandBufferPool` or reuse an
already allocated command buffer that has finished execution, and "start" the command buffer,
which allows you to write commands into it. Next, you begin rendering by starting a
`vk.RenderPass`, this can be done with a normal `vk.RenderPass`, or using dynamic rendering. The
render pass specifies that you are rendering to the image requested from swapchain. Then create
a loop where you bind a `vk.Pipeline`, bind some `vk.DescriptorSet` resources (for the shader
parameters), bind the vertex buffers, and then execute a draw call. Once you are finished with
the drawing for a pass, you end the `vk.RenderPass`. If there is nothing more to render, you end
the `vk.CommandBuffer`. Finally, you submit the command buffer into the queue for rendering.
This will begin execution of the commands in the command buffer on the gpu. If you want to
display the result of the rendering, you "present" the image you have rendered to to the
screen. Because the execution may not have finished yet, you use a semaphore to make the
presentation of the image to the screen wait until rendering is finished.

Pseudocode of a render-loop in Vulkan:

```odin
package vk_engine

import vk "vendor:vulkan"

// Ask the swapchain for the index of the swapchain image we can render onto
image_index := request_image(mySwapchain)

// Create a new command buffer
cmd := allocate_command_buffer()

// Initialize the command buffer
vk.BeginCommandBuffer(cmd, ...)

// Start a new renderpass with the image index from swapchain as target to render onto
// Each framebuffer refers to a image in the swapchain
vk.CmdBeginRenderPass(cmd, main_render_pass, framebuffers[image_index])

// Rendering all objects
for object in PassObjects {
    // Bind the shaders and configuration used to render the object
    vk.CmdBindPipeline(cmd, object.pipeline)

    // Bind the vertex and index buffers for rendering the object
    vk.CmdBindVertexBuffers(cmd, object.VertexBuffer,...)
    vk.CmdBindIndexBuffer(cmd, object.IndexBuffer,...)

    // Bind the descriptor sets for the object (shader inputs)
    vk.CmdBindDescriptorSets(cmd, object.textureDescriptorSet)
    vk.CmdBindDescriptorSets(cmd, object.parametersDescriptorSet)

    // Execute drawing
    vk.CmdDraw(cmd,...)
}

// Finalize the render pass and command buffer
vk.CmdEndRenderPass(cmd)
vk.EndCommandBuffer(cmd)

// Submit the command buffer to begin execution on GPU
vk.QueueSubmit(graphicsQueue, cmd, ...)

// Display the image we just rendered on the screen
// renderSemaphore makes sure the image isn't presented until `cmd` is finished executing
vk.QueuePresent(graphicsQueue, renderSemaphore)
```
