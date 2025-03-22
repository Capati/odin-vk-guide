package vk_guide

// Core
import "core:log"
import la "core:math/linalg"

// Vendor
import "vendor:glfw"
import vk "vendor:vulkan"

// Libraries
import "libs:vkb"
import "libs:vma"

TITLE :: "4. Textures and Engine Architecture"
DEFAULT_WINDOW_EXTENT :: vk.Extent2D{1280, 678} // Default window size in pixels

Frame_Data :: struct {
	command_pool:          vk.CommandPool,
	main_command_buffer:   vk.CommandBuffer,
	swapchain_semaphore:   vk.Semaphore,
	render_semaphore:      vk.Semaphore,
	swapchain_image_index: u32,
	render_fence:          vk.Fence,
	deletion_queue:        Deletion_Queue,
	frame_descriptors:     Descriptor_Allocator_Growable,
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

GPU_Scene_Data :: struct {
	view:               la.Matrix4x4f32,
	proj:               la.Matrix4x4f32,
	viewproj:           la.Matrix4x4f32,
	ambient_color:      la.Vector4f32,
	sunlight_direction: la.Vector4f32, // w for sun power
	sunlight_color:     la.Vector4f32,
}

Engine :: struct {
	// Initialization state
	is_initialized:                   bool,
	stop_rendering:                   bool,

	// Core Vulkan handles
	vk_instance:                      vk.Instance,
	vk_physical_device:               vk.PhysicalDevice,
	vk_device:                        vk.Device,
	vk_surface:                       vk.SurfaceKHR,

	// Window and display
	window:                           glfw.WindowHandle,
	window_extent:                    vk.Extent2D,

	// Queue management
	graphics_queue:                   vk.Queue,
	graphics_queue_family:            u32,

	// Swapchain
	vk_swapchain:                     vk.SwapchainKHR,
	swapchain_extent:                 vk.Extent2D,
	swapchain_format:                 vk.Format,
	swapchain_images:                 []vk.Image,
	swapchain_image_views:            []vk.ImageView,

	// Frame management
	frames:                           [FRAME_OVERLAP]Frame_Data,
	frame_number:                     int,

	// Memory management
	vma_allocator:                    vma.Allocator,
	main_deletion_queue:              Deletion_Queue,

	// Descriptor management
	global_descriptor_allocator:      Descriptor_Allocator,
	draw_image_descriptors:           vk.DescriptorSet,
	draw_image_descriptor_layout:     vk.DescriptorSetLayout,

	// immediate submit structures
	imm_fence:                        vk.Fence,
	imm_command_buffer:               vk.CommandBuffer,
	imm_command_pool:                 vk.CommandPool,

	// Rendering resources
	draw_image:                       Allocated_Image,
	depth_image:                      Allocated_Image,
	draw_extent:                      vk.Extent2D,
	render_scale:                     f32,
	gradient_pipeline_layout:         vk.PipelineLayout,
	background_effects:               [Compute_Effect_Kind]Compute_Effect,
	current_background_effect:        Compute_Effect_Kind,
	mesh_pipeline_layout:             vk.PipelineLayout,
	mesh_pipeline:                    vk.Pipeline,
	test_meshes:                      Mesh_Asset_List,

	// Scene
	main_draw_context:                Draw_Context,
	loaded_nodes:                     map[string]^Node,
	scene_data:                       GPU_Scene_Data,
	gpu_scene_data_descriptor_layout: vk.DescriptorSetLayout,

	// Textures
	white_image:                      Allocated_Image,
	black_image:                      Allocated_Image,
	grey_image:                       Allocated_Image,
	error_checkerboard_image:         Allocated_Image,
	default_sampler_linear:           vk.Sampler,
	default_sampler_nearest:          vk.Sampler,
	single_image_descriptor_layout:   vk.DescriptorSetLayout,

	// Materials
	default_material_data:            Material_Instance,
	metal_rough_material:             Metallic_Roughness,

	// Helper libraries
	vkb:                              struct {
		instance:        ^vkb.Instance,
		physical_device: ^vkb.Physical_Device,
		device:          ^vkb.Device,
		swapchain:       ^vkb.Swapchain,
	},
}

// Updates the scene state and prepares render objects.
engine_update_scene :: proc(self: ^Engine) {
	// Clear previous render objects
	clear(&self.main_draw_context.opaque_surfaces)

	// Draw the Suzanne mesh
	if suzanne, ok := self.loaded_nodes["Suzanne"]; ok {
		suzanne.draw(suzanne, la.MATRIX4F32_IDENTITY, &self.main_draw_context)
	}

	// Draw a line of cubes
	if cube, ok := self.loaded_nodes["Cube"]; ok {
		for x := -3; x < 3; x += 1 {
			scale := la.matrix4_scale(la.Vector3f32{0.2, 0.2, 0.2})
			translation := la.matrix4_translate(la.Vector3f32{f32(x), 1, 0})
			cube.draw(cube, translation * scale, &self.main_draw_context)
		}
	}

	// Set up Camera
	aspect := f32(self.window_extent.width) / f32(self.window_extent.height)
	self.scene_data.view = la.matrix4_translate_f32({0, 0, -5})
	self.scene_data.proj = matrix4_perspective_reverse_z_f32(
		f32(la.to_radians(70.0)),
		aspect,
		0.1,
		true, // Invert the Y direction to match OpenGL and glTF axis conventions
	)
	self.scene_data.viewproj = la.matrix_mul(self.scene_data.proj, self.scene_data.view)

	// Default lighting parameters
	self.scene_data.ambient_color = {0.1, 0.1, 0.1, 1.0}
	self.scene_data.sunlight_color = {1.0, 1.0, 1.0, 1.0}
	self.scene_data.sunlight_direction = {0, 1, 0.5, 1.0}
}

// Run main loop.
@(require_results)
engine_run :: proc(self: ^Engine) -> (ok: bool) {
	monitor_info := get_primary_monitor_info()
	t: Timer
	timer_init(&t, monitor_info.refresh_rate)

	log.info("Entering main loop...")

	for !glfw.WindowShouldClose(self.window) {
		if !self.stop_rendering {
			engine_acquire_next_image(self) or_return
		}

		timer_tick(&t)
		engine_ui_definition(self)
		engine_update_scene(self)

		if self.stop_rendering {
			glfw.WaitEvents()
			timer_init(&t, monitor_info.refresh_rate)
			continue
		}

		engine_draw(self) or_return

		when ODIN_DEBUG {
			if timer_check_fps_updated(t) {
				window_update_title_with_fps(self.window, TITLE, timer_get_fps(t))
			}
		}

		glfw.PollEvents()
	}

	log.info("Exiting...")

	return true
}
