---
sidebar_position: 1
sidebar_label: "Improving The Render Loop"
---

# Improving The Render Loop

Before we begin drawing, we need to implement a couple other things. First we have a deletion
queue that will allow us to safely handle the cleanup of a growing amount of objects, and then
we will change the render loop to draw into a non-swapchain image and then copy it to the
swapchain.

## Deletion Queue

As we begin to add more and more vulkan structures, we need a way to handle their destruction.
We could keep adding more things into the `engine_cleanup()` procedure, but that would not
scale and would be very annoying to keep synced correctly. We are going to add a new structure
to the engine, called a DeletionQueue. This is a common approach by lots of engines, where we
add the objects we want to delete into some queue, and then run that queue to delete all the
objects in the correct orders.

In our implementation, we will use a deque of vulkan handles of various types such as
`vk.Image`, `vk.Buffer`,and so on. And then delete those from a loop. We will be using that
deque as a LIFO (Last-In, First-Out) queue, so that when we flush the deletion queue, it first
destroys the objects that were added into it last.

This is the entire implementation.

```odin title="deletion_queue.odin (create the file)"
package vk_guide

// Core
import "core:mem"

// Vendor
import vk "vendor:vulkan"

// Libraries
import "libs:vma"

Resource :: union {
    // Cleanup procedures
    proc "c" (),

    // Pipeline objects
    vk.Pipeline,
    vk.PipelineLayout,

    // Descriptor-related objects
    vk.DescriptorPool,
    vk.DescriptorSetLayout,

    // Resource views and samplers
    vk.ImageView,
    vk.Sampler,

    // Command-related objects
    vk.CommandPool,

    // Synchronization primitives
    vk.Fence,
    vk.Semaphore,

    // Core memory resources
    vk.Buffer,
    vk.DeviceMemory,

    // Memory allocator
    vma.Allocator,
}

Deletion_Queue :: struct {
    device:    vk.Device,
    resources: [dynamic]Resource,
    allocator: mem.Allocator,
}

deletion_queue_init :: proc(
    self: ^Deletion_Queue,
    device: vk.Device,
    allocator := context.allocator,
) {
    assert(self != nil, "Invalid 'Deletion_Queue'")
    assert(device != nil, "Invalid 'Device'")

    self.allocator = allocator
    self.device = device
    self.resources = make([dynamic]Resource, self.allocator)
}

deletion_queue_destroy :: proc(self: ^Deletion_Queue) {
    assert(self != nil)

    context.allocator = self.allocator

    // Flush any remaining resources
    deletion_queue_flush(self)

    // Free dynamic array
    delete(self.resources)
}

deletion_queue_push :: proc(self: ^Deletion_Queue, resource: Resource) {
    append(&self.resources, resource)
}

// LIFO (Last-In, First-Out) deletion.
deletion_queue_flush :: proc(self: ^Deletion_Queue) {
    assert(self != nil)

    if len(self.resources) == 0 {
        return
    }

    // Process resources in reverse order (LIFO)
    #reverse for &resource in self.resources {
        switch &res in resource {
        // Cleanup procedures
        case proc "c" ():
          res()

        // Pipeline objects
        case vk.Pipeline:
            vk.DestroyPipeline(self.device, res, nil)
        case vk.PipelineLayout:
            vk.DestroyPipelineLayout(self.device, res, nil)

        // Descriptor-related objects
        case vk.DescriptorPool:
            vk.DestroyDescriptorPool(self.device, res, nil)
        case vk.DescriptorSetLayout:
            vk.DestroyDescriptorSetLayout(self.device, res, nil)

        // Resource views and samplers
        case vk.ImageView:
            vk.DestroyImageView(self.device, res, nil)
        case vk.Sampler:
            vk.DestroySampler(self.device, res, nil)

        // Command-related objects
        case vk.CommandPool:
            vk.DestroyCommandPool(self.device, res, nil)

        // Synchronization primitives
        case vk.Fence:
            vk.DestroyFence(self.device, res, nil)
        case vk.Semaphore:
            vk.DestroySemaphore(self.device, res, nil)

        // Core memory resources
        case vk.Buffer:
            vk.DestroyBuffer(self.device, res, nil)
        case vk.DeviceMemory:
            vk.FreeMemory(self.device, res, nil)

        // Memory allocator
        case vma.Allocator:
            vma.destroy_allocator(res)
        }
    }

    // Clear the array after processing all resources
    clear(&self.resources)

```

