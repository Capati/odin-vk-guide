package vk_guide

// Core
import "base:runtime"
import "core:log"

import la "core:math/linalg"

// Vendor
import "vendor:glfw"
import vk "vendor:vulkan"

// Local packages
import "libs:vkb"
import "libs:vma"
import im "libs:imgui"
import im_glfw "libs:imgui/backends/glfw"
import im_vk "libs:imgui/backends/vulkan"

// Initializes everything in the engine.
@(require_results)
engine_init :: proc(self: ^Engine) -> (ok: bool) {
    ensure(self != nil, "Invalid 'Engine' object")

    // Store the current logger for later use inside callbacks
    g_logger = context.logger

    self.window_extent = DEFAULT_WINDOW_EXTENT
    self.render_scale = 1.0

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
    engine_init_descriptors(self) or_return
    engine_init_pipelines(self) or_return
    engine_init_imgui(self) or_return
    engine_init_default_data(self) or_return

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

        info: vkb.System_Info
        info_err := vkb.system_info_init(&info, allocator = ta)
        if info_err != nil {
            log.errorf("Failed to get system info: %#v", info_err)
            return
        }

        // VK_LAYER_LUNARG_MONITOR :: "VK_LAYER_LUNARG_monitor"
        // if vkb.system_info_is_layer_available(info, VK_LAYER_LUNARG_MONITOR) {
        //     // Displays FPS in the application's title bar. It is only compatible
        //     // with the Win32 and XCB windowing systems.
        //     // https://vulkan.lunarg.com/doc/sdk/latest/windows/monitor_layer.html
        //     when ODIN_OS == .Windows || ODIN_OS == .Linux {
        //         vkb.instance_builder_enable_layer(&instance_builder, VK_LAYER_LUNARG_MONITOR)
        //     }
        // }
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

    // Initialize global deletion queue
    deletion_queue_init(&self.main_deletion_queue, self.vk_device)

    // Initializes a subset of Vulkan functions required by VMA
    vma_vulkan_functions := vma.create_vulkan_functions()

    api_version := min(
        self.vkb.instance.api_version,
        self.vkb.physical_device.vk_properties.apiVersion,
    )

    vma_create_info: vma.AllocatorCreateInfo = {
        flags            = { .BUFFER_DEVICE_ADDRESS },
        instance         = self.vk_instance,
        physicalDevice   = self.vk_physical_device,
        device           = self.vk_device,
        pVulkanFunctions = &vma_vulkan_functions,
        vulkanApiVersion = api_version,
    }

    // Create the VMA (Vulkan Memory Allocator)
    vk_check(vma.CreateAllocator(vma_create_info, &self.vma_allocator)) or_return

    deletion_queue_push(&self.main_deletion_queue, self.vma_allocator)

    return true
}

