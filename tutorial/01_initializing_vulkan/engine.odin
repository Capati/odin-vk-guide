package vk_guide

// Core
import "base:runtime"
import "core:log"
import "core:math"

// Vendor
import "vendor:glfw"
import vk "vendor:vulkan"

// Local packages
import "libs:vkb"

TITLE :: "0. Project Setup"
DEFAULT_WINDOW_EXTENT :: vk.Extent2D{1280, 678} // Default window size in pixels

Frame_Data :: struct {
    command_pool:        vk.CommandPool,
    main_command_buffer: vk.CommandBuffer,
    swapchain_semaphore: vk.Semaphore,
    render_fence:        vk.Fence,
}

FRAME_OVERLAP :: 2

Engine :: struct {
    // Platform
    window:                     glfw.WindowHandle,
    window_extent:              vk.Extent2D,
    is_initialized:             bool,
    stop_rendering:             bool,

    // GPU Context
    vk_instance:                vk.Instance,
    vk_physical_device:         vk.PhysicalDevice,
    vk_surface:                 vk.SurfaceKHR,
    vk_device:                  vk.Device,

    // vk-bootstrap
    vkb:                        struct {
        instance:        vkb.Instance,
        physical_device: vkb.Physical_Device,
        device:          vkb.Device,
        swapchain:       vkb.Swapchain,
    },

    // Swapchain
    vk_swapchain:               vk.SwapchainKHR,
    swapchain_format:           vk.Format,
    swapchain_extent:           vk.Extent2D,
    swapchain_images:           []vk.Image,
    swapchain_image_views:      []vk.ImageView,
    swapchain_image_semaphores: []vk.Semaphore,

    // Frame resources
    frames:                     [FRAME_OVERLAP]Frame_Data,
    frame_number:               int,
    graphics_queue:             vk.Queue,
    graphics_queue_family:      u32,
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

    engine_init_vulkan(self) or_return
    engine_init_swapchain(self) or_return
    engine_init_commands(self) or_return
    engine_init_sync_structures(self) or_return

    // Everything went fine
    self.is_initialized = true

    return true
}

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

    // use vk-bootstrap to get a Graphics queue
    graphics_queue, graphics_queue_err :=
        vkb.device_get_queue(self.vkb.device, .Graphics)
    if graphics_queue_err != nil {
        log.errorf("Failed to get graphics queue: %#v", graphics_queue_err)
        return
    }
    graphics_queue_family, graphics_queue_family_err :=
        vkb.device_get_queue_index(self.vkb.device, .Graphics)
    if graphics_queue_family_err != nil {
        log.errorf("Failed to get graphics queue family: %#v", graphics_queue_family_err)
        return
    }

    self.graphics_queue = graphics_queue
    self.graphics_queue_family = graphics_queue_family

    // Give every swapchain image its own dedicated semaphore.
    //
    // Since a given image can't be re-acquired until the presentation engine is
    // done with the previous present of that same image
    self.swapchain_image_semaphores = make([]vk.Semaphore, len(self.swapchain_images))[:]
    defer if !ok {delete(self.swapchain_image_semaphores)}

    // These need to be created here so that they are recreated when we resize.
    semaphore_create_info := semaphore_create_info()
    for &semaphore in self.swapchain_image_semaphores {
        vk_check(vk.CreateSemaphore(
            self.vk_device, &semaphore_create_info, nil, &semaphore)) or_return
    }

    return true
}

engine_destroy_swapchain :: proc(self: ^Engine) {
    vkb.destroy_swapchain(&self.vkb.swapchain)
    vkb.swapchain_destroy_image_views(self.vkb.swapchain, self.swapchain_image_views)

    for semaphore in self.swapchain_image_semaphores {
        vk.DestroySemaphore(self.vk_device, semaphore, nil)
    }

    delete(self.swapchain_image_semaphores)
    delete(self.swapchain_image_views)
    delete(self.swapchain_images)
}

engine_init_swapchain :: proc(self: ^Engine) -> (ok: bool) {
    engine_create_swapchain(self, self.window_extent) or_return
    return true
}

engine_init_commands :: proc(self: ^Engine) -> (ok: bool) {
    // Create a command pool for commands submitted to the graphics queue.
    // We also want the pool to allow for resetting of individual command buffers.
    command_pool_info := command_pool_create_info(
        self.graphics_queue_family,
        {.RESET_COMMAND_BUFFER},
    )

    for &frame in self.frames {
        // Create the command pool
        vk_check(vk.CreateCommandPool(
            self.vk_device, &command_pool_info, nil, &frame.command_pool)) or_return

        // Allocate the default command buffer that we will use for rendering
        cmd_alloc_info := command_buffer_allocate_info(frame.command_pool)

        vk_check(vk.AllocateCommandBuffers(
            self.vk_device, &cmd_alloc_info, &frame.main_command_buffer)) or_return
    }

    return true
}

@(require_results)
engine_init_sync_structures :: proc(self: ^Engine) -> (ok: bool) {
    // Create synchronization structures, one fence to control when the gpu has
    // finished rendering the frame, and a semaphore to synchronize rendering
    // with swapchain. We want the fence to start signaled so we can wait on it
    // on the first frame.
    fence_create_info := fence_create_info({.SIGNALED})
    semaphore_create_info := semaphore_create_info()

    for &frame in self.frames {
        vk_check(vk.CreateFence(
            self.vk_device, &fence_create_info, nil, &frame.render_fence)) or_return

        vk_check(vk.CreateSemaphore(
            self.vk_device, &semaphore_create_info, nil, &frame.swapchain_semaphore)) or_return
    }

    return true
}

