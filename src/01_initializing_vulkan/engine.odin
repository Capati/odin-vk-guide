package vk_guide

// Core
import intr "base:intrinsics"
import "base:runtime"
import "core:log"
import "core:math"

// Vendor
import "vendor:glfw"
import vk "vendor:vulkan"

// Local packages
import "libs:vkb"
import "libs:vma"

FRAME_OVERLAP :: 2

Frame_Data :: struct {
	command_pool:        vk.CommandPool,
	main_command_buffer: vk.CommandBuffer,
	swapchain_semaphore: vk.Semaphore,
	render_semaphore:    vk.Semaphore,
	render_fence:        vk.Fence,
}

Engine :: struct {
	// Platform
	is_initialized:        bool,
	stop_rendering:        bool,
	window_extent:         vk.Extent2D,
	window:                glfw.WindowHandle,

	// Swapchain
	swapchain_format:      vk.Format,
	swapchain_images:      []vk.Image,
	swapchain_image_views: []vk.ImageView,

	// Frame data
	frames:                [FRAME_OVERLAP]Frame_Data,
	frame_number:          int,

	// Queue
	graphics_queue:        vk.Queue,
	graphics_queue_family: u32,

	// GPU Context
	vk_instance:           vk.Instance,
	vk_physical_device:    vk.PhysicalDevice,
	vk_surface:            vk.SurfaceKHR,
	vk_device:             vk.Device,
	vk_swapchain:          vk.SwapchainKHR,
	vkb:                   struct {
		instance:        ^vkb.Instance,
		physical_device: ^vkb.Physical_Device,
		swapchain:       ^vkb.Swapchain,
		device:          ^vkb.Device,
	},

	// Internal
	vma_allocator:         vma.Allocator,
}

TITLE :: "01. Initializing Vulkan"

// Initializes everything in the engine.
engine_init :: proc(self: ^Engine) -> (ok: bool) {
	ensure(self != nil, "Invalid 'Engine' object")

	// Default window  size in pixels
	self.window_extent = {800, 600}

	width := self.window_extent.width
	height := self.window_extent.height

	// Create a window using GLFW
	self.window = create_window(TITLE, width, height) or_return
	defer if !ok {
		destroy_window(self.window)
	}

	// Set window callbacks
	glfw.SetWindowUserPointer(self.window, self)
	glfw.SetFramebufferSizeCallback(self.window, size_callback)
	glfw.SetWindowIconifyCallback(self.window, iconify_callback)

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

	// Instance
	instance_builder := vkb.init_instance_builder() or_return
	defer vkb.destroy_instance_builder(&instance_builder)

	vkb.instance_set_app_name(&instance_builder, "Example Vulkan Application")
	vkb.instance_require_api_version(&instance_builder, vk.API_VERSION_1_3)

	when ODIN_DEBUG {
		vkb.instance_request_validation_layers(&instance_builder)
		vkb.instance_use_default_debug_messenger(&instance_builder)

		VK_LAYER_LUNARG_MONITOR :: "VK_LAYER_LUNARG_monitor"

		info := vkb.get_system_info(ta)

		if vkb.is_layer_available(&info, VK_LAYER_LUNARG_MONITOR) {
			// Displays FPS in the application's title bar. It is only compatible
			// with the Win32 and XCB windowing systems.
			// https://vulkan.lunarg.com/doc/sdk/latest/windows/monitor_layer.html
			when ODIN_OS == .Windows || ODIN_OS == .Linux {
				vkb.instance_enable_layer(&instance_builder, VK_LAYER_LUNARG_MONITOR)
			}
		}
	}

	self.vkb.instance = vkb.build_instance(&instance_builder) or_return
	defer if !ok {
		vkb.destroy_instance(self.vkb.instance)
	}
	self.vk_instance = self.vkb.instance.ptr

	// Surface
	vk_check(
		glfw.CreateWindowSurface(self.vk_instance, self.window, nil, &self.vk_surface),
	) or_return
	defer if !ok {
		vkb.destroy_surface(self.vkb.instance, self.vk_surface)
	}

	// Vulkan 1.2 features
	features_12 := vk.PhysicalDeviceVulkan12Features {
		bufferDeviceAddress = true,
		descriptorIndexing  = true,
	}

	// Vulkan 1.3 features
	features_13 := vk.PhysicalDeviceVulkan13Features {
		dynamicRendering = true,
		synchronization2 = true,
	}

	// Use vk-bootstrap to select a gpu.
	// We want a gpu that can write to the GLFW surface and supports vulkan 1.3
	// with the correct features
	selector := vkb.init_physical_device_selector(self.vkb.instance) or_return
	defer vkb.destroy_physical_device_selector(&selector)

	vkb.selector_set_minimum_version(&selector, vk.API_VERSION_1_3)
	vkb.selector_set_required_features_13(&selector, features_13)
	vkb.selector_set_required_features_12(&selector, features_12)
	vkb.selector_set_surface(&selector, self.vk_surface)

	self.vkb.physical_device = vkb.select_physical_device(&selector) or_return
	defer if !ok {
		vkb.destroy_physical_device(self.vkb.physical_device)
	}
	self.vk_physical_device = self.vkb.physical_device.ptr

	// Create the final vulkan device
	device_builder := vkb.init_device_builder(self.vkb.physical_device) or_return
	defer vkb.destroy_device_builder(&device_builder)

	self.vkb.device = vkb.build_device(&device_builder) or_return
	defer if !ok {
		vkb.destroy_device(self.vkb.device)
	}
	self.vk_device = self.vkb.device.ptr

	// use vk-bootstrap to get a Graphics queue
	self.graphics_queue = vkb.device_get_queue(self.vkb.device, .Graphics) or_return
	self.graphics_queue_family = vkb.device_get_queue_index(self.vkb.device, .Graphics) or_return

	// Create the VMA (Vulkan Memory Allocator)
	// Initializes a subset of Vulkan functions required by VMA
	vma_vulkan_functions := vma.create_vulkan_functions()

	allocator_create_info: vma.Allocator_Create_Info = {
		flags              = {.Buffer_Device_Address},
		instance           = self.vk_instance,
		vulkan_api_version = vkb.convert_vulkan_to_vma_version(self.vkb.instance.api_version),
		physical_device    = self.vk_physical_device,
		device             = self.vk_device,
		vulkan_functions   = &vma_vulkan_functions,
	}

	vk_check(
		vma.create_allocator(allocator_create_info, &self.vma_allocator),
		"Failed to Create Vulkan Memory Allocator",
	) or_return

	return true
}

