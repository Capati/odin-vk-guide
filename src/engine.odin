package main

// Core
import "core:container/queue"
import "core:log"
import "core:math"
import "core:time"

// Vendor
import sdl "vendor:sdl2"
import vk "vendor:vulkan"

// Libs
import "libs:vkb"
import "libs:vma"

Engine :: struct {
	is_initialized:        bool,
	frame_number:          u32,
	stop_rendering:        bool,
	window_extent:         vk.Extent2D,
	window:                ^sdl.Window,
	instance:              ^vkb.Instance,
	chosen_gpu:            ^vkb.Physical_Device,
	device:                ^vkb.Device,
	surface:               vk.SurfaceKHR,
	swapchain:             ^vkb.Swapchain,
	swapchain_format:      vk.Format,
	swapchain_images:      []vk.Image,
	swapchain_image_views: []vk.ImageView,
	frames:                [FRAME_OVERLAP]Frame_Data,
	graphics_queue:        vk.Queue,
	graphics_queue_family: u32,
	deletors:              Deletion_Queue,
	allocator:             vma.Allocator,
	draw_image:            Allocated_Image,
	draw_extent:           vk.Extent2D,
}

@(private)
_ctx: Engine

// Initializes everything in the engine
engine_init :: proc() -> (err: Error) {
	// We initialize SDL and create a window with it.
	if res := sdl.Init({.VIDEO}); res != 0 {
		log.errorf("Failed to initialize SDL: [%s]", sdl.GetError())
		return .SDL_Init_Failed
	}
	defer if err != nil do sdl.Quit()

	window_flags: sdl.WindowFlags = {.VULKAN}

	_ctx.window_extent = {800, 600}

	_ctx.window = sdl.CreateWindow(
		"Vulkan Engine",
		sdl.WINDOWPOS_UNDEFINED,
		sdl.WINDOWPOS_UNDEFINED,
		i32(_ctx.window_extent.width),
		i32(_ctx.window_extent.height),
		window_flags,
	)

	if _ctx.window == nil {
		log.errorf("Failed to create the window: [%s]", sdl.GetError())
		return .Create_Window_Failed
	}

	if res := engine_init_vulkan(); res != nil {
		log.errorf("Failed to initialize Vulkan: [%v]", res)
		return res
	}

	if res := engine_init_swapchain(); res != nil {
		log.errorf("Failed to initialize Swapchain: [%v]", res)
		return res
	}

	if res := engine_init_commands(); res != nil {
		log.errorf("Failed to initialize commands: [%v]", res)
		return res
	}

	if res := engine_init_sync_structures(); res != nil {
		log.errorf("Failed to initialize sync structures: [%v]", res)
		return res
	}

	// everything went fine
	_ctx.is_initialized = true

	return
}

engine_init_vulkan :: proc() -> (err: Error) {
	// Init deletion queues
	queue.init(&_ctx.deletors) or_return
	defer if err != nil do queue.destroy(&_ctx.deletors)

	for i in 0 ..< FRAME_OVERLAP {
		queue.init(&_ctx.frames[i].deletors) or_return
	}
	defer if err != nil {
		for i in 0 ..< FRAME_OVERLAP {
			queue.destroy(&_ctx.frames[i].deletors)
		}
	}

	// Instance
	inst_b := vkb.init_instance_builder() or_return
	defer vkb.destroy_instance_builder(&inst_b)

	vkb.instance_set_app_name(&inst_b, "Example Vulkan Application")
	vkb.instance_request_validation_layers(&inst_b)
	vkb.instance_use_default_debug_messenger(&inst_b)
	vkb.instance_require_api_version(&inst_b, vk.API_VERSION_1_3)

	_ctx.instance = vkb.build_instance(&inst_b) or_return
	defer if err != nil do vkb.destroy_instance(_ctx.instance)

	// Surface
	if !sdl.Vulkan_CreateSurface(_ctx.window, _ctx.instance.ptr, &_ctx.surface) {
		log.errorf("SDL couldn't create vulkan surface: %s", sdl.GetError())
		return
	}
	defer if err != nil do vkb.destroy_surface(_ctx.instance, _ctx.surface)

	// Vulkan 1.3 features
	features_13 := vk.PhysicalDeviceVulkan13Features {
		dynamicRendering = true,
		synchronization2 = true,
	}

	// Vulkan 1.2 features
	features_12 := vk.PhysicalDeviceVulkan12Features {
		bufferDeviceAddress = true,
		descriptorIndexing  = true,
	}

	// Use vk-bootstrap to select a gpu.
	// We want a gpu that can write to the SDL surface and supports vulkan 1.3
	// with the correct features
	selector := vkb.init_physical_device_selector(_ctx.instance) or_return
	defer vkb.destroy_physical_device_selector(&selector)

	vkb.selector_set_minimum_version(&selector, vk.API_VERSION_1_3)
	vkb.selector_set_required_features_13(&selector, features_13)
	vkb.selector_set_required_features_12(&selector, features_12)
	vkb.selector_set_surface(&selector, _ctx.surface)

	_ctx.chosen_gpu = vkb.select_physical_device(&selector) or_return
	defer if err != nil do vkb.destroy_physical_device(_ctx.chosen_gpu)

	// Create the final vulkan device
	device_builder := vkb.init_device_builder(_ctx.chosen_gpu) or_return
	defer vkb.destroy_device_builder(&device_builder)

	_ctx.device = vkb.build_device(&device_builder) or_return
	defer if err != nil do vkb.destroy_device(_ctx.device)

	// use vk-bootstrap to get a Graphics queue
	_ctx.graphics_queue = vkb.device_get_queue(_ctx.device, .Graphics) or_return
	_ctx.graphics_queue_family = vkb.device_get_queue_index(_ctx.device, .Graphics) or_return

	// Create the VMA (Vulkan Memory Allocator)
	vma_vulkan_functions := vma.create_vulkan_functions()

	allocator_create_info: vma.Allocator_Create_Info = {
		flags = {.Buffer_Device_Address},
		instance = _ctx.instance.ptr,
		vulkan_api_version = vkb.convert_vulkan_to_vma_version(_ctx.instance.api_version),
		physical_device = _ctx.chosen_gpu.ptr,
		device = _ctx.device.ptr,
		vulkan_functions = &vma_vulkan_functions,
	}

	if res := vma.create_allocator(&allocator_create_info, &_ctx.allocator); res != .SUCCESS {
		log.errorf("Failed to Create Vulkan Memory Allocator: [%v]", res)
		return res
	}

	queue.push_back(&_ctx.deletors, proc() {
		vma.destroy_allocator(_ctx.allocator)
	})

	return
}