The code defines a `Deletion_Queue` struct that tracks Vulkan resources that need to be
destroyed. The `Resource` union type can hold any Vulkan object type (buffers, images,
pipelines, etc.) or a procedure callback. We will add more resources as needed.

Key procedures:

- `deletion_queue_init` - Initializes a new deletion queue with references to the Vulkan device
- `deletion_queue_push` - Adds resources to the queue for later cleanup
- `deletion_queue_flush` - Destroys all queued resources in reverse order (LIFO)
- `deletion_queue_destroy` - Flushes remaining resources and frees the queue itself

:::tip[LIFO (Last-In, First-Out)]

The **LIFO** approach is important because Vulkan resources often have dependencies (e.g., a
pipeline depends on a pipeline layout), so destroying them in reverse creation order ensures
dependencies are respected.

:::

We will have the deletion queue in multiple places, for multiple lifetimes of objects. One of
them is on the `Engine` itself, and will be flushed when the engine gets destroyed. Global
objects go into that one. We will also store one deletion queue for each frame in flight, which
will allow us to delete objects next frame after they are used.

Add it into `Engine` struct, and inside the `Frame_Data` struct.

```odin
Frame_Data :: struct {
     // Other data ---
    deletion_queue: Deletion_Queue,
}

Engine :: struct {
     // Other data ---
    main_deletion_queue: Deletion_Queue,
}
```

Before we can use the deletion queue, we need to initialize then by calling
`deletion_queue_init` from `engine_init_vulkan` and `engine_init_commands`.

```odin
engine_init_vulkan :: proc(self: ^Engine) -> (ok: bool) {
    // Other code ---

    // Initialize global deletion queue
    deletion_queue_init(&self.main_deletion_queue, self.vk_device)

    return true
}
```

```odin
engine_init_commands :: proc(self: ^Engine) -> (ok: bool) {
    // Other code ---

    for &frame in self.frames {
        // Create peer frame deletion queue
        deletion_queue_init(&frame.deletion_queue, self.vk_device)

        // Other code ---
    }

    return true
}
```

We then call it from 2 places, right after we wait on the Fence per frame, and from the
`engine_cleanup()` procedure after the `WaitIdle` call. By flushing it right after the fence,
we make sure that the GPU has finished executing that frame so we can safely delete objects
create for that specific frame only. We also want to make sure we free those per-frame
resources when destroying the rest of frame data.

```odin
engine_draw :: proc(self: ^Engine) -> (ok: bool) {
    frame := engine_get_current_frame(self)

    // Wait until the gpu has finished rendering the last frame. Timeout of 1 second
    vk_check(vk.WaitForFences(self.vk_device, 1, &frame.render_fence, true, 1e9)) or_return

    deletion_queue_flush(&frame.deletion_queue)

    // Other code ---
}
```

```odin
engine_cleanup :: proc(self: ^Engine) {
    if !self.is_initialized {
        return
    }

    // Make sure the gpu has stopped doing its things
    ensure(vk.DeviceWaitIdle(self.vk_device) == .SUCCESS)

    for &frame in self.frames {
        vk.DestroyCommandPool(self.vk_device, frame.command_pool, nil)

        // Destroy sync objects
        vk.DestroyFence(self.vk_device, frame.render_fence, nil)
        vk.DestroySemaphore(self.vk_device, frame.swapchain_semaphore, nil)

        // Flush and destroy the peer frame deletion queue
        deletion_queue_destroy(&frame.deletion_queue)
    }

    // Flush and destroy the global deletion queue
    deletion_queue_destroy(&self.main_deletion_queue)

    // Rest of cleanup procedure
}
```

:::tip[Flush and destroy]

Note that `deletion_queue_destroy` will flush and free allocated memory, making the deletion
queue unusable afterward. On the other hand, `deletion_queue_flush` only flushes the queue.

:::

With the deletion queue set, now whenever we create new vulkan objects we can just add them
into the queue.

## Memory Allocation

