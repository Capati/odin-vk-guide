---
sidebar_position: 2
sidebar_label: "Vulkan Initialization Code"
---

# Initializing core Vulkan structures

:::warning[Starting point]

The explanations assume that you start from the code of `00_project_setup`. If you don’t have
the project setup, please grab the code of `00_project_setup` and compile it.

:::

The first thing to do, is to `import` the `odin-vk-bootstrap` library that we will be using to
simplify the initialization code. For that, go to the top of `engine.main`, and just import the
`odin-vk-bootstrap` package from the `libs` folder:

```odin title="engine.odin"
// --- other imports ---

// Vendor
import "vendor:glfw"
import vk "vendor:vulkan"

// Local packages
import "libs:vkb" // < here
```

`odin-vk-bootstrap` will remove hundreds of lines of code from our engine, simplifying the
startup code by a considerable amount. If you want to learn how to do that yourself without
vkbootstrap, you can try reading the first chapter of vulkan-tutorial
[here](https://vulkan-tutorial.com/Drawing_a_triangle/Setup/Base_code).

The first thing we are need to initialize is the Vulkan instance. For that, let's start by
adding the stored handles to the `Engine` object:

```odin title="engine.odin"
Engine :: struct {
    // ...

    // GPU Context
    vk_instance:        vk.Instance,
    vk_physical_device: vk.PhysicalDevice,
    vk_surface:         vk.SurfaceKHR,
    vk_device:          vk.Device,

    // vk-bootstrap
    vkb:                struct {
        instance:        vkb.Instance,
        physical_device: vkb.Physical_Device,
        device:          vkb.Device,
        swapchain:       vkb.Swapchain,
    },
}
```

We have added 4 handles, `vk.Instance`, `vk.PhysicalDevice`, `vk.SurfaceKHR` and `vk.Device`.
We are also storing the `vkb` handles.

Now lets also add some extra procedures to the engine file for the different stages of
initialization. We will call those init procedures in order from our `engine_init` procedure.

```odin title="engine.odin"
// Initializes everything in the engine.
engine_init :: proc(self: ^Engine) -> (ok: bool) {
    // Other code ---

    // Set window callbacks
    glfw.SetFramebufferSizeCallback(self.window, callback_framebuffer_size)
    glfw.SetWindowIconifyCallback(self.window, callback_window_minimize)

    // highlight-start
    engine_init_vulkan(self) or_return
    engine_init_swapchain(self) or_return
    engine_init_commands(self) or_return
    engine_init_sync_structures(self) or_return
    // highlight-end

    // Everything went fine
    self.is_initialized = true

    return true
}

engine_init_vulkan :: proc(self: ^Engine) -> (ok: bool) {
    return true
}

engine_init_swapchain :: proc(self: ^Engine) -> (ok: bool) {
    return true
}

engine_init_commands :: proc(self: ^Engine) -> (ok: bool) {
    return true
}

engine_init_sync_structures :: proc(self: ^Engine) -> (ok: bool) {
    return true
}
```

## Instance

Now that our new `engine_init_vulkan` procedure is added, we can start filling it with the code
needed to create the instance.

```odin
import "base:runtime" // import at the top

engine_init_vulkan :: proc(self: ^Engine) -> (ok: bool) {
    ta := context.temp_allocator
    runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()

    // Make the vulkan instance, with basic debug features
    instance_builder: vkb.Instance_Builder
    vkb.instance_builder_init(&instance_builder, ta)

    vkb.instance_builder_set_app_name(&instance_builder, "Example Vulkan Application")
    vkb.instance_builder_require_api_version(&instance_builder, vk.API_VERSION_1_3)

    when ODIN_DEBUG {
        vkb.instance_builder_request_validation_layers(&instance_builder)

        default_debug_callback :: proc "system" (
            message_severity: vk.DebugUtilsMessageSeverityFlagsEXT,
            message_types: vk.DebugUtilsMessageTypeFlagsEXT,
            p_callback_data: ^vk.DebugUtilsMessengerCallbackDataEXT,
            p_user_data: rawptr,
        ) -> b32 {
            context = runtime.default_context()
            context.logger = g_logger

            if .WARNING in message_severity {
                log.warnf("[%v]: %s", message_types, p_callback_data.pMessage)
            } else if .ERROR in message_severity {
                log.errorf("[%v]: %s", message_types, p_callback_data.pMessage)
                runtime.debug_trap()
            } else {
                log.infof("[%v]: %s", message_types, p_callback_data.pMessage)
            }

            return false // Applications must return false here
        }

        vkb.instance_builder_set_debug_callback(&instance_builder, default_debug_callback)
        vkb.instance_builder_set_debug_callback_user_data_pointer(&instance_builder, self)

        VK_LAYER_LUNARG_MONITOR :: "VK_LAYER_LUNARG_monitor"

        info: vkb.System_Info
        info_err := vkb.system_info_init(&info, allocator = ta)
        if info_err != nil {
            log.errorf("Failed to get system info: %#v", info_err)
            return
        }

        if vkb.system_info_is_layer_available(info, VK_LAYER_LUNARG_MONITOR) {
            // Displays FPS in the application's title bar. It is only compatible
            // with the Win32 and XCB windowing systems.
            // https://vulkan.lunarg.com/doc/sdk/latest/windows/monitor_layer.html
            when ODIN_OS == .Windows || ODIN_OS == .Linux {
                vkb.instance_builder_enable_layer(&instance_builder, VK_LAYER_LUNARG_MONITOR)
            }
        }
    }

    // Grab the instance
    vkb_instance_err := vkb.instance_builder_build(&instance_builder, &self.vkb.instance)
    if vkb_instance_err != nil {
        log.errorf("Failed to build instance: %#v", vkb_instance_err)
        return
    }
    defer if !ok {
        vkb.destroy_instance(&self.vkb.instance)
    }

    self.vk_instance = self.vkb.instance.vk_instance

    return true
}
```

We are going to create a `vkb.InstanceBuilder`, which is from the `vkb` package, and abstracts
the creation of a Vulkan `vk.Instance`.

:::info[Temporary allocator]

We use `context.temp_allocator` for temporary `vkb` builders that do not need to outlive the
current procedure. `DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD` ensures that any temporary allocations
made within the procedure are automatically freed when the scope exits.

:::

For the creation of the instance, we want it to have the name "Example Vulkan Application",
have validation layers enabled, and use default debug logger. The "Example Vulkan Application"
name does not matter. You can set the name to whatever you want. When initializing a
`vk.Instance`, the name of the application and engine is supplied. This is so that driver
vendors have a easier time finding the name of the game/engine, so they can tweak internal
driver logic for them alone. For us, it's not really important.

We want to enable validation layers by default, with what we are going to do during the guide
in debug mode. Vulkan validation layers can slow down the performance of the vulkan calls
significantly, so once we begin loading complex scenes with lots of data, we will want to
disable them by omitting the `-debug` build flag to see what the real performance of the code
is.

We also require the Vulkan api version 1.3. This should be supported on gpus that are
relatively modern. We will be taking advantage of the features given by that vulkan version. If
you are on a old PC/gpu that does not support those features, then you will have to follow the
older version of this guide, which targets 1.1.

Lastly, inside `ODIN_DEBUG`, we configure Vulkan debugging features:

1. **Validation Layers**

    - `vkb.instance_builder_request_validation_layers` enables Vulkan validation layers
    - These layers perform runtime checks on Vulkan API usage, catching errors and potential issues

2. **Debug Messenger Callback**

    - Defines `default_debug_callback`, a custom procedure to handle debug messages
    - Message handling based on severity:
        - `.WARNING`: Logs warnings using `log.warnf`
        - `.ERROR`: Logs errors using `log.errorf` and triggers `runtime.debug_trap()` to pause
          execution. The debugger will catch the error thrown and you can move up the call
          stack to whatever procedure caused the error
        - Other (typically `.INFO` or `.VERBOSE`): Logs using `log.infof`
    - Logs include message type and content from `p_callback_data.pMessage`
    - Configured via:
        - `vkb.instance_builder_set_debug_callback`: Sets our callback procedure
        - `vkb.instance_builder_set_debug_callback_user_data_pointer`: Passes `self`
          (our engine) as user data
    - Returns `false` as required by Vulkan specification for debug callbacks

Next, we retrieve the `vk.Instance` handle from the `vkb.Instance` and store it in our `Engine`
structure.

## Physical Device

```odin title="engine.odin"
engine_init_vulkan :: proc(self: ^Engine) -> (ok: bool) {
    // other code ------

    // Surface
    vk_check(
        glfw.CreateWindowSurface(self.vk_instance, self.window, nil, &self.vk_surface),
    ) or_return
    defer if !ok {
        vkb.destroy_surface(&self.vkb.instance, self.vk_surface)
    }

    // Vulkan 1.1 features
    features_11 := vk.PhysicalDeviceVulkan11Features {
        shaderDrawParameters = true,
    }

    // Vulkan 1.2 features
    features_12 := vk.PhysicalDeviceVulkan12Features {
        // Allows shaders to directly access buffer memory using GPU addresses
        bufferDeviceAddress = true,
        // Enables dynamic indexing of descriptors and more flexible descriptor usage
        descriptorIndexing  = true,
    }

    // Vulkan 1.3 features
    features_13 := vk.PhysicalDeviceVulkan13Features {
        // Eliminates the need for render pass objects, simplifying rendering setup
        dynamicRendering = true,
        // Provides improved synchronization primitives with simpler usage patterns
        synchronization2 = true,
    }

    // Use vk-bootstrap to select a gpu.
    // We want a gpu that can write to the GLFW surface and supports vulkan 1.3
    // with the correct features
    selector: vkb.Physical_Device_Selector
    vkb.physical_device_selector_init(&selector, self.vkb.instance, ta)

    vkb.physical_device_selector_set_minimum_version(&selector, vk.API_VERSION_1_3)
    vkb.physical_device_selector_set_required_features_13(&selector, features_13)
    vkb.physical_device_selector_set_required_features_12(&selector, features_12)
    vkb.physical_device_selector_set_required_features_11(&selector, features_11)
    vkb.physical_device_selector_set_surface(&selector, self.vk_surface)

    vkb_physical_device_err := vkb.physical_device_selector_select(
        &selector, &self.vkb.physical_device)
    if vkb_physical_device_err != nil {
        log.errorf("Failed to select physical device: %#v", vkb_physical_device_err)
        return
    }
    defer if !ok {
        vkb.destroy_physical_device(&self.vkb.physical_device)
    }

    self.vk_physical_device = self.vkb.physical_device.vk_physical_device

    // Create the final vulkan device
    device_builder: vkb.Device_Builder
    vkb.device_builder_init(&device_builder, ta)

    vkb_device_err := vkb.device_builder_build(
        &device_builder, &self.vkb.physical_device, &self.vkb.device)
    if vkb_device_err != nil {
        log.errorf("Failed to get logical device: %#v", vkb_device_err)
        return
    }
    defer if !ok {
        vkb.destroy_device(&self.vkb.device)
    }

    self.vk_device = self.vkb.device.vk_device

    return true
}
```

To select a GPU to use, we are going to use `vkb.Physical_Device_Selector`.

First of all, we need to create a `vk.SurfaceKHR` object from the GLFW window. This is the
actual window we will be rendering to, so we need to tell the physical device selector to grab
a GPU that can render to said window.

We're enabling several important Vulkan features:

- **Vulkan 1.2 features**
  - `bufferDeviceAddress`: Allows our shaders to directly access buffer memory using GPU
    addresses without binding buffers explicitly.
  - `descriptorIndexing`: Enables bindless textures and more flexible descriptor access
    patterns.

- **Vulkan 1.3 features**
  - `dynamicRendering`: Eliminates the need for render pass/framebuffer objects, simplifying
    our rendering setup.
  - `synchronization2`: Provides improved synchronization primitives with simpler usage
    patterns.

Those are optional features provided in vulkan 1.3 that change a few things. dynamic rendering
allows us to completely skip renderpasses/framebuffers (if you want to learn about them, they
are explained in the old version of vkguide), and also use a new upgraded version of the
syncronization procedures. We are also going to use the vulkan 1.2 features
`bufferDeviceAddress` and `descriptorIndexing`. Buffer device adress will let us use GPU
pointers without binding buffers, and descriptorIndexing gives us bindless textures.

By giving the `vkb.Physical_Device_Selector` the `vk.PhysicalDeviceVulkan13Features` structure,
we can tell `vkb` to find a gpu that has those features.

There are multiple levels of feature structs you can use depending on your vulkan version, you
can find their info here:

- [Vulkan Spec: 1.0 physical device features](https://registry.khronos.org/vulkan/specs/1.3-extensions/html/chap47.html#VkPhysicalDeviceFeatures)
- [Vulkan Spec: 1.1 physical device features](https://registry.khronos.org/vulkan/specs/1.3-extensions/html/chap47.html#VkPhysicalDeviceVulkan11Features)
- [Vulkan Spec: 1.2 physical device features](https://registry.khronos.org/vulkan/specs/1.3-extensions/html/chap47.html#VkPhysicalDeviceVulkan12Features)
- [Vulkan Spec: 1.3 physical device features](https://registry.khronos.org/vulkan/specs/1.3-extensions/html/chap47.html#VkPhysicalDeviceVulkan13Features)

Once we have a `vk.PhysicalDevice`, we can directly build a `vk.Device` from it.

That's it, we have initialized Vulkan. We can now start calling Vulkan commands.

If you run the project right now, it will crash if you dont have a gpu with the required
features or vulkan drivers that dont support them. If that happens, make sure your drivers are
updated.

## Setting Up The Swapchain

Last thing from the core initialization is to initialize the swapchain, so we can have
something to render into.

Begin by adding new fields and procedures.

```odin title="engine.odin"
Engine :: struct {
    // ...

    // Swapchain
    vk_swapchain:          vk.SwapchainKHR,
    swapchain_format:      vk.Format,
    swapchain_extent:      vk.Extent2D,
    swapchain_images:      []vk.Image,
    swapchain_image_views: []vk.ImageView,
}

engine_create_swapchain :: proc(self: ^Engine, extent: vk.Extent2D) -> (ok: bool) {
  return true
}

engine_destroy_swapchain :: proc(self: ^Engine) {
}
```

We are storing the `vk.SwapchainKHR` itself, alongside the format and extent that the swapchain
images use when rendering to them.

We also store 2 arrays, one of `Image`s, and another of `ImageView`s.

A `vk.Image` is a handle to the actual image object to use as texture or to render into. A
`vk.ImageView` is a wrapper for that image. It allows to do things like swap the colors. We
will go into detail about it later.

We are also adding create and destroy procedures for the swapchain.

Like with the other initialization procedures, we are going to use the `vkb` library to create
a swapchain. It uses a builder similar to the ones we used for instance and device.

```odin title="engine.odin"
engine_create_swapchain :: proc(self: ^Engine, extent: vk.Extent2D) -> (ok: bool) {
    ta := context.temp_allocator
    runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()

    self.swapchain_format = .B8G8R8A8_UNORM

    builder: vkb.Swapchain_Builder
    vkb.swapchain_builder_init(&builder, self.vkb.device, ta)

    vkb.swapchain_builder_set_desired_format(&builder,
        {format = self.swapchain_format, colorSpace = .SRGB_NONLINEAR},
    )
    vkb.swapchain_builder_set_desired_present_mode(&builder, .FIFO)
    vkb.swapchain_builder_set_desired_extent(&builder, extent.width, extent.height)
    vkb.swapchain_builder_add_image_usage_flags(&builder, {.TRANSFER_DST})

    swapchain_err := vkb.swapchain_builder_build(&builder, &self.vkb.swapchain)
    if swapchain_err != nil {
        log.errorf("Failed to build swapchain: %#v", swapchain_err)
        return
    }

    self.vk_swapchain = self.vkb.swapchain.vk_swapchain
    self.swapchain_extent = self.vkb.swapchain.vk_extent

    swapchain_images, swapchain_images_err :=
        vkb.swapchain_get_images(self.vkb.swapchain)
    if swapchain_images_err != nil {
        log.errorf("Failed to get swapchain images: %#v", swapchain_images_err)
        return
    }
    swapchain_image_views, swapchain_image_views_err :=
        vkb.swapchain_get_image_views(self.vkb.swapchain)
    if swapchain_image_views_err != nil {
        log.errorf("Failed to get swapchain image views: %#v", swapchain_image_views_err)
        return
    }

    self.swapchain_images = swapchain_images
    self.swapchain_image_views = swapchain_image_views

    return true
}

engine_init_swapchain :: proc(self: ^Engine) -> (ok: bool) {
    engine_create_swapchain(self, self.window_extent) or_return
    return true
}
```

From `engine_create_swapchain`, we make the swapchain structures, and then we call the
procedure from `engine_init_swapchain()`

The most important detail here is the present mode, which we have set to `FIFO`. This way we
are doing a hard VSync, which will limit the FPS of the entire engine to the speed of the
monitor.

We also send the window sizes (`window_extent`) to the swapchain. This is important as creating
a swapchain will also create the images for it, so the size is locked. Later in the tutorial we
will need to rebuild the swapchain as the window resizes, so we have them separated from the
init flow, but in the init flow we default that size to the window size.

Once the swapchain is built, we just store all of its stuff into the fields of `Engine`
structure.

Lets write the `engine_destroy_swapchain()` procedure too.

```odin title="engine.odin"
engine_destroy_swapchain :: proc(self: ^Engine) {
    vkb.swapchain_destroy_image_views(self.vkb.swapchain, self.swapchain_image_views)
    vkb.destroy_swapchain(&self.vkb.swapchain)
    delete(self.swapchain_image_views)
    delete(self.swapchain_images)
}
```

We first delete the swapchain object, which will delete the images it holds internally. We then
have to destroy the ImageViews for those images. We also free the memory allocated for the
slices.

## Cleaning Up Resources

We need to make sure that all of the Vulkan resources we create are correctly deleted, when the
app exists.

For that, go to the `engine_cleanup()` procedure.

```odin title="engine.odin"
engine_cleanup :: proc(self: ^Engine) {
    if !self.is_initialized {
        return
    }

    engine_destroy_swapchain(self)

    vk.DestroySurfaceKHR(self.vk_instance, self.vk_surface, nil)
    vkb.destroy_device(&self.vkb.device)

    vkb.destroy_physical_device(&self.vkb.physical_device)
    vkb.destroy_instance(&self.vkb.instance)

    destroy_window(self.window)
}
```

Objects have dependencies on each other, and we need to delete them in the correct order.
Deleting them in the opposite order they were created is a good way of doing it. In some cases,
if you know what you are doing, the order can be changed a bit and it will be fine.

`vk.PhysicalDevice` can't be destroyed, as it's not a Vulkan resource per-se, it's more like
just a handle to a GPU in the system. But here you need to free some resources when the
physical device was created by `vkb`. We are also using `vkb` to destroy the device and
instance, this will destroy the vulkan handle and free `vkb` resources.

Because our initialization order was GLFW Window -> Instance -> Surface -> Device -> Swapchain,
we are doing exactly the opposite order for destruction.

If you try to run the program now, it should do nothing, but that nothing also includes not
emitting errors.

There is no need to destroy the Images in this specific case, because the images are owned and
destroyed with the swapchain.

## Validation Layer Errors

Just to check that our validation layers are working, let's try to call the destruction
procedures in the wrong order.

```odin title="engine.odin" {6,7}
engine_cleanup :: proc(self: ^Engine) {
    if !self.is_initialized {
        return
    }

    // ERROR - Instance destroyed before others
    vkb.destroy_instance(self.vkb.instance)

    engine_destroy_swapchain(self)

    vk.DestroySurfaceKHR(self.vk_instance, self.vk_surface, nil)
    vkb.destroy_device(self.vkb.device)

    vkb.destroy_physical_device(self.vkb.physical_device)

    destroy_window(self.window)
}
```

We are now destroying the Instance before the Device and the Surface (which was created from
the Instance) is also deleted. The validation layers should complain with an error like this.

```text
[ERROR: Validation]
Validation Error: [ VUID-vkDestroyInstance-instance-00629 ] Object 0: handle = 0x24ff02340c0, type = VK_OBJECT_TYPE_INSTANCE; Object 1: handle = 0xf8ce070000000002, type = VK_OBJECT_TYPE_SURFACE_KHR; | MessageID = 0x8b3d8e18 | OBJ ERROR : For VkInstance 0x24ff02340c0[], VkSurfaceKHR 0xf8ce070000000002[] has not been destroyed. The Vulkan spec states: All child objects created using instance must have been destroyed prior to destroying instance (https://www.khronos.org/registry/vulkan/specs/1.1-extensions/html/vkspec.html#VUID-vkDestroyInstance-instance-00629)
```

With the Vulkan initialization completed and the layers working, we can begin to prepare the
command structures so that we can make the gpu do something.
