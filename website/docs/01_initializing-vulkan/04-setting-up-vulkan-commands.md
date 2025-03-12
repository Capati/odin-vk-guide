---
sidebar_position: 4
sidebar_label: "Setting up Vulkan Commands"
---

# Setting up Vulkan Commands

We will begin by writing our `Frame_Data` struct, on the `engine.odin` file. This will hold the
structures and commands we will need to draw a given frame, as we will be double-buffering,
with the GPU running some commands while we write into others.

```odin
Frame_Data :: struct {
    command_pool:        vk.CommandPool,
    main_command_buffer: vk.CommandBuffer,
}

FRAME_OVERLAP :: 2
```

We also need to add those into the `Engine` structure, alongside the members we will use to
store the queue.

```odin
Engine :: struct {
    // other code ---
    // Frame resources
    frames:                [FRAME_OVERLAP]Frame_Data,
    frame_number:          int,
    graphics_queue:        vk.Queue,
    graphics_queue_family: u32,
}

engine_get_current_frame :: #force_inline proc(self: ^Engine) -> ^Frame_Data #no_bounds_check {
  return &self.frames[self.frame_number % FRAME_OVERLAP]
}
```

We will not be accessing the `frames` slice directly outside of initialization logic. So we add
a getter that will use the `frame_number` member we use to count the frames to access it. This
way it will flip between the 2 structures we have.

## Grabbing the Queue

We now need to find a valid queue family and create a queue from it. We want to create a queue
that can execute all types of commands, so that we can use it for everything in the engine.

Luckily, the `vkb` library allow us to get the Queue and Family directly.

Go to the end of the `engine_init_vulkan()` procedure, where we initialized the core Vulkan
structures.

At the end of it, add this code.

```odin
engine_init_vulkan :: proc(self: ^Engine) -> (ok: bool) {
    // ---- other code, initializing vulkan device ----

    // use vk-bootstrap to get a Graphics queue
    self.graphics_queue = vkb.device_get_queue(self.vkb.device, .Graphics) or_return
    self.graphics_queue_family = vkb.device_get_queue_index(self.vkb.device, .Graphics) or_return

    return true
}
```

We begin by requesting both a queue family and a queue of type Graphics from `vkb`.

## Creating the Command structures

For the pool, we start adding code into `engine_init_commands()` unlike before, from now on the
`vkb` library will not do anything for us, and we will start calling the Vulkan commands
directly.

```odin
engine_init_commands :: proc(self: ^Engine) -> (ok: bool) {
    // Create a command pool for commands submitted to the graphics queue.
    // We also want the pool to allow for resetting of individual command buffers.
    command_pool_info := vk.CommandPoolCreateInfo {
        sType            = .COMMAND_POOL_CREATE_INFO,
        pNext            = nil,
        flags            = {.RESET_COMMAND_BUFFER},
        queueFamilyIndex = self.graphics_queue_family,
    }

    for i in 0 ..< FRAME_OVERLAP {
        // Create the command pool
        vk_check(
            vk.CreateCommandPool(
                self.vk_device,
                &command_pool_info,
                nil,
                &self.frames[i].command_pool,
            ),
        )

        // Allocate the default command buffer that we will use for rendering
        cmd_alloc_info := vk.CommandBufferAllocateInfo {
            sType              = .COMMAND_BUFFER_ALLOCATE_INFO,
            pNext              = nil,
            commandPool        = self.frames[i].command_pool,
            commandBufferCount = 1,
            level              = .PRIMARY,
        }

        vk_check(
            vk.AllocateCommandBuffers(
                self.vk_device,
                &cmd_alloc_info,
                &self.frames[i].main_command_buffer,
            ),
        )
    }

    return true
}
```

Most Vulkan Info structures, used for  the `vk.CreateX` procedures, and a lot of the other
Vulkan structures, need `sType` and `pNext` set. This is used for extensions, as some
extensions will still call the `vk.CreateX` procedure, but with structs of a different type
than the normal one. The `sType` helps the implementation know what struct is being used in the
procedure.

:::tip[Zero Initialization]

Since everything in Odin is zero-initialized, we can use designated initializers and omit
fields with known default values. This means we don't need to explicitly assign `nil` to
`pNext`. By knowing that, we can rest assured that we don't leave uninitialized data in the
struct.

:::

We set `queueFamilyIndex` to the `graphics_queue_family` that we grabbed before. This means
that the command pool will create commands that are compatible with any queue of that
"graphics" family.

We are also setting something in the `flags` parameter. A lot of Vulkan structures will have
that `flags` parameter, for extra options, they are of type `bit_set`. We are sending
`{.RESET_COMMAND_BUFFER}`, which tells Vulkan that we expect to be able to reset individual
command buffers made from that pool. An alternative approach would be to reset the whole
Command Pool at once, which resets all command buffers. In that case we would not need that
flag.