engine_create_swapchain :: proc(width, height: u32) -> (err: Error) {
	_ctx.swapchain_format = .B8G8R8A8_UNORM

	builder := vkb.init_swapchain_builder(_ctx.device) or_return
	defer vkb.destroy_swapchain_builder(&builder)

	vkb.swapchain_builder_set_desired_format(
		&builder,
		{format = _ctx.swapchain_format, colorSpace = .SRGB_NONLINEAR},
	)
	vkb.swapchain_builder_set_present_mode(&builder, .FIFO)
	vkb.swapchain_builder_set_desired_extent(&builder, width, height)
	vkb.swapchain_builder_add_image_usage_flags(&builder, {.TRANSFER_DST})

	_ctx.swapchain = vkb.build_swapchain(&builder) or_return

	_ctx.swapchain_images = vkb.swapchain_get_images(_ctx.swapchain) or_return
	_ctx.swapchain_image_views = vkb.swapchain_get_image_views(_ctx.swapchain) or_return

	return
}

engine_init_swapchain :: proc() -> (err: Error) {
	engine_create_swapchain(_ctx.window_extent.width, _ctx.window_extent.height) or_return

	// Draw image size will match the window
	draw_image_extent := vk.Extent3D {
		width  = _ctx.window_extent.width,
		height = _ctx.window_extent.height,
		depth  = 1,
	}

	// Hardcoding the draw format to 32 bit float
	_ctx.draw_image.image_format = .R16G16B16A16_SFLOAT
	_ctx.draw_image.image_extent = draw_image_extent

	draw_image_usages := vk.ImageUsageFlags {
		.TRANSFER_SRC,
		.TRANSFER_DST,
		.STORAGE,
		.COLOR_ATTACHMENT,
	}

	rimg_info := image_create_info(
		_ctx.draw_image.image_format,
		draw_image_usages,
		draw_image_extent,
	)

	// For the draw image, we want to allocate it from gpu local memory
	rimg_allocinfo := vma.Allocation_Create_Info {
		usage = .Gpu_Only,
		required_flags = {.DEVICE_LOCAL},
	}

	// Allocate and create the image
	vma.create_image(
		_ctx.allocator,
		&rimg_info,
		&rimg_allocinfo,
		&_ctx.draw_image.image,
		&_ctx.draw_image.allocation,
		nil,
	) or_return

	//build a image-view for the draw image to use for rendering
	rview_info := imageview_create_info(
		_ctx.draw_image.image_format,
		_ctx.draw_image.image,
		{.COLOR},
	)

	vk.CreateImageView(_ctx.device.ptr, &rview_info, nil, &_ctx.draw_image.image_view) or_return

	deletion_queue_push_proc(&_ctx.deletors, proc() {
		vk.DestroyImageView(_ctx.device.ptr, _ctx.draw_image.image_view, nil)
		vk.DestroyImage(_ctx.device.ptr, _ctx.draw_image.image, nil)
	})

	return
}