engine_get_current_frame :: #force_inline proc(self: ^Engine) -> ^Frame_Data #no_bounds_check {
    return &self.frames[self.frame_number % FRAME_OVERLAP]
}

// Shuts down the engine.
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
    }

    engine_destroy_swapchain(self)

    vk.DestroySurfaceKHR(self.vk_instance, self.vk_surface, nil)
    vkb.destroy_device(&self.vkb.device)

    vkb.destroy_physical_device(&self.vkb.physical_device)
    vkb.destroy_instance(&self.vkb.instance)

    destroy_window(self.window)
}

// Draw loop.
@(require_results)
engine_draw :: proc(self: ^Engine) -> (ok: bool) {
    // Steps:
    //
    // 1. Waits for the GPU to finish the previous frame
    // 2. Acquires the next swapchain image
    // 3. Records rendering commands into a command buffer
    // 4. Submits the command buffer to the GPU for execution
    // 5. Presents the rendered image to the screen

    frame := engine_get_current_frame(self)

    // Wait until the gpu has finished rendering the last frame. Timeout of 1 second
    vk_check(vk.WaitForFences(self.vk_device, 1, &frame.render_fence, true, 1e9)) or_return
    vk_check(vk.ResetFences(self.vk_device, 1, &frame.render_fence)) or_return

    // Request image from the swapchain
    swapchain_image_index: u32 = ---
    vk_check(
        vk.AcquireNextImageKHR(
            self.vk_device,
            self.vk_swapchain,
            1000000000,
            frame.swapchain_semaphore,
            0,
            &swapchain_image_index,
        ),
    ) or_return

    // The the current command buffer, naming it cmd for shorter writing
    cmd := frame.main_command_buffer

    // Now that we are sure that the commands finished executing, we can safely reset the
    // command buffer to begin recording again.
    vk_check(vk.ResetCommandBuffer(cmd, {})) or_return

    // Begin the command buffer recording. We will use this command buffer exactly once, so we
    // want to let vulkan know that
    cmd_begin_info := command_buffer_begin_info({.ONE_TIME_SUBMIT})

    // Start the command buffer recording
    vk_check(vk.BeginCommandBuffer(cmd, &cmd_begin_info)) or_return

    // Make the swapchain image into writeable mode before rendering
    transition_image(cmd, self.swapchain_images[swapchain_image_index], .UNDEFINED, .GENERAL)

    // Make a clear-color from frame number. This will flash with a 120 frame period.
    flash := abs(math.sin(f32(self.frame_number) / 120.0))
    clear_value := vk.ClearColorValue {
        float32 = {0.0, 0.0, flash, 1.0},
    }

    clear_range := image_subresource_range({.COLOR})

    // Clear image
    vk.CmdClearColorImage(
        cmd,
        self.swapchain_images[swapchain_image_index],
        .GENERAL,
        &clear_value,
        1,
        &clear_range,
    )

    // Make the swapchain image into presentable mode
    transition_image(
        cmd,
        self.swapchain_images[swapchain_image_index],
        .GENERAL,
        .PRESENT_SRC_KHR,
    )

    // Finalize the command buffer (we can no longer add commands, but it can now be executed)
    vk_check(vk.EndCommandBuffer(cmd)) or_return

    // Prepare the submission to the queue. we want to wait on the
    // `swapchain_semaphore`, as that semaphore is signaled when the swapchain is
    // ready. We will signal the `ready_for_present_semaphore`, to signal that
    // rendering has finished.

    ready_for_present_semaphore := self.swapchain_image_semaphores[swapchain_image_index]

    cmd_info := command_buffer_submit_info(cmd)
    signal_info := semaphore_submit_info({.ALL_GRAPHICS}, ready_for_present_semaphore)
    wait_info := semaphore_submit_info({.COLOR_ATTACHMENT_OUTPUT_KHR}, frame.swapchain_semaphore)

    submit := submit_info(&cmd_info, &signal_info, &wait_info)

    // Submit command buffer to the queue and execute it. `render_fence` will now
    // block until the graphic commands finish execution.
    vk_check(vk.QueueSubmit2(self.graphics_queue, 1, &submit, frame.render_fence)) or_return

    // Prepare present
    //
    // This will put the image we just rendered to into the visible window. we want to wait on
    // the `ready_for_present_semaphore` for that, as its necessary that drawing commands
    // have finished before the image is displayed to the user.
    present_info := vk.PresentInfoKHR {
        sType              = .PRESENT_INFO_KHR,
        pSwapchains        = &self.vk_swapchain,
        swapchainCount     = 1,
        pWaitSemaphores    = &ready_for_present_semaphore,
        waitSemaphoreCount = 1,
        pImageIndices      = &swapchain_image_index,
    }

    vk_check(vk.QueuePresentKHR(self.graphics_queue, &present_info)) or_return

    // Increase the number of frames drawn
    self.frame_number += 1

    return true
}

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
