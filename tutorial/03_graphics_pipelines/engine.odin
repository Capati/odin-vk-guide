package vk_guide

// Core
import "core:log"

// Vendor
import "vendor:glfw"
import vk "vendor:vulkan"

// Libraries
import "libs:vkb"
import "libs:vma"

TITLE :: "3. Graphics Pipelines"
DEFAULT_WINDOW_EXTENT :: vk.Extent2D{1280, 678} // Default window size in pixels

Frame_Data :: struct {
	command_pool:          vk.CommandPool,
	main_command_buffer:   vk.CommandBuffer,
	swapchain_semaphore:   vk.Semaphore,
	render_semaphore:      vk.Semaphore,
	swapchain_image_index: u32,
	render_fence:          vk.Fence,
	deletion_queue:        Deletion_Queue,
}

FRAME_OVERLAP :: 2

Compute_Push_Constants :: struct {
	data1: [4]f32,
	data2: [4]f32,
	data3: [4]f32,
	data4: [4]f32,
}

Compute_Effect_Kind :: enum {
	Gradient,
	Sky,
}

Compute_Effect :: struct {
	name:     cstring,
	pipeline: vk.Pipeline,
	layout:   vk.PipelineLayout,
	data:     Compute_Push_Constants,
}

Engine :: struct {
	// Initialization state
	is_initialized:               bool,
	stop_rendering:               bool,

	// Core Vulkan handles
	vk_instance:                  vk.Instance,
	vk_physical_device:           vk.PhysicalDevice,
	vk_device:                    vk.Device,
	vk_surface:                   vk.SurfaceKHR,

	// Window and display
	window:                       glfw.WindowHandle,
	window_extent:                vk.Extent2D,

	// Queue management
	graphics_queue:               vk.Queue,
	graphics_queue_family:        u32,

	// Swapchain
	vk_swapchain:                 vk.SwapchainKHR,
	swapchain_extent:             vk.Extent2D,
	swapchain_format:             vk.Format,
	swapchain_images:             []vk.Image,
	swapchain_image_views:        []vk.ImageView,

	// Frame management
	frames:                       [FRAME_OVERLAP]Frame_Data,
	frame_number:                 int,

	// Memory management
	vma_allocator:                vma.Allocator,
	main_deletion_queue:          Deletion_Queue,

	// Descriptor management
	global_descriptor_allocator:  Descriptor_Allocator,
	draw_image_descriptors:       vk.DescriptorSet,
	draw_image_descriptor_layout: vk.DescriptorSetLayout,

	// immediate submit structures
	imm_fence:                    vk.Fence,
	imm_command_buffer:           vk.CommandBuffer,
	imm_command_pool:             vk.CommandPool,

	// Rendering resources
	draw_image:                   Allocated_Image,
	depth_image:                  Allocated_Image,
	draw_extent:                  vk.Extent2D,
	render_scale:                 f32,
	gradient_pipeline_layout:     vk.PipelineLayout,
	background_effects:           [Compute_Effect_Kind]Compute_Effect,
	current_background_effect:    Compute_Effect_Kind,
	mesh_pipeline_layout:         vk.PipelineLayout,
	mesh_pipeline:                vk.Pipeline,
	test_meshes:                  Mesh_Asset_List,

	// Helper libraries
	vkb:                          struct {
		instance:        ^vkb.Instance,
		physical_device: ^vkb.Physical_Device,
		device:          ^vkb.Device,
		swapchain:       ^vkb.Swapchain,
	},
}

// Run main loop.
@(require_results)
engine_run :: proc(self: ^Engine) -> (ok: bool) {
	monitor_info := get_primary_monitor_info()

	t: Timer
	timer_init(&t, monitor_info.refresh_rate)

	log.info("Entering main loop...")

	for !glfw.WindowShouldClose(self.window) {
		engine_acquire_next_image(self) or_return

		glfw.PollEvents()

		if self.stop_rendering {
			glfw.WaitEvents()
			timer_init(&t, monitor_info.refresh_rate) // Reset timer after wait
			continue
		}

		// Advance timer and set for FPS update
		timer_tick(&t)

		engine_ui_definition(self)

		engine_draw(self) or_return

		when ODIN_DEBUG {
			if timer_check_fps_updated(t) {
				window_update_title_with_fps(self.window, TITLE, timer_get_fps(t))
			}
		}
	}

	log.info("Exiting...")

	return true
}