engine_init_commands :: proc() -> (err: Error) {
	//create a command pool for commands submitted to the graphics queue.
	//we also want the pool to allow for resetting of individual command buffers
	command_pool_info := command_pool_create_info(
		_ctx.graphics_queue_family,
		{.RESET_COMMAND_BUFFER},
	)

	for i in 0 ..< FRAME_OVERLAP {
		vk.CreateCommandPool(
			_ctx.device.ptr,
			&command_pool_info,
			nil,
			&_ctx.frames[i].command_pool,
		) or_return

		// allocate the default command buffer that we will use for rendering
		cmd_alloc_info := command_buffer_allocate_info(_ctx.frames[i].command_pool, 1)

		vk.AllocateCommandBuffers(
			_ctx.device.ptr,
			&cmd_alloc_info,
			&_ctx.frames[i].main_command_buffer,
		) or_return
	}

	return
}

engine_init_sync_structures :: proc() -> (err: Error) {
	// Create synchronization structures
	// One fence to control when the gpu has finished rendering the frame,
	// And 2 semaphores to sincronize rendering with swapchain
	// We want the fence to start signalled so we can wait on it on the first frame
	fence_create_info := fence_create_info({.SIGNALED})
	semaphore_create_info := semaphore_create_info()

	for i in 0 ..< FRAME_OVERLAP {
		vk.CreateFence(
			_ctx.device.ptr,
			&fence_create_info,
			nil,
			&_ctx.frames[i].render_fence,
		) or_return

		vk.CreateSemaphore(
			_ctx.device.ptr,
			&semaphore_create_info,
			nil,
			&_ctx.frames[i].swapchain_semaphore,
		) or_return

		vk.CreateSemaphore(
			_ctx.device.ptr,
			&semaphore_create_info,
			nil,
			&_ctx.frames[i].render_semaphore,
		) or_return
	}

	return
}

engine_destroy_swapchain :: proc() {
	vkb.swapchain_destroy_image_views(_ctx.swapchain, &_ctx.swapchain_image_views)
	delete(_ctx.swapchain_image_views)
	delete(_ctx.swapchain_images)
	vkb.destroy_swapchain(_ctx.swapchain)
}

// Shuts down the engine
engine_cleanup :: proc() {
	if _ctx.is_initialized {
		// Make sure the gpu has stopped doing its things
		vk.DeviceWaitIdle(_ctx.device.ptr)

		deletion_queue_flush(&_ctx.deletors)
		queue.destroy(&_ctx.deletors)
		for i in 0 ..< FRAME_OVERLAP {
			queue.destroy(&_ctx.frames[i].deletors)
		}

		for i in 0 ..< FRAME_OVERLAP {
			vk.DestroyCommandPool(_ctx.device.ptr, _ctx.frames[i].command_pool, nil)
			vk.DestroySemaphore(_ctx.device.ptr, _ctx.frames[i].swapchain_semaphore, nil)
			vk.DestroySemaphore(_ctx.device.ptr, _ctx.frames[i].render_semaphore, nil)
			vk.DestroyFence(_ctx.device.ptr, _ctx.frames[i].render_fence, nil)
		}

		engine_destroy_swapchain()

		vkb.destroy_device(_ctx.device)
		vkb.destroy_physical_device(_ctx.chosen_gpu)
		vkb.destroy_surface(_ctx.instance, _ctx.surface)
		vkb.destroy_instance(_ctx.instance)

		sdl.DestroyWindow(_ctx.window)
		sdl.Quit()
	}
}

engine_draw_background :: proc(cmd: vk.CommandBuffer) {
	// Make a clear-color from frame number. This will flash with a 120 frame period.
	clear_value: vk.ClearColorValue
	flash := math.abs(math.sin(f32(_ctx.frame_number / 120.0)))
	clear_value = {
		float32 = {0.0, 0.0, flash, 1.0},
	}

	clear_range := image_subresource_range({.COLOR})

	//clear image
	vk.CmdClearColorImage(cmd, _ctx.draw_image.image, .GENERAL, &clear_value, 1, &clear_range)
}