engine_resize_swapchain :: proc(self: ^Engine) -> (ok: bool) {
    vk_check(vk.DeviceWaitIdle(self.vk_device)) or_return

    width, height := glfw.GetFramebufferSize(self.window)
    self.window_extent = {u32(width), u32(height)}

    engine_create_swapchain(self, self.window_extent) or_return

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
    // vkb.swapchain_builder_set_desired_present_mode(&builder, .IMMEDIATE)
    // vkb.swapchain_builder_set_desired_present_mode(&builder, .MAILBOX)

    vkb.swapchain_builder_set_desired_extent(&builder, extent.width, extent.height)
    vkb.swapchain_builder_add_image_usage_flags(&builder, {.TRANSFER_DST})

    // If an existing swapchain is present, link it as the old swapchain
    if self.vkb.swapchain.vk_swapchain != {} {
        vkb.swapchain_builder_set_old_swapchain(&builder, self.vkb.swapchain)
    }

    vkb_swapchain: vkb.Swapchain
    swapchain_err := vkb.swapchain_builder_build(&builder, &vkb_swapchain)
    if swapchain_err != nil {
        log.errorf("Failed to build swapchain: %#v", swapchain_err)
        return
    }

    // If there was an old swapchain, destroy it after the new one is set
    if self.vkb.swapchain.vk_swapchain != {} {
        engine_destroy_swapchain(self)
    }

    self.vkb.swapchain = vkb_swapchain
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

    monitor_width, monitor_height := get_monitor_resolution()

    // Draw image size will match the monitor resolution
    draw_image_extent := vk.Extent3D {
        width  = monitor_width,
        height = monitor_height,
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
    rimg_allocinfo := vma.AllocationCreateInfo {
        usage         = .GPU_ONLY,
        requiredFlags = {.DEVICE_LOCAL},
    }

    // Allocate and create the image
    vk_check(vma.CreateImage(
        self.vma_allocator,
        rimg_info,
        rimg_allocinfo,
        &self.draw_image.image,
        &self.draw_image.allocation,
        nil,
    )) or_return
    defer if !ok {
        vma.DestroyImage(self.vma_allocator, self.draw_image.image, nil)
    }

    // Build a image-view for the draw image to use for rendering
    rview_info := imageview_create_info(
        self.draw_image.image_format,
        self.draw_image.image,
        {.COLOR},
    )

    vk_check(vk.CreateImageView(
        self.vk_device, &rview_info, nil, &self.draw_image.image_view)) or_return
    defer if !ok {
        vk.DestroyImageView(self.vk_device, self.draw_image.image_view, nil)
    }

    // Add to deletion queues
    deletion_queue_push(&self.main_deletion_queue, self.draw_image)

    self.depth_image.image_format = .D32_SFLOAT
    self.depth_image.image_extent = draw_image_extent
    self.depth_image.allocator = self.vma_allocator
    self.depth_image.device = self.vk_device

    depth_image_usages := vk.ImageUsageFlags{.DEPTH_STENCIL_ATTACHMENT}

    dimg_info := image_create_info(
        self.depth_image.image_format,
        depth_image_usages,
        draw_image_extent,
    )

    // Allocate and create the image
    vk_check(
        vma.CreateImage(
            self.vma_allocator,
            dimg_info,
            rimg_allocinfo,
            &self.depth_image.image,
            &self.depth_image.allocation,
            nil,
        ),
    ) or_return
    defer if !ok {
        vma.DestroyImage(self.vma_allocator, self.depth_image.image, nil)
    }

    // Build a image-view for the draw image to use for rendering
    dview_info := imageview_create_info(
        self.depth_image.image_format,
        self.depth_image.image,
        {.DEPTH},
    )

    vk_check(
        vk.CreateImageView(self.vk_device, &dview_info, nil, &self.depth_image.image_view),
    ) or_return
    defer if !ok {
        vk.DestroyImageView(self.vk_device, self.depth_image.image_view, nil)
    }

    // Add to deletion queues
    deletion_queue_push(&self.main_deletion_queue, self.depth_image)

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
        // Create peer frame deletion queue
        deletion_queue_init(&frame.deletion_queue, self.vk_device)

        // Create the command pool
        vk_check(vk.CreateCommandPool(
            self.vk_device, &command_pool_info, nil, &frame.command_pool)) or_return

        // Allocate the default command buffer that we will use for rendering
        cmd_alloc_info := command_buffer_allocate_info(frame.command_pool)

        vk_check(vk.AllocateCommandBuffers(
            self.vk_device, &cmd_alloc_info, &frame.main_command_buffer)) or_return
    }

    vk_check(vk.CreateCommandPool(
        self.vk_device, &command_pool_info, nil, &self.imm_command_pool)) or_return

    // Allocate the command buffer for immediate submits
    cmd_alloc_info := command_buffer_allocate_info(self.imm_command_pool)
    vk_check(vk.AllocateCommandBuffers(
        self.vk_device, &cmd_alloc_info, &self.imm_command_buffer)) or_return
    deletion_queue_push(&self.main_deletion_queue, self.imm_command_pool)

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

    vk_check(vk.CreateFence(
        self.vk_device, &fence_create_info, nil, &self.imm_fence)) or_return
    deletion_queue_push(&self.main_deletion_queue, self.imm_fence)

    return true
}