engine_create_swapchain :: proc(self: ^Engine, width, height: u32) -> (ok: bool) {
	self.swapchain_format = .B8G8R8A8_UNORM

	builder := vkb.init_swapchain_builder(self.vkb.device) or_return
	defer vkb.destroy_swapchain_builder(&builder)

	vkb.swapchain_builder_set_desired_format(
		&builder,
		{format = self.swapchain_format, colorSpace = .SRGB_NONLINEAR},
	)
	vkb.swapchain_builder_set_present_mode(&builder, .FIFO)
	vkb.swapchain_builder_set_desired_extent(&builder, width, height)
	vkb.swapchain_builder_add_image_usage_flags(&builder, {.TRANSFER_DST})

	self.vkb.swapchain = vkb.build_swapchain(&builder) or_return
	self.vk_swapchain = self.vkb.swapchain.ptr

	self.swapchain_images = vkb.swapchain_get_images(self.vkb.swapchain) or_return
	self.swapchain_image_views = vkb.swapchain_get_image_views(self.vkb.swapchain) or_return

	return true
}

engine_init_swapchain :: proc(self: ^Engine) -> (ok: bool) {
	engine_create_swapchain(self, self.window_extent.width, self.window_extent.height) or_return
	return true
}

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
		) or_return

		// Allocate the default command buffer that we will use for rendering
		cmd_alloc_info := command_buffer_allocate_info(self.frames[i].command_pool)

		vk_check(
			vk.AllocateCommandBuffers(
				self.vk_device,
				&cmd_alloc_info,
				&self.frames[i].main_command_buffer,
			),
		) or_return
	}

	return true
}

engine_init_sync_structures :: proc(self: ^Engine) -> (ok: bool) {
	// Create synchronization structures, one fence to control when the gpu has finished
	// rendering the frame, and 2 semaphores to sincronize rendering with swapchain. We want
	// the fence to start signalled so we can wait on it on the first frame
	fence_create_info := fence_create_info({.SIGNALED})
	semaphore_create_info := semaphore_create_info()

	for i in 0 ..< FRAME_OVERLAP {
		vk_check(
			vk.CreateFence(self.vk_device, &fence_create_info, nil, &self.frames[i].render_fence),
		) or_return

		vk_check(
			vk.CreateSemaphore(
				self.vk_device,
				&semaphore_create_info,
				nil,
				&self.frames[i].swapchain_semaphore,
			),
		) or_return
		vk_check(
			vk.CreateSemaphore(
				self.vk_device,
				&semaphore_create_info,
				nil,
				&self.frames[i].render_semaphore,
			),
		) or_return
	}

	return true
}

engine_get_current_frame :: #force_inline proc(self: ^Engine) -> ^Frame_Data #no_bounds_check {
	return &self.frames[self.frame_number % FRAME_OVERLAP]
}

