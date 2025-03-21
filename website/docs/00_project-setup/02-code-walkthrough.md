---
sidebar_position: 2
description: Engine setup and rendering loop initialization.
---

# Code Walkthrough

Because we are starting this chapter with an already made code skeleton, we are going to see
what it actually does.

The files are all stored in the `tutorial/<chapter-name>` folder.

- `engine.odin` : This will be the main file for the engine, and where most of the code of the
  tutorial will go
- `main.odin` : Entry point for the code. Has nothing but just calls into engine code
- `initializers.odin` : This will contain helpers to create vulkan structures
- `images.odin` : This will contain image related vulkan helpers
- `pipelines.odin` : Will contain abstractions for pipelines
- `descriptors.odin` : Will contain descriptor set abstractions
- `loader.odin` : Will contain GLTF loading logic
- `core.odin` : Provide widely used default structures and procedures
- `platform.odin`: window creation and other platform specific code

`engine.odin` will be our main file, and the core of the project. `loader.odin` will be tied
into it as it will need to interface it while loading GLTF files.

The other files are for generic vulkan abstraction layers that will get built as the tutorial
needs. Those abstraction files have no dependencies other than vulkan, so you can keep them for
your own projects.

## Code

We start with something simple, `main.odin`.

### Main

```odin
package vk_guide

// Core
import "core:log"
import "core:mem"

start :: proc() -> (ok: bool) {
    engine := new(Engine)
    ensure(engine != nil, "Failed to allocate 'Engine' object")
    defer free(engine)

    engine_init(engine) or_return
    defer engine_cleanup(engine)

    engine_run(engine) or_return

    return true
}

main :: proc() {
    when ODIN_DEBUG {
        context.logger = log.create_console_logger(opt = {.Level, .Terminal_Color})
        defer log.destroy_console_logger(context.logger)

        track: mem.Tracking_Allocator
        mem.tracking_allocator_init(&track, context.allocator)
        context.allocator = mem.tracking_allocator(&track)

        defer {
            if len(track.allocation_map) > 0 {
                log.errorf("=== %v allocations not freed: ===", len(track.allocation_map))
                for _, entry in track.allocation_map {
                    log.debugf("%v bytes @ %v", entry.size, entry.location)
                }
            }
            if len(track.bad_free_array) > 0 {
                log.errorf("=== %v incorrect frees: ===", len(track.bad_free_array))
                for entry in track.bad_free_array {
                    log.debugf("%p @ %v", entry.memory, entry.location)
                }
            }
            mem.tracking_allocator_destroy(&track)
        }
    }

    start()
}
```

The `main` procedure initializes a logger for general-purpose logging and sets up a [Tracking
Allocator][] to detect memory leaks or improper deallocations. We then call the `start`
procedure to begin the application's core logic. From there, we allocate an `Engine` object,
defined in `engine.odin`, which serves as the central state for our engine.

:::note[]

In the future, this could be a good place to set some configuration parameters brought from the
command line arguments or a settings file.

:::

### Core

`core.odin` holds this:

```odin
package vk_guide

// Core
import intr "base:intrinsics"
import "base:runtime"
import "core:log"

// Vendor
import vk "vendor:vulkan"

@(require_results)
vk_check :: #force_inline proc(
    res: vk.Result,
    message := "Detected Vulkan error",
    loc := #caller_location,
) -> bool {
    if intr.expect(res, vk.Result.SUCCESS) == .SUCCESS {
        return true
    }
    log.errorf("[Vulkan Error] %s: %v", message, res)
    runtime.print_caller_location(loc)
    return false
}
```

The `vk_check` procedure we will use for our error handling on vulkan calls.

### Initializers

`initializers.odin` is pre-written. It contains initializers for most of the vulkan info
structs and other similar ones. They abstract those structs slightly, and every time we use one
of them, its code and abstraction will be explained.

### Platform

Vulkan by itself is a platform agnostic API and does not include tools for creating a window to
display the rendered results, for that, we use `GLFW` to opening a window and handle input. The
window creation and other platform specific code are located in `platform.odin`:

```odin
package vk_guide

// Core
import "base:runtime"
import "core:log"
import "core:strings"

// Vendor
import "vendor:glfw"

glfw_error_callback :: proc "c" (error: i32, description: cstring) {
    context = runtime.default_context()
    context.logger = g_logger
    log.errorf("GLFW [%d]: %s", error, description)
}

@(require_results)
create_window :: proc(title: string, width, height: u32) -> (window: glfw.WindowHandle, ok: bool) {
    // We initialize GLFW and create a window with it.
    ensure(bool(glfw.Init()), "Failed to initialize GLFW")

    glfw.SetErrorCallback(glfw_error_callback)

    runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
    c_title := strings.clone_to_cstring(title, context.temp_allocator)

    // We specify that the window created by GLFW should not be associated with any specific
    // client API, such as OpenGL or OpenGL ES. This is particularly important when targeting
    // Vulkan.
    glfw.WindowHint(glfw.CLIENT_API, glfw.NO_API)

    window = glfw.CreateWindow(i32(width), i32(height), c_title, nil, nil)
    if window == nil {
        log.error("Failed to create a Window")
        return
    }

    return window, true
}

destroy_window :: proc(window: glfw.WindowHandle) {
    glfw.DestroyWindow(window)
    glfw.Terminate()
}

// -----------------------------------------------------------------------------
// Callbacks
// -----------------------------------------------------------------------------

callback_framebuffer_size :: proc "c" (window: glfw.WindowHandle, width, height: i32) {
    // TODO: Implement later
}

callback_window_minimize :: proc "c" (window: glfw.WindowHandle, iconified: i32) {
    // Get the engine from the window user pointer
    engine := cast(^Engine)glfw.GetWindowUserPointer(window)
    engine.stop_rendering = bool(iconified) // Flag to not draw if we are minimized
}
```

