package main

// Core
import "core:log"
import "core:time"

// Vendor
import sdl "vendor:sdl2"
import vk "vendor:vulkan"

// Libs
import "libs:vk-bootstrap/vkb"

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
}

Frame_Data :: struct {
	command_pool:        vk.CommandPool,
	main_command_buffer: vk.CommandBuffer,
}

FRAME_OVERLAP: u32 : 2

@(private)
_engine: Engine

// Initializes everything in the engine
engine_init :: proc() -> (err: Error) {
	// We initialize SDL and create a window with it.
	if res := sdl.Init({.VIDEO}); res != 0 {
		log.errorf("Failed to initialize SDL: [%s]", sdl.GetError())
		return .SDL_Init_Failed
	}
	defer if err != nil do sdl.Quit()

	window_flags: sdl.WindowFlags = {.VULKAN}

	_engine.window_extent = {800, 600}

	_engine.window = sdl.CreateWindow(
		"Vulkan Engine",
		sdl.WINDOWPOS_UNDEFINED,
		sdl.WINDOWPOS_UNDEFINED,
		i32(_engine.window_extent.width),
		i32(_engine.window_extent.height),
		window_flags,
	)

	if _engine.window == nil {
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

	engine_init_sync_structures()

	// everything went fine
	_engine.is_initialized = true

	return
}

engine_init_vulkan :: proc() -> (err: Error) {
	// Instance
	inst_b := vkb.init_instance_builder() or_return
	defer vkb.destroy_instance_builder(&inst_b)

	vkb.instance_set_app_name(&inst_b, "Example Vulkan Application")
	vkb.instance_request_validation_layers(&inst_b)
	vkb.instance_use_default_debug_messenger(&inst_b)
	vkb.instance_require_api_version(&inst_b, vk.API_VERSION_1_3)

	_engine.instance = vkb.build_instance(&inst_b) or_return
	defer if err != nil do vkb.destroy_instance(_engine.instance)

	// Surface
	if !sdl.Vulkan_CreateSurface(_engine.window, _engine.instance.ptr, &_engine.surface) {
		log.errorf("SDL couldn't create vulkan surface: %s", sdl.GetError())
		return
	}
	defer if err != nil do vkb.destroy_surface(_engine.instance, _engine.surface)

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
	selector := vkb.init_physical_device_selector(_engine.instance) or_return
	defer vkb.destroy_physical_device_selector(&selector)

	vkb.selector_set_minimum_version(&selector, vk.API_VERSION_1_3)
	vkb.selector_set_required_features_13(&selector, features_13)
	vkb.selector_set_required_features_12(&selector, features_12)
	vkb.selector_set_surface(&selector, _engine.surface)

	_engine.chosen_gpu = vkb.select_physical_device(&selector) or_return
	defer if err != nil do vkb.destroy_physical_device(_engine.chosen_gpu)

	// Create the final vulkan device
	device_builder := vkb.init_device_builder(_engine.chosen_gpu) or_return
	defer vkb.destroy_device_builder(&device_builder)

	_engine.device = vkb.build_device(&device_builder) or_return
	defer if err != nil do vkb.destroy_device(_engine.device)

	// use vk-bootstrap to get a Graphics queue
	_engine.graphics_queue = vkb.device_get_queue(_engine.device, .Graphics) or_return
	_engine.graphics_queue_family = vkb.device_get_queue_index(_engine.device, .Graphics) or_return

	return
}

engine_create_swapchain :: proc(width, height: u32) -> (err: Error) {
	_engine.swapchain_format = .B8G8R8A8_UNORM

	builder := vkb.init_swapchain_builder(_engine.device) or_return
	defer vkb.destroy_swapchain_builder(&builder)

	vkb.swapchain_builder_set_desired_format(
		&builder,
		{format = _engine.swapchain_format, colorSpace = .SRGB_NONLINEAR},
	)
	vkb.swapchain_builder_set_present_mode(&builder, .FIFO)
	vkb.swapchain_builder_set_desired_extent(&builder, width, height)
	vkb.swapchain_builder_add_image_usage_flags(&builder, {.TRANSFER_DST})

	_engine.swapchain = vkb.build_swapchain(&builder) or_return

	_engine.swapchain_images = vkb.swapchain_get_images(_engine.swapchain) or_return
	_engine.swapchain_image_views = vkb.swapchain_get_image_views(_engine.swapchain) or_return

	return
}

engine_init_swapchain :: proc() -> (err: Error) {
	return engine_create_swapchain(_engine.window_extent.width, _engine.window_extent.height)
}

engine_get_current_frame :: proc() -> Frame_Data {
	return _engine.frames[_engine.frame_number % FRAME_OVERLAP]
}

engine_init_commands :: proc() -> (err: Error) {
	//create a command pool for commands submitted to the graphics queue.
	//we also want the pool to allow for resetting of individual command buffers
	command_pool_info := command_pool_create_info(
		_engine.graphics_queue_family,
		{.RESET_COMMAND_BUFFER},
	)

	for i in 0 ..< FRAME_OVERLAP {
		if res := vk.CreateCommandPool(
			_engine.device.ptr,
			&command_pool_info,
			nil,
			&_engine.frames[i].command_pool,
		); res != .SUCCESS {
			log.errorf("Failed to create command pool for frame [%d]: [%v]", i, res)
			return .Vulkan_Create_Error
		}

		// allocate the default command buffer that we will use for rendering
		cmd_alloc_info := command_buffer_allocate_info(_engine.frames[i].command_pool, 1)

		if res := vk.AllocateCommandBuffers(
			_engine.device.ptr,
			&cmd_alloc_info,
			&_engine.frames[i].main_command_buffer,
		); res != .SUCCESS {
			log.errorf("Failed to allocate command buffers for frame [%d]: [%v]", i, res)
			return .Vulkan_Allocate_Error
		}
	}

	return
}

engine_init_sync_structures :: proc() {

}

engine_destroy_swapchain :: proc() {
	vkb.swapchain_destroy_image_views(_engine.swapchain, &_engine.swapchain_image_views)
	delete(_engine.swapchain_image_views)
	delete(_engine.swapchain_images)
	vkb.destroy_swapchain(_engine.swapchain)
}

// Shuts down the engine
engine_cleanup :: proc() {
	if _engine.is_initialized {
		//make sure the gpu has stopped doing its things
		vk.DeviceWaitIdle(_engine.device.ptr)

		for i in 0 ..< FRAME_OVERLAP {
			vk.DestroyCommandPool(_engine.device.ptr, _engine.frames[i].command_pool, nil)
		}

		engine_destroy_swapchain()
		vkb.destroy_device(_engine.device)
		vkb.destroy_physical_device(_engine.chosen_gpu)
		vkb.destroy_surface(_engine.instance, _engine.surface)
		vkb.destroy_instance(_engine.instance)

		sdl.DestroyWindow(_engine.window)
		sdl.Quit()
	}
}

// Draw loop
engine_draw :: proc() {
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
					_engine.stop_rendering = true
				case .RESTORED:
					_engine.stop_rendering = false
				}
			}
		}

		// do not draw if we are minimized
		if _engine.stop_rendering {
			// throttle the speed to avoid the endless spinning
			time.sleep(100 * time.Millisecond)
			continue main_loop
		}

		engine_draw()
	}
}