// Run main loop.
engine_run :: proc(self: ^Engine) {
	log.info("Entering main loop...")

	for !glfw.WindowShouldClose(self.window) {
		glfw.PollEvents()

		// Do not draw if we are minimized
		if self.stop_rendering {
			glfw.WaitEvents() // Wait to avoid endless spinning
			continue
		}

		engine_draw(self)
	}

	log.info("Exiting...")
}

// Draw loop.
engine_draw :: proc(self: ^Engine) -> (ok: bool) {
	// Steps:
	//
	// 1. Waits for the GPU to finish the previous frame
	// 2. Acquires the next swapchain image
	// 3. Records rendering commands into a command buffer
	// 4. Submits the command buffer to the GPU for execution
	// 5. Presents the rendered image to the screen

	render_fence := engine_get_current_frame(self).render_fence

	// Wait until the gpu has finished rendering the last frame. Timeout of 1 second
	vk_check(vk.WaitForFences(self.vk_device, 1, &render_fence, true, max(u64))) or_return
	vk_check(vk.ResetFences(self.vk_device, 1, &render_fence)) or_return

	// Request image from the swapchain
	swapchain_image_index: u32 = ---
	vk_check(
		vk.AcquireNextImageKHR(
			self.vk_device,
			self.vk_swapchain,
			max(u64),
			engine_get_current_frame(self).swapchain_semaphore,
			0,
			&swapchain_image_index,
		),
	) or_return

	// The the current command buffer, naming it cmd for shorter writing
	cmd := engine_get_current_frame(self).main_command_buffer

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
	transition_image(cmd, self.swapchain_images[swapchain_image_index], .GENERAL, .PRESENT_SRC_KHR)

	// Finalize the command buffer (we can no longer add commands, but it can now be executed)
	vk_check(vk.EndCommandBuffer(cmd)) or_return

	// Prepare the submission to the queue. we want to wait on the _presentSemaphore, as that
	// semaphore is signaled when the swapchain is ready we will signal the _renderSemaphore,
	// to signal that rendering has finished

	cmd_info := command_buffer_submit_info(cmd)

	wait_info := semaphore_submit_info(
		{.COLOR_ATTACHMENT_OUTPUT_KHR},
		engine_get_current_frame(self).swapchain_semaphore,
	)
	signal_info := semaphore_submit_info(
		{.ALL_GRAPHICS},
		engine_get_current_frame(self).render_semaphore,
	)

	submit := submit_info(&cmd_info, &signal_info, &wait_info)

	// Submit command buffer to the queue and execute it. _renderFence will now block until the
	// graphic commands finish execution
	vk_check(vk.QueueSubmit2(self.graphics_queue, 1, &submit, render_fence)) or_return

	// Prepare present
	//
	// this will put the image we just rendered to into the visible window. we want to wait on
	// the render_semaphore for that, as its necessary that drawing commands have finished
	// before the image is displayed to the user
	present_info := vk.PresentInfoKHR {
		sType              = .PRESENT_INFO_KHR,
		pSwapchains        = &self.vk_swapchain,
		swapchainCount     = 1,
		pWaitSemaphores    = &engine_get_current_frame(self).render_semaphore,
		waitSemaphoreCount = 1,
		pImageIndices      = &swapchain_image_index,
	}

	vk_check(vk.QueuePresentKHR(self.graphics_queue, &present_info)) or_return

	//increase the number of frames drawn
	self.frame_number += 1

	return true
}

// Shuts down the engine.
engine_cleanup :: proc(self: ^Engine) {
	if !self.is_initialized {
		return
	}

	// Make sure the gpu has stopped doing its things
	ensure(vk.DeviceWaitIdle(self.vk_device) == .SUCCESS)

	for i in 0 ..< FRAME_OVERLAP {
		vk.DestroyCommandPool(self.vk_device, self.frames[i].command_pool, nil)

		// Destroy sync objects
		vk.DestroyFence(self.vk_device, self.frames[i].render_fence, nil)
		vk.DestroySemaphore(self.vk_device, self.frames[i].render_semaphore, nil)
		vk.DestroySemaphore(self.vk_device, self.frames[i].swapchain_semaphore, nil)
	}

	engine_destroy_swapchain(self)

	vk.DestroySurfaceKHR(self.vk_instance, self.vk_surface, nil)
	vkb.destroy_device(self.vkb.device)

	vkb.destroy_physical_device(self.vkb.physical_device)
	vkb.destroy_instance(self.vkb.instance)

	destroy_window(self.window)
}

engine_destroy_swapchain :: proc(self: ^Engine) {
	vkb.destroy_swapchain(self.vkb.swapchain)
	vkb.swapchain_destroy_image_views(self.vkb.swapchain, self.swapchain_image_views)
	delete(self.swapchain_image_views)
	delete(self.swapchain_images)
}