### The Engine

Finally, we get into `engine.odin`, the main file:

```odin
package vk_guide

// Core
import "core:log"

// Vendor
import "vendor:glfw"
import vk "vendor:vulkan"

TITLE :: "0. Project Setup"
DEFAULT_WINDOW_EXTENT :: vk.Extent2D{800, 600} // Default window size in pixels

Engine :: struct {
    // Platform
    window:         glfw.WindowHandle,
    window_extent:  vk.Extent2D,
    is_initialized: bool,
    stop_rendering: bool,
}

@(private)
g_logger: log.Logger

// Initializes everything in the engine.
@(require_results)
engine_init :: proc(self: ^Engine) -> (ok: bool) {
    ensure(self != nil, "Invalid 'Engine' object")

    // Store the current logger for later use inside callbacks
    g_logger = context.logger

    self.window_extent = DEFAULT_WINDOW_EXTENT

    // Create a window using GLFW
    self.window = create_window(
        TITLE,
        self.window_extent.width,
        self.window_extent.height,
    ) or_return
    defer if !ok {
        destroy_window(self.window)
    }

    // Set the window user pointer so we can get the engine from callbacks
    glfw.SetWindowUserPointer(self.window, self)

    // Set window callbacks
    glfw.SetFramebufferSizeCallback(self.window, callback_framebuffer_size)
    glfw.SetWindowIconifyCallback(self.window, callback_window_minimize)

    // Everything went fine
    self.is_initialized = true

    return true
}
```

:::info[Global logger]

We created a global logger (`g_logger`) that will be used in callbacks that are outside of
Odin context.

:::

After initializing GLFW, we create a window and store it in the `window` field for later use.
The window's width and height are stored in the `window_extent` field, which is of type
`vk.Extent2D`.

When a window is created, it also has to be destroyed.

```odin title="tutorial/00_project_setup/engine.odin"
// Shuts down the engine.
engine_cleanup :: proc(self: ^Engine) {
    if !self.is_initialized {
        return
    }

    destroy_window(self.window)
}
```

```odin title="tutorial/00_project_setup/platform.odin"
destroy_window :: proc(window: glfw.WindowHandle) {
    glfw.DestroyWindow(window)
    glfw.Terminate()
}
```

In a similar way that we did `glfw.CreateWindow`, we need to do `glfw.DestroyWindow`. This will
destroy the window for the program. You also need to call `glfw.Terminate` to destroy any
remaining windows and releases any other resources allocated by GLFW.

Over time, we will add more logic into the `engine_cleanup` procedure.

```odin
// Draw loop.
@(require_results)
engine_draw :: proc(self: ^Engine) -> (ok: bool) {
    // Nothing yet
    return true
}
```

Our `engine_draw` procedure is empty for now, but here is where we will add the rendering code.

```odin
// Run main loop.
@(require_results)
engine_run :: proc(self: ^Engine) -> (ok: bool) {
    log.info("Entering main loop...")

    loop: for !glfw.WindowShouldClose(self.window) {
        glfw.PollEvents()

        // Do not draw if we are minimized
        if self.stop_rendering {
            glfw.WaitEvents() // Wait to avoid endless spinning
            continue
        }

        engine_draw(self) or_return
    }

    log.info("Exiting...")

    return true
}
```

This is our application main loop. We have an endless loop in the `loop: for`, that is only
stopped when `glfw.WindowShouldClose` returns a **close flag**, for example by clicking the
close widget or using a key chord like Alt+F4, the **close flag** of the window is set.

On every iteration of the inner loop, we do `glfw.PollEvents()`. This will process all of the
events the OS has sent to the application during the last frame. Processing events will cause
the window and input **callbacks** associated with those events to be called, things like
keyboard events, mouse movement, window moving, minimization, and many others.

```odin title="tutorial/00_project_setup/engine.odin (engine_init)"
// Set window callbacks
glfw.SetFramebufferSizeCallback(self.window, size_callback)
glfw.SetWindowIconifyCallback(self.window, iconify_callback)
```

We set some of those callbacks in the `engine_init` procedure.

```odin title="tutorial/00_project_setup/platform.odin"
callback_window_minimize :: proc "c" (window: glfw.WindowHandle, iconified: i32) {
    // Get the engine from the window user pointer
    engine := cast(^Engine)glfw.GetWindowUserPointer(window)
    engine.stop_rendering = bool(iconified) // Flag to not draw if we are minimized
}
```

When we receive the event that makes the window minimized, we set the `stop_rendering` bool to
the `iconified` state, if `true`, we avoid drawing when the window is minimized. Restoring the
window will set it back to `false`, which lets it continue drawing.

And finally, every iteration of the main loop we call either `engine_draw()`;, or
`glfw.WaitEvents` if drawing is disabled. This way we save performance as we dont want the
application spinning at full speed if the user has it minimized.

We now have seen how to open a window with GLFW, and basically not much else.

There is really only one thing that can be added to this at this point, and that is
experimenting with the GLFW callbacks.

As an exercise, read the documentation of GLFW 3.4 and try to set the key callback, use
`log.info` to log them.

Now we can move forward to the first chapter, and get a render loop going.

[Tracking allocator]: https://odin-lang.org/docs/overview/#tracking-allocator