// Draw loop
engine_draw :: proc() -> (err: Error) {
	frame := engine_get_current_frame()

	// Wait until the gpu has finished rendering the last frame. Timeout of 1 second
	vk.WaitForFences(_ctx.device.ptr, 1, &frame.render_fence, true, 1000000000) or_return

	deletion_queue_flush(&frame.deletors)

	vk.ResetFences(_ctx.device.ptr, 1, &frame.render_fence) or_return

	// Request image from the swapchain
	image_index: u32 = 0
	if res := vk.AcquireNextImageKHR(
		_ctx.device.ptr,
		_ctx.swapchain.ptr,
		1000000000,
		frame.swapchain_semaphore,
		0,
		&image_index,
	); res == .ERROR_OUT_OF_DATE_KHR {
		// TODO: recreate swapchain
	} else if res != .SUCCESS && res != .SUBOPTIMAL_KHR {
		log.errorf("Failed to acquire swap chain image: [%v]", res)
		return res
	}

	cmd := frame.main_command_buffer

	// Now that we are sure that the commands finished executing, we can safely
	// Reset the command buffer to begin recording again.
	vk.ResetCommandBuffer(cmd, {}) or_return

	// Begin the command buffer recording. We will use this command buffer exactly once, so we
	// want to let vulkan know that
	cmd_begin_info := command_buffer_begin_info({.ONE_TIME_SUBMIT})

	_ctx.draw_extent.width = _ctx.draw_image.image_extent.width
	_ctx.draw_extent.height = _ctx.draw_image.image_extent.height

	// Start the command buffer recording
	vk.BeginCommandBuffer(cmd, &cmd_begin_info) or_return

	// transition our main draw image into general layout so we can write into it
	// we will overwrite it all so we dont care about what was the older layout
	transition_image(cmd, _ctx.draw_image.image, .UNDEFINED, .GENERAL)

	engine_draw_background(cmd)

	// Transition the draw image and the swapchain image into their correct transfer layouts
	transition_image(cmd, _ctx.draw_image.image, .GENERAL, .TRANSFER_SRC_OPTIMAL)
	transition_image(cmd, _ctx.swapchain_images[image_index], .UNDEFINED, .TRANSFER_DST_OPTIMAL)

	// Execute a copy from the draw image into the swapchain
	copy_image_to_image(
		cmd,
		_ctx.draw_image.image,
		_ctx.swapchain_images[image_index],
		_ctx.draw_extent,
		_ctx.swapchain.extent,
	)

	// set swapchain image layout to Present so we can show it on the screen
	transition_image(
		cmd,
		_ctx.swapchain_images[image_index],
		.TRANSFER_DST_OPTIMAL,
		.PRESENT_SRC_KHR,
	)

	// Finalize the command buffer (we can no longer add commands, but it can now be executed)
	vk.EndCommandBuffer(cmd) or_return

	// Prepare the submission to the queue.
	// We want to wait on the present_semaphore, as that semaphore is signaled when the swapchain
	// is ready. We will signal the render_semaphore, to signal that rendering has finished
	cmd_info := command_buffer_submit_info(cmd)

	wait_info := semaphore_submit_info({.COLOR_ATTACHMENT_OUTPUT}, frame.swapchain_semaphore)
	signal_info := semaphore_submit_info({.ALL_GRAPHICS}, frame.render_semaphore)

	submit_info := submit_info(&cmd_info, &signal_info, &wait_info)

	// Submit command buffer to the queue and execute it.
	// render_fence will now block until the graphic commands finish execution
	vk.QueueSubmit2(_ctx.graphics_queue, 1, &submit_info, frame.render_fence) or_return

	//prepare present
	// this will put the image we just rendered to into the visible window.
	// we want to wait on the _renderSemaphore for that,
	// as its necessary that drawing commands have finished before the image is displayed to the user
	present_info := vk.PresentInfoKHR {
		sType              = .PRESENT_INFO_KHR,
		pSwapchains        = &_ctx.swapchain.ptr,
		swapchainCount     = 1,
		pWaitSemaphores    = &frame.render_semaphore,
		waitSemaphoreCount = 1,
		pImageIndices      = &image_index,
	}

	vk.QueuePresentKHR(_ctx.graphics_queue, &present_info) or_return

	// Increase the number of frames drawn
	_ctx.frame_number += 1

	return
}

// Run main loop
engine_run :: proc() {
	e: sdl.Event

	main_loop: for {
		// Handle events on queue
		for sdl.PollEvent(&e) {
			#partial switch (e.type) {
			// close the window when user alt-f4s or clicks the X button
			case .QUIT:
				break main_loop

			case .WINDOWEVENT:
				#partial switch (e.window.event) {
				case .MINIMIZED:
					_ctx.stop_rendering = true
				case .RESTORED:
					_ctx.stop_rendering = false
				}
			}
		}

		// do not draw if we are minimized
		if _ctx.stop_rendering {
			// throttle the speed to avoid the endless spinning
			time.sleep(100 * time.Millisecond)
			continue main_loop
		}

		if res := engine_draw(); res != nil {
			log.errorf("Error while drawing frame: [%v]", res)
			break main_loop
		}
	}
}