To improve the render loop, we will need to allocate a image, and this gets us into how to
allocate objects in vulkan. We are going to skip that entire chapter, because we will be using
**Vulkan Memory Allocator** library. Dealing with the different memory heaps and object
restrictions such as image alignment is very error prone and really hard to get right,
specially if you want to get it right at a decent performance. By using VMA, we skip all that,
and we get a battle tested way that is guaranteed to work well. There are cases like the PCSX3
emulator project, where they replaced their attempt at allocation to VMA, and won 20% extra
framerate.

:::warning[VMA library]

Before you can continue, make sure uou have `vma` library in place (the binary in `libs/vma`).
Check the [Project Setup](/project-setup/building-project) and the
[odin-vma](https://github.com/Capati/odin-vma) repository for more information.

:::

Start by adding the allocator to the `Engine` structure.

```odin title="Import the 'libs:vma' package at the top"
// Libraries
import "libs:vma"
```

```odin
Engine :: struct {
    vma_allocator: vma.Allocator,
}
```

Now we will initialize it from `engine_init_vulkan()` call, at the end of the procedure.

```odin
engine_init_vulkan :: proc(self: ^Engine) -> (ok: bool) {
    // Other code ---

    // Initializes a subset of Vulkan functions required by VMA
    vma_vulkan_functions := vma.create_vulkan_functions()

    allocator_create_info: vma.Allocator_Create_Info = {
        flags            = {.Buffer_Device_Address},
        instance         = self.vk_instance,
        physical_device  = self.vk_physical_device,
        device           = self.vk_device,
        vulkan_functions = &vma_vulkan_functions,
    }

    vk_check(
        vma.create_allocator(allocator_create_info, &self.vma_allocator),
        "Failed to Create Vulkan Memory Allocator",
    ) or_return

    deletion_queue_push(&self.main_deletion_queue, self.vma_allocator)

    return true
}
```

There isn't much to explain it, we are initializing the `vma_allocator` field, and then adding
its destruction procedure into the destruction queue so that it gets cleared when the engine
exits. We hook the physical device, instance, and device to the creation procedure. We give the
flag `.Buffer_Device_Address` that will let us use GPU pointers later when we need them. Vulkan
Memory Allocator library follows similar call conventions as the vulkan api, so it works with
similar info structs.

:::warning[Vulkan functions]

Note that since we are fetching Vulkan functions dynamically, we need to set the same function
pointers using the utility procedure `vma.create_vulkan_functions` and assign them to
`vulkan_functions`.

:::

## New Draw Loop

Drawing directly into the swapchain is fine for many projects, and it can even be optimal in
some cases such as phones. But it comes with a few restrictions. The most important of them is
that the formats of the image used in the swapchain are not guaranteed. Different OS, drivers,
and windowing modes can have different optimal swapchain formats. Things like HDR support also
need their own very specific formats. Another one is that we only get a swapchain image index
from the windowing present system. There are low-latency techniques where we could be rendering
into another image, and then directly push that image to the swapchain with very low latency.

One very important limitation is that their resolution is fixed to whatever your window size
is. If you want to have higher or lower resolution, and then do some scaling logic, you need to
draw into a different image.

And last, swapchain formats are, for the most part, low precision. Some platforms with High
Dynamic Range rendering have higher precision formats, but you will often default to 8 bits per
color. So if you want high precision light calculations, system that would prevent banding, or
to be able to go past 1.0 on the normalized color range, you will need a separate image for
drawing.

For all those reasons, we will do the whole tutorial rendering into a separate image than the
one from the swapchain. After we are doing with the drawing, we will then copy that image into
the swapchain image and present it to the screen.

The image we will be using is going to be in the  RGBA 16-bit float format. This is slightly
overkill, but will provide us with a lot of extra precision that will come in handy when doing
lighting calculations and better rendering.

### Vulkan Images

We have already dealt superficially with images when setting up the swapchain, but it was
handled by VkBootstrap. This time we will create the images ourselves.

Lets begin by adding the new members we will need to the VulkanEngine class.

On `core.odin`, add this structure which holds the data needed for an image. We will hold a
`vk.Image` alongside its default `vk.ImageView`, then the allocation for the image memory, and
last, the image size and its format, which will be useful when dealing with the image. We also
store the device and VMA allocator for use on cleanup later.

```odin title="core.odin"
Allocated_Image :: struct {
    device:       vk.Device,
    image:        vk.Image,
    image_view:   vk.ImageView,
    image_extent: vk.Extent3D,
    image_format: vk.Format,
    allocator:    vma.Allocator,
    allocation:   vma.Allocation,
}

destroy_image :: proc(self: Allocated_Image) {
    vk.DestroyImageView(self.device, self.image_view, nil)
    vma.destroy_image(self.allocator, self.image, self.allocation)
}
```

In the `Engine` structure, add the `draw_image` field to store the image we will render to, and
the `draw_extent` field to specify the size of the rendered image.

```odin title="engine.odin"
Engine :: struct {
    // Draw resources
    draw_image:  Allocated_Image,
    draw_extent: vk.Extent2D,
}
```

For the `destroy_image` procedure, we first destroy the image-view, and then destroy the
image itself using **VMA**. This will free the image and its memory correctly.

Lets check the `initializers.odin` procedure for image and imageview create info.

```odin title="initializers.odin"
image_create_info :: proc(
    format: vk.Format,
    usageFlags: vk.ImageUsageFlags,
    extent: vk.Extent3D,
) -> vk.ImageCreateInfo {
    info := vk.ImageCreateInfo {
        sType       = .IMAGE_CREATE_INFO,
        imageType   = .D2,
        format      = format,
        extent      = extent,
        mipLevels   = 1,
        arrayLayers = 1,
        samples     = {._1},
        tiling      = .OPTIMAL,
        usage       = usageFlags,
    }
    return info
}

imageview_create_info :: proc(
    format: vk.Format,
    image: vk.Image,
    aspectFlags: vk.ImageAspectFlags,
) -> vk.ImageViewCreateInfo {
    info := vk.ImageViewCreateInfo {
        sType = .IMAGE_VIEW_CREATE_INFO,
        viewType = .D2,
        image = image,
        format = format,
        subresourceRange = {levelCount = 1, layerCount = 1, aspectMask = aspectFlags},
    }
    return info
}
```

We will hardcode the image tiling to `OPTIMAL`, which means that we allow the gpu to shuffle the
data however it sees fit. If we want to read the image data from cpu, we would need to use
tiling LINEAR, which makes the gpu data into a simple 2d array. This tiling highly limits what
the gpu can do, so the only real use case for LINEAR is CPU readback.

On the imageview creation, we need to setup the subresource. Thats similar to the one we used
in the pipeline barrier.

Lets update our deletion queue to handle the `Allocated_Image`:

```odin title="deletion_queue.odin"
Resource :: union {
    // Higher-level custom resources
    Allocated_Image,
}

deletion_queue_flush :: proc(self: ^Deletion_Queue) {
    #reverse for &resource in self.resources {
        switch &res in resource {
        // Higher-level custom resources
        case Allocated_Image:
            destroy_image(res)
        }
    }
}
```

Now, at the end of `engine_init_swapchain`, lets create it.

```odin title="engine.odin"
engine_init_swapchain :: proc(self: ^Engine) -> (ok: bool) {
    // Other code ---

    // Draw image size will match the window
    draw_image_extent := vk.Extent3D {
        width  = self.window_extent.width,
        height = self.window_extent.height,
        depth  = 1,
    }

    // Hardcoding the draw format to 32 bit float
    self.draw_image.image_format = .R16G16B16A16_SFLOAT
    self.draw_image.image_extent = draw_image_extent
    self.draw_image.allocator = self.vma_allocator
    self.draw_image.device = self.vk_device

    draw_image_usages := vk.ImageUsageFlags {
        .TRANSFER_SRC,
        .TRANSFER_DST,
        .STORAGE,
        .COLOR_ATTACHMENT,
    }

    rimg_info := image_create_info(
        self.draw_image.image_format,
        draw_image_usages,
        draw_image_extent,
    )

    // For the draw image, we want to allocate it from gpu local memory
    rimg_allocinfo := vma.Allocation_Create_Info {
        usage          = .Gpu_Only,
        required_flags = {.DEVICE_LOCAL},
    }

    // Allocate and create the image
    vk_check(
        vma.create_image(
            self.vma_allocator,
            rimg_info,
            rimg_allocinfo,
            &self.draw_image.image,
            &self.draw_image.allocation,
            nil,
        ),
    ) or_return
    defer if !ok {
        vma.destroy_image(self.vma_allocator, self.draw_image.image, nil)
    }

    // Build a image-view for the draw image to use for rendering
    rview_info := imageview_create_info(
        self.draw_image.image_format,
        self.draw_image.image,
        {.COLOR},
    )

    vk_check(
        vk.CreateImageView(self.vk_device, &rview_info, nil, &self.draw_image.image_view),
    ) or_return
    defer if !ok {
        vk.DestroyImageView(self.vk_device, self.draw_image.image_view, nil)
    }

    // Add to deletion queues
    deletion_queue_push(&self.main_deletion_queue, self.draw_image)

    return true
}
```

We begin by creating a `vk.Extent3D` structure with the size of the image we want, which will
match our window size. We copy it into the AllocatedImage.

Then, we need to fill our usage flags. In vulkan, all images and buffers must fill a UsageFlags
with what they will be used for. This allows the driver to perform optimizations in the
background depending on what that buffer or image is going to do later. In our case, we want
`TRANSFER_SRC` and `TRANSFER_DST` so that we can copy from and into the image,  Storage because
thats the "compute shader can write to it" layout, and `COLOR_ATTACHMENT` so that we can use
graphics pipelines to draw geometry into it.

The format is going to be `vk.Format.R16G16B16A16_SFLOAT`. This is 16 bit floats for all 4
channels, and will use 64 bits per pixel. Thats a fair amount of data, 2x what a 8 bit color
image uses, but its going to be useful.

When creating the image itself, we need to send the image info and an alloc info to VMA. VMA
will do the vulkan create calls for us and directly give us the vulkan image. The interesting
thing in here is Usage and the required memory flags. With `.Gpu_Only` usage, we are letting
VMA know that this is a gpu texture that wont ever be accessed from CPU, which lets it put it
into gpu VRAM. To make extra sure of that, we are also setting `.DEVICE_LOCAL` as a memory
flag. This is a flag that only gpu-side VRAM has, and guarantees the fastest access.

In vulkan, there are multiple memory regions we can allocate images and buffers from. PC
implementations with dedicated GPUs will generally have a cpu ram region, a GPU Vram region,
and a "upload heap" which is a special region of gpu vram that allows cpu writes. If you have
resizable bar enabled, the upload heap can be the entire gpu vram. Else it will be much
smaller, generally only 256 megabytes. We tell VMA to put it on GPU_ONLY which will prioritize
it to be on the gpu vram but outside of that upload heap region.

With the image allocated, we create an imageview to pair with it. In vulkan, you need a
imageview to access images. This is generally a thin wrapper over the image itself that lets
you do things like limit access to only 1 mipmap. We will always be pairing vkimages with their
"default" imageview in this tutorial.

### The New Draw Loop

Now that we have a new draw image, lets add it into the render loop.

We will need a way to copy images, so add this into `images.odin`.

```odin title="images.odin"
copy_image_to_image :: proc(
    cmd: vk.CommandBuffer,
    source: vk.Image,
    destination: vk.Image,
    src_size: vk.Extent2D,
    dst_size: vk.Extent2D,
) {
    blit_region := vk.ImageBlit2 {
        sType = .IMAGE_BLIT_2,
        pNext = nil,
        srcOffsets = [2]vk.Offset3D {
            {0, 0, 0},
            {x = i32(src_size.width), y = i32(src_size.height), z = 1},
        },
        dstOffsets = [2]vk.Offset3D {
            {0, 0, 0},
            {x = i32(dst_size.width), y = i32(dst_size.height), z = 1},
        },
        srcSubresource = {aspectMask = {.COLOR}, mipLevel = 0, baseArrayLayer = 0, layerCount = 1},
        dstSubresource = {aspectMask = {.COLOR}, mipLevel = 0, baseArrayLayer = 0, layerCount = 1},
    }

    blit_info := vk.BlitImageInfo2 {
        sType          = .BLIT_IMAGE_INFO_2,
        srcImage       = source,
        srcImageLayout = .TRANSFER_SRC_OPTIMAL,
        dstImage       = destination,
        dstImageLayout = .TRANSFER_DST_OPTIMAL,
        filter         = .LINEAR,
        regionCount    = 1,
        pRegions       = &blit_region,
    }

    vk.CmdBlitImage2(cmd, &blit_info)
}
```

Vulkan has 2 main ways of copying one image to another. you can use `vk.CmdCopyImage` or
`vk.CmdBlitImage`. `CopyImage` is faster, but its much more restricted, for example the
resolution on both images must match. Meanwhile, blit image lets you copy images of different
formats and different sizes into one another. You have a source rectangle and a target
rectangle, and the system copies it into its position. Those two procedures are useful when
setting up the engine, but later its best to ignore them and write your own version that can do
extra logic on a fullscreen fragment shader.

With it, we can now update the render loop. As draw() is getting too big, we are going to leave
the syncronization, command buffer management, and transitions in the draw() procedure, but we
are going to add the draw commands themselves into a `engine_draw_background()` procedure.

```odin
engine_draw_background :: proc(self: ^Engine, cmd: vk.CommandBuffer) -> (ok: bool) {
    // Make a clear-color from frame number. This will flash with a 120 frame period.
    flash := abs(math.sin(f32(self.frame_number) / 120.0))
    clear_value := vk.ClearColorValue {
        float32 = {0.0, 0.0, flash, 1.0},
    }

    clear_range := image_subresource_range({.COLOR})

    // Clear image
    vk.CmdClearColorImage(cmd, self.draw_image.image, .GENERAL, &clear_value, 1, &clear_range)
}
```

Add the procedure to the header too.

We will be changing the code that records the command buffer. You can now delete the older one.
The new code is this.

```odin title="engine_draw"
self.draw_extent.width = self.draw_image.image_extent.width
self.draw_extent.height = self.draw_image.image_extent.height

// Start the command buffer recording
vk_check(vk.BeginCommandBuffer(cmd, &cmd_begin_info)) or_return

// Transition our main draw image into general layout so we can write into it
// we will overwrite it all so we dont care about what was the older layout
transition_image(cmd, self.draw_image.image, .UNDEFINED, .GENERAL)

// Clear the image
engine_draw_background(self, cmd) or_return

// Transition the draw image and the swapchain image into their correct transfer layouts
transition_image(cmd, self.draw_image.image, .GENERAL, .TRANSFER_SRC_OPTIMAL)
transition_image(
    cmd,
    self.swapchain_images[frame.swapchain_image_index],
    .UNDEFINED,
    .TRANSFER_DST_OPTIMAL,
)

// ExecEte a copy from the draw image into the swapchain
copy_image_to_image(
    cmd,
    self.draw_image.image,
    self.swapchain_images[frame.swapchain_image_index],
    self.draw_extent,
    self.swapchain_extent,
)

// Set swapchain image layout to Attachment Optimal so we can draw it
transition_image(
    cmd,
    self.swapchain_images[frame.swapchain_image_index],
    .TRANSFER_DST_OPTIMAL,
    .COLOR_ATTACHMENT_OPTIMAL,
)

// Draw imgui into the swapchain image
engine_draw_imgui(self, cmd, self.swapchain_image_views[frame.swapchain_image_index])

// Set swapchain image layout to Present so we can show it on the screen
transition_image(
    cmd,
    self.swapchain_images[frame.swapchain_image_index],
    .COLOR_ATTACHMENT_OPTIMAL,
    .PRESENT_SRC_KHR,
)

// Finalize the command buffer (we can no longer add commands, but it can now be executed)
vk_check(vk.EndCommandBuffer(cmd)) or_return
```

The main difference we have in the render loop is that we no longer do the clear on the
swapchain image. Instead, we do it on the `draw_image.image`. Once we have cleared the image,
we transition both the swapchain and the draw image into their layouts for transfer, and we
execute the copy command. Once we are done with the copy command, we transition the swapchain
image into present layout for display. As we are always drawing on the same image, our
draw_image does not need to access swapchain index, it just clears the draw image. We are also
writing the `draw_extent` that we will use for our draw region.

This will now provide us a way to render images outside of the swapchain itself. We now get
significantly higher pixel precision, and we unlock some other techniques.

With that done, we can now move into the actual compute shader execution steps.