At the end, we finally call `vk.CreateCommandPool`, giving it our `vk.Device`, the
`command_pool_info` for create parameters, and a pointer to the `command_pool` field, which
will get overwritten if it succeeds.

To check if the command succeeds, we use the `vk_check()` procedure. It will just immediately
abort if something happens.

Now that we have the `vk.CommandPool` created, and stored in the `command_pool` field, we can
allocate our command buffer from it.

As with the command pool, we need to fill the `sType`, and then continue the rest of the Info
struct.

We let Vulkan know that the parent of our command will be the `command_pool` we just created,
and we want to create only one command buffer.

The `commandBufferCount` parameter allows you to allocate multiple buffers at once. Make sure
that the pointer you send to `vk.AllocateCommandBuffer` has space for those.

The `level` is set to `PRIMARY`. Command buffers can be Primary or Secondary level. Primary
level are the ones that are sent into a `vk.Queue`, and do all of the work. This is what we
will use in the guide. Secondary level are ones that can act as "subcommands" to a primary
buffer. They are most commonly used when you want to record commands for a single pass from
multiple threads. We are not going to use them as with the architecture we will do, we wont
need to multithread command recording.

You can find the details and parameters for those info structures here:

- [VkCommandPoolCreateInfo](https://registry.khronos.org/vulkan/specs/1.3-extensions/html/chap6.html#VkCommandPoolCreateInfo)
- [VkCommandBufferAllocateInfo](https://registry.khronos.org/vulkan/specs/1.3-extensions/html/chap6.html#VkCommandBufferAllocateInfo)

## The `initializers.odin`

If you remember the article that explored the project files, we commented that the
`initializers.odin` file will contain abstraction over the initialization of Vulkan structures.
Let's look into the implementation for those 2 structures.

```odin title="tutorial/01_initializing_vulkan/initializers.odin"
command_pool_create_info :: proc(
    queueFamilyIndex: u32,
    flags: vk.CommandPoolCreateFlags = {},
) -> vk.CommandPoolCreateInfo {
    info := vk.CommandPoolCreateInfo {
        sType            = .COMMAND_POOL_CREATE_INFO,
        queueFamilyIndex = queueFamilyIndex,
        flags            = flags,
    }
    return info
}

command_buffer_allocate_info :: proc(
    pool: vk.CommandPool,
    count: u32 = 1,
) -> vk.CommandBufferAllocateInfo {
    info := vk.CommandBufferAllocateInfo {
        sType              = .COMMAND_BUFFER_ALLOCATE_INFO,
        commandPool        = pool,
        commandBufferCount = count,
        level              = .PRIMARY,
    }
    return info
}
```

We will be hardcoding command buffer level to `PRIMARY` . As we wont ever be using secondary
command buffers, we can just ignore their existence and configuration parameters. By
abstracting things with defaults that match your engine, you can simplify things a bit.

```odin title="tutorial/01_initializing_vulkan/engine.odin"
engine_init_commands :: proc(self: ^Engine) -> (ok: bool) {
    // Create a command pool for commands submitted to the graphics queue.
    // We also want the pool to allow for resetting of individual command buffers.
    command_pool_info := command_pool_create_info(
        self.graphics_queue_family,
        {.RESET_COMMAND_BUFFER},
    )

    for i in 0 ..< FRAME_OVERLAP {
        // Create the command pool
        vk_check(
            vk.CreateCommandPool(
                self.vk_device,
                &command_pool_info,
                nil,
                &self.frames[i].command_pool,
            ),
        )

        // Allocate the default command buffer that we will use for rendering
        cmd_alloc_info := command_buffer_allocate_info(self.frames[i].command_pool)

        vk_check(
            vk.AllocateCommandBuffers(
                self.vk_device,
                &cmd_alloc_info,
                &self.frames[i].main_command_buffer,
            ),
        )
    }

    return true
}
```

Much better and shorter. Over the guide, we will keep using the procedures in that file. You
will be able to reuse then in other projects safely given how simple it is.

## Cleanup

Same as before, what we have created, we have to delete.

```odin
engine_cleanup :: proc(self: ^Engine) {
    if !self.is_initialized {
        return
    }

    // Make sure the gpu has stopped doing its things
    ensure(vk.DeviceWaitIdle(self.vk_device) == .SUCCESS)

    for &frame in self.frames {
        vk.DestroyCommandPool(self.vk_device, frame.command_pool, nil)
    }

    // --- rest of code
}
```

As the command pool is the most recent Vulkan object, we need to destroy it before the other
objects. It's not possible to individually destroy `vk.CommandBuffer`, destroying their parent
pool will destroy all of the command buffers allocated from it.

`vk.Queue`-s also can't be destroyed, as, like with the `vk.PhysicalDevice`, they aren't really
created objects, more like a handle to something that already exists as part of the VkInstance.

We now have a way to send commands to the gpu, but we still need another piece, which is the
synchronization structures to sincronize GPU execution with CPU.