engine_init_descriptors :: proc(self: ^Engine) -> (ok: bool) {
    // Create a descriptor pool that will hold 10 sets with 1 image each
    sizes := []Pool_Size_Ratio {
        {.STORAGE_IMAGE, 1},
        {.UNIFORM_BUFFER, 1},
        {.COMBINED_IMAGE_SAMPLER, 2},
    }

    descriptor_allocator_init_pool(
        &self.global_descriptor_allocator, self.vk_device, 10, sizes) or_return
    deletion_queue_push(&self.main_deletion_queue, self.global_descriptor_allocator.pool)

    {
        // Make the descriptor set layout for our compute draw
        builder: Descriptor_Layout_Builder
        descriptor_layout_builder_init(&builder, self.vk_device)
        descriptor_layout_builder_add_binding(&builder, 0, .STORAGE_IMAGE)
        self.draw_image_descriptor_layout =
            descriptor_layout_builder_build(&builder, {.COMPUTE}) or_return
        deletion_queue_push(&self.main_deletion_queue, self.draw_image_descriptor_layout)
    }

    // Allocate a descriptor set for our draw image
    self.draw_image_descriptors = descriptor_allocator_allocate(
        &self.global_descriptor_allocator,
        self.vk_device,
        &self.draw_image_descriptor_layout,
    ) or_return

    writer: Descriptor_Writer
    descriptor_writer_init(&writer, self.vk_device)

    descriptor_writer_write_image(
        &writer,
        binding = 0,
        image = self.draw_image.image_view,
        sampler = 0,
        layout = .GENERAL,
        type = .STORAGE_IMAGE,
    )

    descriptor_writer_update_set(&writer, self.draw_image_descriptors)

    for &frame in self.frames {
        frame_sizes: Ratios
        append(&frame_sizes, Pool_Size_Ratio{.STORAGE_IMAGE, 3})
        append(&frame_sizes, Pool_Size_Ratio{.STORAGE_BUFFER, 3})
        append(&frame_sizes, Pool_Size_Ratio{.UNIFORM_BUFFER, 3})
        append(&frame_sizes, Pool_Size_Ratio{.COMBINED_IMAGE_SAMPLER, 4})

        descriptor_growable_init(
            &frame.frame_descriptors,
            self.vk_device,
            1000,
            frame_sizes[:],
        )

        deletion_queue_push(&self.main_deletion_queue, frame.frame_descriptors)
    }

    {
        builder: Descriptor_Layout_Builder
        descriptor_layout_builder_init(&builder, self.vk_device)
        descriptor_layout_builder_add_binding(&builder, 0, .UNIFORM_BUFFER)
        self.gpu_scene_data_descriptor_layout =
            descriptor_layout_builder_build(&builder, {.VERTEX, .FRAGMENT}) or_return
        deletion_queue_push(&self.main_deletion_queue, self.gpu_scene_data_descriptor_layout)
    }

    {
        builder: Descriptor_Layout_Builder
        descriptor_layout_builder_init(&builder, self.vk_device)
        descriptor_layout_builder_add_binding(&builder, 0, .COMBINED_IMAGE_SAMPLER)
        self.single_image_descriptor_layout =
            descriptor_layout_builder_build(&builder, {.FRAGMENT}) or_return
        deletion_queue_push(&self.main_deletion_queue, self.single_image_descriptor_layout)
    }

    return true
}

engine_init_background_pipelines :: proc(self: ^Engine) -> (ok: bool) {
    GRADIENT_COLOR_SPV :: #load("./../../shaders/compiled/gradient_color.comp.spv")
    gradient_color_shader := create_shader_module(self.vk_device, GRADIENT_COLOR_SPV) or_return
    defer vk.DestroyShaderModule(self.vk_device, gradient_color_shader, nil)

    SKY_SPV :: #load("./../../shaders/compiled/sky.comp.spv")
    sky_shader := create_shader_module(self.vk_device, SKY_SPV) or_return
    defer vk.DestroyShaderModule(self.vk_device, sky_shader, nil)

    stage_info := vk.PipelineShaderStageCreateInfo {
        sType  = .PIPELINE_SHADER_STAGE_CREATE_INFO,
        stage  = {.COMPUTE},
        module = gradient_color_shader,
        pName  = "main",
    }

    compute_pipeline_create_info := vk.ComputePipelineCreateInfo {
        sType  = .COMPUTE_PIPELINE_CREATE_INFO,
        layout = self.gradient_pipeline_layout,
        stage  = stage_info,
    }

    gradient_color := Compute_Effect {
        layout = self.gradient_pipeline_layout,
        name = "Gradient Color",
        data = {data1 = {1, 0, 0, 1}, data2 = {0, 0, 1, 1}},
    }

    vk_check(
        vk.CreateComputePipelines(
            self.vk_device,
            0,
            1,
            &compute_pipeline_create_info,
            nil,
            &gradient_color.pipeline,
        ),
    ) or_return

    // Change the shader module only to create the sky shader
    compute_pipeline_create_info.stage.module = sky_shader

    sky := Compute_Effect {
        layout = self.gradient_pipeline_layout,
        name = "Sky",
        data = {data1 = {0.1, 0.2, 0.4, 0.97}},
    }

    vk_check(
        vk.CreateComputePipelines(
            self.vk_device,
            0,
            1,
            &compute_pipeline_create_info,
            nil,
            &sky.pipeline,
        ),
    ) or_return

    // Set the 2 background effects
    self.background_effects[.Gradient] = gradient_color
    self.background_effects[.Sky] = sky

    deletion_queue_push(&self.main_deletion_queue, self.gradient_pipeline_layout)
    deletion_queue_push(&self.main_deletion_queue, gradient_color.pipeline)
    deletion_queue_push(&self.main_deletion_queue, sky.pipeline)

    return true
}

engine_init_mesh_pipeline :: proc(self: ^Engine) -> (ok: bool) {
    mesh_frag_shader := create_shader_module(self.vk_device,
        #load("./../../shaders/compiled/tex_image.frag.spv")) or_return
    defer vk.DestroyShaderModule(self.vk_device, mesh_frag_shader, nil)

    mesh_vertex_shader := create_shader_module(self.vk_device,
        #load("./../../shaders/compiled/colored_triangle_mesh.vert.spv")) or_return
    defer vk.DestroyShaderModule(self.vk_device, mesh_vertex_shader, nil)

    buffer_range := vk.PushConstantRange {
        offset     = 0,
        size       = size_of(GPU_Draw_Push_Constants),
        stageFlags = {.VERTEX},
    }

    pipeline_layout_info := pipeline_layout_create_info()
    pipeline_layout_info.pPushConstantRanges = &buffer_range
    pipeline_layout_info.pushConstantRangeCount = 1
    pipeline_layout_info.pSetLayouts = &self.single_image_descriptor_layout
    pipeline_layout_info.setLayoutCount = 1

    vk_check(vk.CreatePipelineLayout(
        self.vk_device,
        &pipeline_layout_info,
        nil,
        &self.mesh_pipeline_layout,
    )) or_return
    deletion_queue_push(&self.main_deletion_queue, self.mesh_pipeline_layout)

    builder := pipeline_builder_create_default()

    // Use the triangle layout we created
    builder.pipeline_layout = self.mesh_pipeline_layout
    // Add the vertex and pixel shaders to the pipeline
    pipeline_builder_set_shaders(&builder, mesh_vertex_shader, mesh_frag_shader)
    // It will draw triangles
    pipeline_builder_set_input_topology(&builder, .TRIANGLE_LIST)
    // Filled triangles
    pipeline_builder_set_polygon_mode(&builder, .FILL)
    // No backface culling
    pipeline_builder_set_cull_mode(&builder, vk.CullModeFlags_NONE, .CLOCKWISE)
    // No multisampling
    pipeline_builder_set_multisampling_none(&builder)
    // Enable blending
    pipeline_builder_disable_blending(&builder)
    // pipeline_builder_enable_blending_additive(&builder)
    // Enable depth testing
    pipeline_builder_enable_depth_test(&builder, true, .GREATER_OR_EQUAL)

    // Connect the image format we will draw into, from draw image
    pipeline_builder_set_color_attachment_format(&builder, self.draw_image.image_format)
    pipeline_builder_set_depth_attachment_format(&builder, self.depth_image.image_format)

    // Finally build the pipeline
    self.mesh_pipeline = pipeline_builder_build(&builder, self.vk_device) or_return
    deletion_queue_push(&self.main_deletion_queue, self.mesh_pipeline)

    return true
}

engine_init_pipelines :: proc(self: ^Engine) -> (ok: bool) {
    push_constant := vk.PushConstantRange {
        offset     = 0,
        size       = size_of(Compute_Push_Constants),
        stageFlags = {.COMPUTE},
    }

    compute_layout := vk.PipelineLayoutCreateInfo {
        sType                  = .PIPELINE_LAYOUT_CREATE_INFO,
        pSetLayouts            = &self.draw_image_descriptor_layout,
        setLayoutCount         = 1,
        pPushConstantRanges    = &push_constant,
        pushConstantRangeCount = 1,
    }

    vk_check(vk.CreatePipelineLayout(
        self.vk_device, &compute_layout, nil, &self.gradient_pipeline_layout)) or_return

    // Compute pipelines
    engine_init_background_pipelines(self) or_return

    // Graphics pipelines
    engine_init_mesh_pipeline(self) or_return

    // Materials pipeline
    metallic_roughness_build_pipelines(&self.metal_rough_material, self) or_return
    deletion_queue_push(&self.main_deletion_queue, self.metal_rough_material)

    return true
}

setup_imgui_style :: proc() {
    style := im.GetStyle()
    colors := &style.Colors

    // Base colors for a pleasant and modern dark theme with dark accents
    colors[im.Col.Text]                  = {0.92, 0.93, 0.94, 1.00}  // Light grey text for readability
    colors[im.Col.TextDisabled]          = {0.50, 0.52, 0.54, 1.00}  // Subtle grey for disabled text
    colors[im.Col.WindowBg]              = {0.14, 0.14, 0.16, 1.00}  // Dark background with a hint of blue
    colors[im.Col.ChildBg]               = {0.16, 0.16, 0.18, 1.00}  // Slightly lighter for child elements
    colors[im.Col.PopupBg]               = {0.18, 0.18, 0.20, 1.00}  // Popup background
    colors[im.Col.Border]                = {0.28, 0.29, 0.30, 0.60}  // Soft border color
    colors[im.Col.BorderShadow]          = {0.00, 0.00, 0.00, 0.00}  // No border shadow
    colors[im.Col.FrameBg]               = {0.20, 0.22, 0.24, 1.00}  // Frame background
    colors[im.Col.FrameBgHovered]        = {0.22, 0.24, 0.26, 1.00}  // Frame hover effect
    colors[im.Col.FrameBgActive]         = {0.24, 0.26, 0.28, 1.00}  // Active frame background
    colors[im.Col.TitleBg]               = {0.14, 0.14, 0.16, 1.00}  // Title background
    colors[im.Col.TitleBgActive]         = {0.16, 0.16, 0.18, 1.00}  // Active title background
    colors[im.Col.TitleBgCollapsed]      = {0.14, 0.14, 0.16, 1.00}  // Collapsed title background
    colors[im.Col.MenuBarBg]             = {0.20, 0.20, 0.22, 1.00}  // Menu bar background
    colors[im.Col.ScrollbarBg]           = {0.16, 0.16, 0.18, 1.00}  // Scrollbar background
    colors[im.Col.ScrollbarGrab]         = {0.24, 0.26, 0.28, 1.00}  // Dark accent for scrollbar grab
    colors[im.Col.ScrollbarGrabHovered]  = {0.28, 0.30, 0.32, 1.00}  // Scrollbar grab hover
    colors[im.Col.ScrollbarGrabActive]   = {0.32, 0.34, 0.36, 1.00}  // Scrollbar grab active
    colors[im.Col.CheckMark]             = {0.46, 0.56, 0.66, 1.00}  // Dark blue checkmark
    colors[im.Col.SliderGrab]            = {0.36, 0.46, 0.56, 1.00}  // Dark blue slider grab
    colors[im.Col.SliderGrabActive]      = {0.40, 0.50, 0.60, 1.00}  // Active slider grab
    colors[im.Col.Button]                = {0.24, 0.34, 0.44, 1.00}  // Dark blue button
    colors[im.Col.ButtonHovered]         = {0.28, 0.38, 0.48, 1.00}  // Button hover effect
    colors[im.Col.ButtonActive]          = {0.32, 0.42, 0.52, 1.00}  // Active button
    colors[im.Col.Header]                = {0.24, 0.34, 0.44, 1.00}  // Header color similar to button
    colors[im.Col.HeaderHovered]         = {0.28, 0.38, 0.48, 1.00}  // Header hover effect
    colors[im.Col.HeaderActive]          = {0.32, 0.42, 0.52, 1.00}  // Active header
    colors[im.Col.Separator]             = {0.28, 0.29, 0.30, 1.00}  // Separator color
    colors[im.Col.SeparatorHovered]      = {0.46, 0.56, 0.66, 1.00}  // Hover effect for separator
    colors[im.Col.SeparatorActive]       = {0.46, 0.56, 0.66, 1.00}  // Active separator
    colors[im.Col.ResizeGrip]            = {0.36, 0.46, 0.56, 1.00}  // Resize grip
    colors[im.Col.ResizeGripHovered]     = {0.40, 0.50, 0.60, 1.00}  // Hover effect for resize grip
    colors[im.Col.ResizeGripActive]      = {0.44, 0.54, 0.64, 1.00}  // Active resize grip
    colors[im.Col.Tab]                   = {0.20, 0.22, 0.24, 1.00}  // Inactive tab
    colors[im.Col.TabHovered]            = {0.28, 0.38, 0.48, 1.00}  // Hover effect for tab
    colors[im.Col.TabSelected]           = {0.24, 0.34, 0.44, 1.00}  // Active tab color (TabActive)
    colors[im.Col.TabDimmed]             = {0.20, 0.22, 0.24, 1.00}  // Unfocused tab (TabUnfocused)
    colors[im.Col.TabDimmedSelected]     = {0.24, 0.34, 0.44, 1.00}  // Active but unfocused tab (TabUnfocusedActive)
    colors[im.Col.DockingPreview]        = {0.24, 0.34, 0.44, 0.70}  // Docking preview
    colors[im.Col.DockingEmptyBg]        = {0.14, 0.14, 0.16, 1.00}  // Empty docking background
    colors[im.Col.PlotLines]             = {0.46, 0.56, 0.66, 1.00}  // Plot lines
    colors[im.Col.PlotLinesHovered]      = {0.46, 0.56, 0.66, 1.00}  // Hover effect for plot lines
    colors[im.Col.PlotHistogram]         = {0.36, 0.46, 0.56, 1.00}  // Histogram color
    colors[im.Col.PlotHistogramHovered]  = {0.40, 0.50, 0.60, 1.00}  // Hover effect for histogram
    colors[im.Col.TableHeaderBg]         = {0.20, 0.22, 0.24, 1.00}  // Table header background
    colors[im.Col.TableBorderStrong]     = {0.28, 0.29, 0.30, 1.00}  // Strong border for tables
    colors[im.Col.TableBorderLight]      = {0.24, 0.25, 0.26, 1.00}  // Light border for tables
    colors[im.Col.TableRowBg]            = {0.20, 0.22, 0.24, 1.00}  // Table row background
    colors[im.Col.TableRowBgAlt]         = {0.22, 0.24, 0.26, 1.00}  // Alternate row background
    colors[im.Col.TextSelectedBg]        = {0.24, 0.34, 0.44, 0.35}  // Selected text background
    colors[im.Col.DragDropTarget]        = {0.46, 0.56, 0.66, 0.90}  // Drag and drop target
    colors[im.Col.NavCursor]             = {0.46, 0.56, 0.66, 1.00}  // Navigation highlight (NavHighlight)
    colors[im.Col.NavWindowingHighlight] = {1.00, 1.00, 1.00, 0.70}  // Windowing highlight
    colors[im.Col.NavWindowingDimBg]     = {0.80, 0.80, 0.80, 0.20}  // Dim background for windowing
    colors[im.Col.ModalWindowDimBg]      = {0.80, 0.80, 0.80, 0.35}  // Dim background for modal windows

    // Style adjustments
    style.WindowRounding    = 8.0  // Softer rounded corners for windows
    style.FrameRounding     = 4.0  // Rounded corners for frames
    style.ScrollbarRounding = 6.0  // Rounded corners for scrollbars
    style.GrabRounding      = 4.0  // Rounded corners for grab elements
    style.ChildRounding     = 4.0  // Rounded corners for child windows

    style.WindowTitleAlign  = {0.50, 0.50}  // Centered window title
    style.WindowPadding     = {10.0, 10.0}  // Comfortable padding
    style.FramePadding      = {6.0, 4.0}    // Frame padding
    style.ItemSpacing       = {8.0, 8.0}    // Item spacing
    style.ItemInnerSpacing  = {8.0, 6.0}    // Inner item spacing
    style.IndentSpacing     = 22.0          // Indentation spacing

    style.ScrollbarSize     = 16.0  // Scrollbar size
    style.GrabMinSize       = 10.0  // Minimum grab size

    style.AntiAliasedLines  = true  // Enable anti-aliased lines
    style.AntiAliasedFill   = true  // Enable anti-aliased fill
}

engine_init_imgui :: proc(self: ^Engine) -> (ok: bool) {
    im.CHECKVERSION()

    // 1: create descriptor pool for IMGUI
    // The size of the pool is very oversize, but it's copied from imgui demo itself.
    pool_sizes := []vk.DescriptorPoolSize {
        {.SAMPLER, 1000},
        {.COMBINED_IMAGE_SAMPLER, 1000},
        {.SAMPLED_IMAGE, 1000},
        {.STORAGE_IMAGE, 1000},
        {.UNIFORM_TEXEL_BUFFER, 1000},
        {.STORAGE_TEXEL_BUFFER, 1000},
        {.UNIFORM_BUFFER, 1000},
        {.STORAGE_BUFFER, 1000},
        {.UNIFORM_BUFFER_DYNAMIC, 1000},
        {.STORAGE_BUFFER_DYNAMIC, 1000},
        {.INPUT_ATTACHMENT, 1000},
    }

    pool_info := vk.DescriptorPoolCreateInfo {
        sType         = .DESCRIPTOR_POOL_CREATE_INFO,
        flags         = {.FREE_DESCRIPTOR_SET},
        maxSets       = 1000,
        poolSizeCount = u32(len(pool_sizes)),
        pPoolSizes    = raw_data(pool_sizes),
    }

    imgui_pool: vk.DescriptorPool
    vk_check(vk.CreateDescriptorPool(self.vk_device, &pool_info, nil, &imgui_pool)) or_return

    // This initializes the core structures of imgui
    im.CreateContext()
    defer if !ok {im.DestroyContext()}

    // This initializes imgui for GLFW
    im_glfw.InitForVulkan(self.window, install_callbacks = true) or_return
    defer if !ok {im_glfw.Shutdown()}

    // This initializes imgui for Vulkan
    pipeline_info := im_vk.PipelineInfo {
        PipelineRenderingCreateInfo = {
            sType                   = .PIPELINE_RENDERING_CREATE_INFO,
            colorAttachmentCount    = 1,
            pColorAttachmentFormats = &self.swapchain_format,
        },
        MSAASamples = {._1},
    }

    // This initializes imgui for Vulkan
    init_info := im_vk.InitInfo {
        ApiVersion          = self.vkb.instance.api_version,
        Instance            = self.vk_instance,
        PhysicalDevice      = self.vk_physical_device,
        Device              = self.vk_device,
        Queue               = self.graphics_queue,
        DescriptorPool      = imgui_pool,
        MinImageCount       = 3,
        ImageCount          = 3,
        UseDynamicRendering = true,
        PipelineInfoMain    = pipeline_info,
    }

    im_vk.LoadFunctions(
        self.vkb.instance.api_version,
        proc "c" (function_name: cstring, user_data: rawptr) -> vk.ProcVoidFunction {
            engine := cast(^Engine)user_data
            return vk.GetInstanceProcAddr(engine.vk_instance, function_name)
        },
        self,
    ) or_return

    im_vk.Init(&init_info) or_return
    defer if !ok {im_vk.Shutdown()}

    // Remember the LIFO queue, make sure the order of push is correct
    deletion_queue_push(&self.main_deletion_queue, imgui_pool)
    deletion_queue_push(&self.main_deletion_queue, im_vk.Shutdown)
    deletion_queue_push(&self.main_deletion_queue, im_glfw.Shutdown)

    setup_imgui_style()

    return true
}

engine_init_default_data :: proc(self: ^Engine) -> (ok: bool) {
    // Initialize the scene
    scene_init(&self.scene)

    load_gltf_meshes(self, "assets/basicmesh.glb", &self.scene.meshes) or_return
    defer if !ok {
        destroy_mesh_assets(&self.scene.meshes)
    }

    // 3 default textures, white, grey, black. 1 pixel each
    white := pack_unorm_4x8({1, 1, 1, 1})
    self.white_image = create_image_from_data(self,
        &white, {1, 1, 1}, .R8G8B8A8_UNORM, {.SAMPLED}) or_return
    deletion_queue_push(&self.main_deletion_queue, self.white_image)

    grey := pack_unorm_4x8({0.66, 0.66, 0.66, 1})
    self.grey_image = create_image_from_data(self,
        &grey, {1, 1, 1}, .R8G8B8A8_UNORM, {.SAMPLED}) or_return
    deletion_queue_push(&self.main_deletion_queue, self.grey_image)

    black := pack_unorm_4x8({0, 0, 0, 0})
    self.black_image = create_image_from_data(self,
        &black, {1, 1, 1}, .R8G8B8A8_UNORM, {.SAMPLED}) or_return
    deletion_queue_push(&self.main_deletion_queue, self.black_image)

    // Checkerboard image
    magenta := pack_unorm_4x8({1, 0, 1, 1})
    pixels: [16 * 16]u32
    for x in 0 ..< 16 {
        for y in 0 ..< 16 {
            pixels[y * 16 + x] = ((x % 2) ~ (y % 2)) != 0 ? magenta : black
        }
    }
    self.error_checkerboard_image = create_image_from_data(self,
        raw_data(pixels[:]), {16, 16, 1}, .R8G8B8A8_UNORM, {.SAMPLED}) or_return
    deletion_queue_push(&self.main_deletion_queue, self.error_checkerboard_image)

    sampler_info := vk.SamplerCreateInfo {
        sType     = .SAMPLER_CREATE_INFO,
        magFilter = .NEAREST,
        minFilter = .NEAREST,
    }

    vk_check(vk.CreateSampler(
        self.vk_device, &sampler_info, nil, &self.default_sampler_nearest)) or_return
    deletion_queue_push(&self.main_deletion_queue, self.default_sampler_nearest)

    sampler_info.magFilter = .LINEAR
    sampler_info.minFilter = .LINEAR

    vk_check(vk.CreateSampler(
        self.vk_device, &sampler_info, nil, &self.default_sampler_linear)) or_return
    deletion_queue_push(&self.main_deletion_queue, self.default_sampler_linear)

    // Default material textures
    material_resources := Metallic_Roughness_Resources {
        color_image         = self.white_image,
        color_sampler       = self.default_sampler_linear,
        metal_rough_image   = self.white_image,
        metal_rough_sampler = self.default_sampler_linear,
    }

    // Set the uniform buffer for the material data
    material_constants := create_buffer(
        self,
        size_of(Metallic_Roughness_Constants),
        {.UNIFORM_BUFFER},
        .CPU_TO_GPU,
    ) or_return
    deletion_queue_push(&self.main_deletion_queue, material_constants)

    // Write the buffer
    scene_uniform_data :=
        cast(^Metallic_Roughness_Constants)material_constants.info.pMappedData
    scene_uniform_data.color_factors = {1, 1, 1, 1}
    scene_uniform_data.metal_rough_factors = {1, 0.5, 0, 0}

    material_resources.data_buffer = material_constants.buffer
    material_resources.data_buffer_offset = 0

    self.default_material_data = metallic_roughness_write(
        &self.metal_rough_material,
        self.vk_device,
        .Main_Color,
        &material_resources,
        &self.global_descriptor_allocator,
    ) or_return

    // Add default material to the materials array
    default_material_idx := append_and_get_idx(
        &self.scene.materials, self.default_material_data)

    // Process each mesh
    for m, i in self.scene.meshes {
        // Ignore the Sphere for now
        if m.name == "Sphere" {
            continue
        }

        node_idx := scene_add_mesh_node(&self.scene, -1, i, default_material_idx, m.name)
        self.name_for_node[m.name] = u32(node_idx)
    }

    // Find and update Suzanne node
    if suzanne_node, suzanne_ok := self.name_for_node["Suzanne"]; suzanne_ok {
        self.scene.local_transforms[suzanne_node] = la.MATRIX4F32_IDENTITY
    }

    // Find and update Cube nodes (create a line of cubes)
    if cube_node, cube_ok := self.name_for_node["Cube"]; cube_ok {
        for x := -3; x < 3; x += 1 {
            scale := la.matrix4_scale(la.Vector3f32{0.2, 0.2, 0.2})
            translation := la.matrix4_translate(la.Vector3f32{f32(x), 1, 0})
            transform := la.matrix_mul(translation, scale)

            // For simplicity, assume one node per cube
            if x == -3 {
                // Use the original cube node for x = -3
                self.scene.local_transforms[cube_node] = transform
            } else {
                // Add new nodes for additional cubes
                new_cube_idx := scene_add_mesh_node(
                    scene = &self.scene,
                    parent = cube_node,
                    mesh_index = cube_node,
                    material_index = cube_node,
                    name = "Cube",
                )
                self.scene.local_transforms[u32(new_cube_idx)] = transform
            }
        }
    }

    return true
}

// Shuts down the engine.
engine_cleanup :: proc(self: ^Engine) {
    if !self.is_initialized {
        return
    }

    // Make sure the gpu has stopped doing its things
    ensure(vk.DeviceWaitIdle(self.vk_device) == .SUCCESS)

    // Clean up scene nodes
    for &mesh in self.scene.meshes {
        destroy_buffer(mesh.mesh_buffers.index_buffer)
        destroy_buffer(mesh.mesh_buffers.vertex_buffer)
    }
    destroy_mesh_assets(&self.scene.meshes)
    scene_destroy(&self.scene)
    delete(self.main_draw_context.opaque_surfaces)
    delete(self.name_for_node)

    for &frame in self.frames {
        vk.DestroyCommandPool(self.vk_device, frame.command_pool, nil)

        // Destroy sync objects
        vk.DestroyFence(self.vk_device, frame.render_fence, nil)
        vk.DestroySemaphore(self.vk_device, frame.swapchain_semaphore, nil)

        // Flush and destroy the peer frame deletion queue
        deletion_queue_destroy(&frame.deletion_queue)
    }

    for &mesh in self.test_meshes {
        destroy_buffer(mesh.mesh_buffers.index_buffer)
        destroy_buffer(mesh.mesh_buffers.vertex_buffer)
    }
    destroy_mesh_assets(&self.test_meshes)

    // Flush and destroy the global deletion queue
    deletion_queue_destroy(&self.main_deletion_queue)

    engine_destroy_swapchain(self)

    vk.DestroySurfaceKHR(self.vk_instance, self.vk_surface, nil)
    vkb.destroy_device(&self.vkb.device)

    vkb.destroy_physical_device(&self.vkb.physical_device)
    vkb.destroy_instance(&self.vkb.instance)

    destroy_window(self.window)
}
