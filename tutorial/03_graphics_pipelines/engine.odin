package vk_guide

// Core
import intr "base:intrinsics"
import "base:runtime"
import "core:log"
import "core:math"
import la "core:math/linalg"

// Vendor
import "vendor:glfw"
import vk "vendor:vulkan"

// Libraries
import im "libs:imgui"
import im_glfw "libs:imgui/imgui_impl_glfw"
import im_vk "libs:imgui/imgui_impl_vulkan"
import "libs:vkb"
import "libs:vma"

TITLE :: "3. Graphics Pipelines"
DEFAULT_WINDOW_EXTENT :: vk.Extent2D{800, 600} // Default window size in pixels

Frame_Data :: struct {
	command_pool:          vk.CommandPool,
	main_command_buffer:   vk.CommandBuffer,
	swapchain_semaphore:   vk.Semaphore,
	render_semaphore:      vk.Semaphore,
	swapchain_image_index: u32,
	render_fence:          vk.Fence,
	deletion_queue:        ^Deletion_Queue,
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
	main_deletion_queue:          ^Deletion_Queue,

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

@(private)
g_logger: log.Logger

// Initializes everything in the engine.
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
		vk.DestroySemaphore(self.vk_device, frame.render_semaphore, nil)
		vk.DestroySemaphore(self.vk_device, frame.swapchain_semaphore, nil)

		// Flush and destroy the peer frame deletion queue
		deletion_queue_destroy(frame.deletion_queue)
	}

	for &mesh in self.test_meshes {
		destroy_buffer(self, mesh.mesh_buffers.index_buffer)
		destroy_buffer(self, mesh.mesh_buffers.vertex_buffer)
	}
	destroy_mesh_assets(&self.test_meshes)

	engine_destroy_draw_image(self)

	// Flush and destroy the global deletion queue
	deletion_queue_destroy(self.main_deletion_queue)

	im.destroy_context()

	vma.destroy_allocator(self.vma_allocator)

	engine_destroy_swapchain(self)

	vk.DestroySurfaceKHR(self.vk_instance, self.vk_surface, nil)
	vkb.destroy_device(self.vkb.device)

	vkb.destroy_physical_device(self.vkb.physical_device)
	vkb.destroy_instance(self.vkb.instance)

	destroy_window(self.window)
}

engine_init_vulkan :: proc(self: ^Engine) -> (ok: bool) {
	// Instance
	instance_builder := vkb.init_instance_builder() or_return
	defer vkb.destroy_instance_builder(&instance_builder)

	vkb.instance_set_app_name(&instance_builder, "Example Vulkan Application")
	vkb.instance_require_api_version(&instance_builder, vk.API_VERSION_1_3)

	when ODIN_DEBUG {
		vkb.instance_request_validation_layers(&instance_builder)

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

		vkb.instance_set_debug_callback(&instance_builder, default_debug_callback)
		vkb.instance_set_debug_callback_user_data_pointer(&instance_builder, self)
	}

	self.vkb.instance = vkb.build_instance(&instance_builder) or_return
	self.vk_instance = self.vkb.instance.handle
	defer if !ok {
		vkb.destroy_instance(self.vkb.instance)
	}

	// Surface
	vk_check(
		glfw.CreateWindowSurface(self.vk_instance, self.window, nil, &self.vk_surface),
	) or_return
	defer if !ok {
		vkb.destroy_surface(self.vkb.instance, self.vk_surface)
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
	selector := vkb.init_physical_device_selector(self.vkb.instance) or_return
	defer vkb.destroy_physical_device_selector(&selector)

	vkb.selector_set_minimum_version(&selector, vk.API_VERSION_1_3)
	vkb.selector_set_required_features_13(&selector, features_13)
	vkb.selector_set_required_features_12(&selector, features_12)
	vkb.selector_set_surface(&selector, self.vk_surface)

	self.vkb.physical_device = vkb.select_physical_device(&selector) or_return
	self.vk_physical_device = self.vkb.physical_device.handle
	defer if !ok {
		vkb.destroy_physical_device(self.vkb.physical_device)
	}

	// Create the final vulkan device
	device_builder := vkb.init_device_builder(self.vkb.physical_device) or_return
	defer vkb.destroy_device_builder(&device_builder)

	self.vkb.device = vkb.build_device(&device_builder) or_return
	self.vk_device = self.vkb.device.handle
	defer if !ok {
		vkb.destroy_device(self.vkb.device)
	}

	// use vk-bootstrap to get a Graphics queue
	self.graphics_queue = vkb.device_get_queue(self.vkb.device, .Graphics) or_return
	self.graphics_queue_family = vkb.device_get_queue_index(self.vkb.device, .Graphics) or_return

	// Create global deletion queue
	self.main_deletion_queue = create_deletion_queue(self.vk_device)

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
	vkb.swapchain_builder_set_present_mode(&builder, .IMMEDIATE)
	vkb.swapchain_builder_set_present_mode(&builder, .MAILBOX)
	vkb.swapchain_builder_set_desired_extent(&builder, width, height)
	vkb.swapchain_builder_add_image_usage_flags(&builder, {.TRANSFER_DST})

	if self.vkb.swapchain != nil {
		vkb.swapchain_builder_set_old_swapchain(&builder, self.vkb.swapchain)
	}

	// Build new swapchain
	swapchain := vkb.build_swapchain(&builder) or_return

	// Destroy old swapchain resources only after successful creation
	if self.vkb.swapchain != nil {
		engine_destroy_swapchain(self)
	}

	// Update engine state with new swapchain
	self.vk_swapchain = swapchain.handle
	self.vkb.swapchain = swapchain
	self.swapchain_extent = swapchain.extent
	self.swapchain_images = vkb.swapchain_get_images(self.vkb.swapchain) or_return
	self.swapchain_image_views = vkb.swapchain_get_image_views(self.vkb.swapchain) or_return

	return true
}

engine_resize_swapchain :: proc(self: ^Engine) -> (ok: bool) {
	vk_check(vk.DeviceWaitIdle(self.vk_device)) or_return

	width, height := glfw.GetFramebufferSize(self.window)
	self.window_extent = {u32(width), u32(height)}

	engine_create_swapchain(self, self.window_extent.width, self.window_extent.height) or_return
	engine_recreate_draw_image(self) or_return
	engine_update_descriptors(self)

	return true
}

engine_destroy_swapchain :: proc(self: ^Engine) {
	vkb.destroy_swapchain(self.vkb.swapchain)
	vkb.swapchain_destroy_image_views(self.vkb.swapchain, self.swapchain_image_views)
	delete(self.swapchain_image_views)
	delete(self.swapchain_images)
}

engine_recreate_draw_image :: proc(self: ^Engine) -> (ok: bool) {
	engine_destroy_draw_image(self)
	engine_create_draw_image(self) or_return
	return true
}

engine_create_draw_image :: proc(self: ^Engine) -> (ok: bool) {
	// Draw image size will match the window
	draw_image_extent := vk.Extent3D {
		width  = u32(self.swapchain_extent.width),
		height = u32(self.swapchain_extent.height),
		depth  = 1,
	}

	// Hardcoding the draw format to 32 bit float
	self.draw_image.image_format = .R16G16B16A16_SFLOAT
	self.draw_image.image_extent = draw_image_extent

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
	rimg_allocinfo := vma.Allocation_Create_Info {
		usage          = .Gpu_Only,
		required_flags = {.DEVICE_LOCAL},
	}

	// Allocate and create the image
	vk_check(
		vma.create_image(
			self.vma_allocator,
			rimg_info,
			rimg_allocinfo,
			&self.draw_image.image,
			&self.draw_image.allocation,
			nil,
		),
	) or_return
	defer if !ok {
		vma.destroy_image(self.vma_allocator, self.draw_image.image, self.draw_image.allocation)
	}

	// Build a image-view for the draw image to use for rendering
	rview_info := imageview_create_info(
		self.draw_image.image_format,
		self.draw_image.image,
		{.COLOR},
	)

	vk_check(
		vk.CreateImageView(self.vk_device, &rview_info, nil, &self.draw_image.image_view),
	) or_return
	defer if !ok {
		vk.DestroyImageView(self.vk_device, self.draw_image.image_view, nil)
	}

	self.depth_image.image_format = .D32_SFLOAT
	self.depth_image.image_extent = draw_image_extent
	depth_image_usages := vk.ImageUsageFlags{.DEPTH_STENCIL_ATTACHMENT}

	dimg_info := image_create_info(
		self.depth_image.image_format,
		depth_image_usages,
		draw_image_extent,
	)

	// Allocate and create the image
	vk_check(
		vma.create_image(
			self.vma_allocator,
			dimg_info,
			rimg_allocinfo,
			&self.depth_image.image,
			&self.depth_image.allocation,
			nil,
		),
	) or_return
	defer if !ok {
		vma.destroy_image(self.vma_allocator, self.depth_image.image, self.depth_image.allocation)
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

	return true
}

engine_destroy_draw_image :: proc(self: ^Engine) {
	if self.draw_image.image != 0 {
		vma.destroy_image(self.vma_allocator, self.draw_image.image, self.draw_image.allocation)
		self.draw_image.image = 0
	}
	if self.draw_image.image_view != 0 {
		vk.DestroyImageView(self.vk_device, self.draw_image.image_view, nil)
		self.draw_image.image_view = 0
	}
	if self.depth_image.image != 0 {
		vma.destroy_image(self.vma_allocator, self.depth_image.image, self.depth_image.allocation)
		self.depth_image.image = 0
	}
	if self.depth_image.image_view != 0 {
		vk.DestroyImageView(self.vk_device, self.depth_image.image_view, nil)
		self.depth_image.image_view = 0
	}
}

engine_init_swapchain :: proc(self: ^Engine) -> (ok: bool) {
	engine_create_swapchain(self, self.window_extent.width, self.window_extent.height) or_return
	engine_create_draw_image(self) or_return
	return true
}

engine_init_commands :: proc(self: ^Engine) -> (ok: bool) {
	// Create a command pool for commands submitted to the graphics queue. We also
	// want the pool to allow for resetting of individual command buffers.
	command_pool_info := command_pool_create_info(
		self.graphics_queue_family,
		{.RESET_COMMAND_BUFFER},
	)

	for &frame in self.frames {
		// Create peer frame deletion queue
		frame.deletion_queue = create_deletion_queue(self.vk_device)

		// Create the command pool
		vk_check(
			vk.CreateCommandPool(self.vk_device, &command_pool_info, nil, &frame.command_pool),
		) or_return

		// Allocate the default command buffer that we will use for rendering
		cmd_alloc_info := command_buffer_allocate_info(frame.command_pool)

		vk_check(
			vk.AllocateCommandBuffers(self.vk_device, &cmd_alloc_info, &frame.main_command_buffer),
		) or_return
	}

	vk_check(
		vk.CreateCommandPool(self.vk_device, &command_pool_info, nil, &self.imm_command_pool),
	) or_return

	// Allocate the command buffer for immediate submits
	cmd_alloc_info := command_buffer_allocate_info(self.imm_command_pool)
	vk_check(
		vk.AllocateCommandBuffers(self.vk_device, &cmd_alloc_info, &self.imm_command_buffer),
	) or_return

	deletion_queue_push(self.main_deletion_queue, self.imm_command_pool)

	return true
}

engine_init_sync_structures :: proc(self: ^Engine) -> (ok: bool) {
	// Create synchronization structures, one fence to control when the gpu has
	// finished rendering the frame, and 2 semaphores to sincronize rendering with
	// swapchain. We want the fence to start signalled so we can wait on it on the
	// first frame
	fence_create_info := fence_create_info({.SIGNALED})
	semaphore_create_info := semaphore_create_info()

	for &frame in self.frames {
		vk_check(
			vk.CreateFence(self.vk_device, &fence_create_info, nil, &frame.render_fence),
		) or_return

		vk_check(
			vk.CreateSemaphore(
				self.vk_device,
				&semaphore_create_info,
				nil,
				&frame.swapchain_semaphore,
			),
		) or_return
		vk_check(
			vk.CreateSemaphore(
				self.vk_device,
				&semaphore_create_info,
				nil,
				&frame.render_semaphore,
			),
		) or_return
	}

	vk_check(vk.CreateFence(self.vk_device, &fence_create_info, nil, &self.imm_fence)) or_return

	deletion_queue_push(self.main_deletion_queue, self.imm_fence)

	return true
}

engine_init_descriptors :: proc(self: ^Engine) -> (ok: bool) {
	// Create a descriptor pool that will hold 10 sets with 1 image each
	sizes := []Pool_Size_Ratio{{.STORAGE_IMAGE, 1}}

	descriptor_allocator_init_pool(
		&self.global_descriptor_allocator,
		self.vk_device,
		10,
		sizes,
	) or_return
	defer if !ok {
		descriptor_allocator_destroy_pool(&self.global_descriptor_allocator, self.vk_device)
	}

	ta := context.temp_allocator
	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()

	// Make the descriptor set layout for our compute draw
	builder: Descriptor_Layout_Builder
	descriptor_layout_builder_init(&builder, ta)
	descriptor_layout_builder_add_binding(&builder, 0, .STORAGE_IMAGE)
	self.draw_image_descriptor_layout = descriptor_layout_builder_build(
		&builder,
		self.vk_device,
		{.COMPUTE},
	) or_return
	defer if !ok {
		vk.DestroyDescriptorSetLayout(self.vk_device, self.draw_image_descriptor_layout, nil)
	}

	// Allocate a descriptor set for our draw image
	self.draw_image_descriptors = descriptor_allocator_allocate(
		&self.global_descriptor_allocator,
		self.vk_device,
		&self.draw_image_descriptor_layout,
	) or_return

	engine_update_descriptors(self)

	deletion_queue_push(self.main_deletion_queue, self.global_descriptor_allocator.pool)
	deletion_queue_push(self.main_deletion_queue, self.draw_image_descriptor_layout)

	return true
}

engine_update_descriptors :: proc(self: ^Engine) {
	img_info := vk.DescriptorImageInfo {
		imageLayout = .GENERAL,
		imageView   = self.draw_image.image_view,
	}

	draw_image_write := vk.WriteDescriptorSet {
		sType           = .WRITE_DESCRIPTOR_SET,
		dstBinding      = 0,
		dstSet          = self.draw_image_descriptors,
		descriptorCount = 1,
		descriptorType  = .STORAGE_IMAGE,
		pImageInfo      = &img_info,
	}

	vk.UpdateDescriptorSets(self.vk_device, 1, &draw_image_write, 0, nil)
}

engine_init_background_pipeline :: proc(self: ^Engine) -> (ok: bool) {
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

	vk_check(
		vk.CreatePipelineLayout(
			self.vk_device,
			&compute_layout,
			nil,
			&self.gradient_pipeline_layout,
		),
	) or_return

	gradient_color_shader := create_shader_module(
		self.vk_device,
		#load("./../../shaders/compiled/gradient_color.comp.spv"),
	) or_return
	defer vk.DestroyShaderModule(self.vk_device, gradient_color_shader, nil)

	sky_shader := create_shader_module(
		self.vk_device,
		#load("./../../shaders/compiled/sky.comp.spv"),
	) or_return
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

	deletion_queue_push(self.main_deletion_queue, self.gradient_pipeline_layout)
	deletion_queue_push(self.main_deletion_queue, gradient_color.pipeline)
	deletion_queue_push(self.main_deletion_queue, sky.pipeline)

	return true
}

engine_init_mesh_pipeline :: proc(self: ^Engine) -> (ok: bool) {
	triangle_frag_shader := create_shader_module(
		self.vk_device,
		#load("./../../shaders/compiled/colored_triangle.frag.spv"),
	) or_return
	defer vk.DestroyShaderModule(self.vk_device, triangle_frag_shader, nil)

	triangle_vertex_shader := create_shader_module(
		self.vk_device,
		#load("./../../shaders/compiled/colored_triangle_mesh.vert.spv"),
	) or_return
	defer vk.DestroyShaderModule(self.vk_device, triangle_vertex_shader, nil)

	buffer_range := vk.PushConstantRange {
		offset     = 0,
		size       = size_of(GPU_Draw_Push_Constants),
		stageFlags = {.VERTEX},
	}

	pipeline_layout_info := pipeline_layout_create_info()
	pipeline_layout_info.pPushConstantRanges = &buffer_range
	pipeline_layout_info.pushConstantRangeCount = 1

	vk_check(
		vk.CreatePipelineLayout(
			self.vk_device,
			&pipeline_layout_info,
			nil,
			&self.mesh_pipeline_layout,
		),
	) or_return
	deletion_queue_push(self.main_deletion_queue, self.mesh_pipeline_layout)

	builder := pipeline_builder_create_default()

	// Use the triangle layout we created
	builder.pipeline_layout = self.mesh_pipeline_layout
	// Add the vertex and pixel shaders to the pipeline
	pipeline_builder_set_shaders(&builder, triangle_vertex_shader, triangle_frag_shader)
	// It will draw triangles
	pipeline_builder_set_input_topology(&builder, .TRIANGLE_LIST)
	// Filled triangles
	pipeline_builder_set_polygon_mode(&builder, .FILL)
	// No backface culling
	pipeline_builder_set_cull_mode(&builder, vk.CullModeFlags_NONE, .CLOCKWISE)
	// No multisampling
	pipeline_builder_set_multisampling_none(&builder)
	// No blending
	// pipeline_builder_disable_blending(&builder)
	pipeline_builder_enable_blending_additive(&builder)
	// No depth testing
	// pipeline_builder_disable_depth_test(&builder)
	pipeline_builder_enable_depth_test(&builder, true, .GREATER_OR_EQUAL)

	// Connect the image format we will draw into, from draw image
	pipeline_builder_set_color_attachment_format(&builder, self.draw_image.image_format)
	pipeline_builder_set_depth_attachment_format(&builder, self.depth_image.image_format)

	// Finally build the pipeline
	self.mesh_pipeline = pipeline_builder_build(&builder, self.vk_device) or_return
	deletion_queue_push(self.main_deletion_queue, self.mesh_pipeline)

	return true
}

engine_init_pipelines :: proc(self: ^Engine) -> (ok: bool) {
	// Compute pipelines
	engine_init_background_pipeline(self) or_return

	// Graphics pipelines
	// engine_init_triangle_pipeline(self) or_return
	engine_init_mesh_pipeline(self) or_return

	return true
}

engine_immediate_submit :: proc(
	self: ^Engine,
	data: $T,
	fn: proc(engine: ^Engine, cmd: vk.CommandBuffer, data: T),
) -> (
	ok: bool,
) {
	vk_check(vk.ResetFences(self.vk_device, 1, &self.imm_fence)) or_return
	vk_check(vk.ResetCommandBuffer(self.imm_command_buffer, {})) or_return

	cmd := self.imm_command_buffer

	cmd_begin_info := command_buffer_begin_info({.ONE_TIME_SUBMIT})

	vk_check(vk.BeginCommandBuffer(cmd, &cmd_begin_info)) or_return

	fn(self, cmd, data)

	vk_check(vk.EndCommandBuffer(cmd)) or_return

	cmd_info := command_buffer_submit_info(cmd)
	submit_info := submit_info(&cmd_info, nil, nil)

	// Submit command buffer to the queue and execute it.
	//  `render_fence` will now block until the graphic commands finish execution
	vk_check(vk.QueueSubmit2(self.graphics_queue, 1, &submit_info, self.imm_fence)) or_return

	vk_check(vk.WaitForFences(self.vk_device, 1, &self.imm_fence, true, 9999999999)) or_return

	return true
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
	im.create_context()
	defer if !ok {im.destroy_context()}

	// This initializes imgui for GLFW
	im_glfw.init_for_vulkan(self.window, true) or_return
	defer if !ok {im_glfw.shutdown()}

	// This initializes imgui for Vulkan
	init_info := im_vk.Init_Info {
		instance = self.vk_instance,
		physical_device = self.vk_physical_device,
		device = self.vk_device,
		queue = self.graphics_queue,
		descriptor_pool = imgui_pool,
		min_image_count = 3,
		image_count = 3,
		use_dynamic_rendering = true,
		pipeline_rendering_create_info = {
			sType = .PIPELINE_RENDERING_CREATE_INFO,
			colorAttachmentCount = 1,
			pColorAttachmentFormats = &self.swapchain_format,
		},
		msaa_samples = ._1,
	}

	im_vk.load_functions(
		proc "c" (function_name: cstring, user_data: rawptr) -> vk.ProcVoidFunction {
			engine := cast(^Engine)user_data
			return vk.GetInstanceProcAddr(engine.vk_instance, function_name)
		},
		self,
	) or_return

	im_vk.init(&init_info) or_return
	defer if !ok {im_vk.shutdown()}

	deletion_queue_push(self.main_deletion_queue, imgui_pool)
	deletion_queue_push(self.main_deletion_queue, im_vk.shutdown)
	deletion_queue_push(self.main_deletion_queue, im_glfw.shutdown)

	return true
}

engine_init_default_data :: proc(self: ^Engine) -> (ok: bool) {
	self.test_meshes = load_gltf_meshes(self, "assets/basicmesh.glb") or_return
	defer if !ok {
		destroy_mesh_assets(&self.test_meshes)
	}

	return true
}

engine_get_current_frame :: #force_inline proc(self: ^Engine) -> ^Frame_Data #no_bounds_check {
	return &self.frames[self.frame_number % FRAME_OVERLAP]
}

engine_draw_background :: proc(self: ^Engine, cmd: vk.CommandBuffer) -> (ok: bool) {
	effect := &self.background_effects[self.current_background_effect]

	// Bind the gradient drawing compute pipeline
	vk.CmdBindPipeline(cmd, .COMPUTE, effect.pipeline)

	// Bind the descriptor set containing the draw image for the compute pipeline
	vk.CmdBindDescriptorSets(
		cmd,
		.COMPUTE,
		self.gradient_pipeline_layout,
		0,
		1,
		&self.draw_image_descriptors,
		0,
		nil,
	)

	vk.CmdPushConstants(
		cmd,
		self.gradient_pipeline_layout,
		{.COMPUTE},
		0,
		size_of(Compute_Push_Constants),
		&effect.data,
	)

	// Execute the compute pipeline dispatch. We are using 16x16 workgroup size so
	// we need to divide by it
	vk.CmdDispatch(
		cmd,
		u32(math.ceil_f32(f32(self.draw_extent.width) / 16.0)),
		u32(math.ceil_f32(f32(self.draw_extent.height) / 16.0)),
		1,
	)

	return true
}

engine_ui_definition :: proc(self: ^Engine) {
	// imgui new frame
	im_glfw.new_frame()
	im_vk.new_frame()
	im.new_frame()

	if im.begin("Background", nil, {.Always_Auto_Resize}) {
		im.slider_float("Render scale", &self.render_scale, 0.3, 1.0)

		selected := &self.background_effects[self.current_background_effect]

		im.text("Selected effect: %s", selected.name)

		@(static) current_background_effect: i32
		current_background_effect = i32(self.current_background_effect)

		// If the combo is opened and an item is selected, update the current effect
		if im.begin_combo("Effect", selected.name) {
			for effect, i in self.background_effects {
				is_selected := i32(i) == current_background_effect
				if im.selectable(effect.name, is_selected) {
					current_background_effect = i32(i)
					self.current_background_effect = Compute_Effect_Kind(current_background_effect)
				}

				// Set initial focus when the currently selected item becomes visible
				if is_selected {
					im.set_item_default_focus()
				}
			}
			im.end_combo()
		}

		im.input_float4("data1", &selected.data.data1)
		im.input_float4("data2", &selected.data.data2)
		im.input_float4("data3", &selected.data.data3)
		im.input_float4("data4", &selected.data.data4)

	}
	im.end()

	//make imgui calculate internal draw structures
	im.render()
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

	frame := engine_get_current_frame(self)

	// Wait until the gpu has finished rendering the last frame. Timeout of 1 second
	vk_check(vk.WaitForFences(self.vk_device, 1, &frame.render_fence, true, max(u64))) or_return
	vk_check(vk.ResetFences(self.vk_device, 1, &frame.render_fence)) or_return

	// Request image from the swapchain
	if result := vk.AcquireNextImageKHR(
		self.vk_device,
		self.vk_swapchain,
		max(u64),
		frame.swapchain_semaphore,
		0,
		&frame.swapchain_image_index,
	); result == .ERROR_OUT_OF_DATE_KHR {
		engine_resize_swapchain(self) or_return
	}

	// The the current command buffer, naming it cmd for shorter writing
	cmd := engine_get_current_frame(self).main_command_buffer

	// Now that we are sure that the commands finished executing, we can safely
	// reset the command buffer to begin recording again.
	vk_check(vk.ResetCommandBuffer(cmd, {})) or_return

	// Begin the command buffer recording. We will use this command buffer exactly
	// once, so we want to let vulkan know that
	cmd_begin_info := command_buffer_begin_info({.ONE_TIME_SUBMIT})

	self.draw_extent = {
		width  = u32(
			f32(min(self.swapchain_extent.width, self.draw_image.image_extent.width)) *
			self.render_scale,
		),
		height = u32(
			f32(min(self.swapchain_extent.height, self.draw_image.image_extent.height)) *
			self.render_scale,
		),
	}

	// Start the command buffer recording
	vk_check(vk.BeginCommandBuffer(cmd, &cmd_begin_info)) or_return

	// Transition our main draw image into general layout so we can write into it
	// we will overwrite it all so we dont care about what was the older layout
	transition_image(cmd, self.draw_image.image, .UNDEFINED, .GENERAL)

	// Clear the image
	engine_draw_background(self, cmd) or_return

	transition_image(cmd, self.draw_image.image, .GENERAL, .COLOR_ATTACHMENT_OPTIMAL)
	transition_image(cmd, self.depth_image.image, .UNDEFINED, .DEPTH_ATTACHMENT_OPTIMAL)

	// Draw the triangle
	engine_draw_geometry(self, cmd) or_return

	// Transition the draw image and the swapchain image into their correct transfer layouts
	transition_image(cmd, self.draw_image.image, .COLOR_ATTACHMENT_OPTIMAL, .TRANSFER_SRC_OPTIMAL)
	transition_image(
		cmd,
		self.swapchain_images[frame.swapchain_image_index],
		.UNDEFINED,
		.TRANSFER_DST_OPTIMAL,
	)

	copy_image_to_image(
		cmd,
		self.draw_image.image,
		self.swapchain_images[frame.swapchain_image_index],
		self.draw_extent,
		self.swapchain_extent,
	)

	// Set swapchain image layout to Attachment Optimal so we can draw it
	transition_image(
		cmd,
		self.swapchain_images[frame.swapchain_image_index],
		.TRANSFER_DST_OPTIMAL,
		.COLOR_ATTACHMENT_OPTIMAL,
	)

	// Draw imgui into the swapchain image
	engine_draw_imgui(self, cmd, self.swapchain_image_views[frame.swapchain_image_index])

	// Set swapchain image layout to Present so we can show it on the screen
	transition_image(
		cmd,
		self.swapchain_images[frame.swapchain_image_index],
		.COLOR_ATTACHMENT_OPTIMAL,
		.PRESENT_SRC_KHR,
	)

	// Finalize the command buffer (we can no longer add commands, but it can now be executed)
	vk_check(vk.EndCommandBuffer(cmd)) or_return

	// Prepare the submission to the queue. we want to wait on the
	// `swapchain_semaphore`, as that semaphore is signaled when the swapchain is
	// ready we will signal the `render_semaphore`, to signal that rendering has
	// finished

	cmd_info := command_buffer_submit_info(cmd)
	signal_info := semaphore_submit_info({.ALL_GRAPHICS}, frame.render_semaphore)
	wait_info := semaphore_submit_info({.COLOR_ATTACHMENT_OUTPUT_KHR}, frame.swapchain_semaphore)

	submit := submit_info(&cmd_info, &signal_info, &wait_info)

	// Submit command buffer to the queue and execute it. _renderFence will now
	// block until the graphic commands finish execution
	vk_check(vk.QueueSubmit2(self.graphics_queue, 1, &submit, frame.render_fence)) or_return

	// Prepare present
	//
	// this will put the image we just rendered to into the visible window. we
	// want to wait on the `render_semaphore` for that, as its necessary that
	// drawing commands have finished before the image is displayed to the user
	present_info := vk.PresentInfoKHR {
		sType              = .PRESENT_INFO_KHR,
		pSwapchains        = &self.vk_swapchain,
		swapchainCount     = 1,
		pWaitSemaphores    = &frame.render_semaphore,
		waitSemaphoreCount = 1,
		pImageIndices      = &frame.swapchain_image_index,
	}

	if result := vk.QueuePresentKHR(self.graphics_queue, &present_info);
	   result == .ERROR_OUT_OF_DATE_KHR {
		engine_resize_swapchain(self) or_return
	}

	// Increase the number of frames drawn
	self.frame_number += 1

	return true
}

engine_draw_imgui :: proc(
	self: ^Engine,
	cmd: vk.CommandBuffer,
	target_view: vk.ImageView,
) -> (
	ok: bool,
) {
	if data := im.get_draw_data(); data != nil {
		color_attachment := attachment_info(target_view, nil, .GENERAL)
		render_info := rendering_info(self.swapchain_extent, &color_attachment, nil)

		vk.CmdBeginRendering(cmd, &render_info)

		im_vk.render_draw_data(im.get_draw_data(), cmd)

		vk.CmdEndRendering(cmd)
	}

	return true
}

engine_draw_geometry :: proc(self: ^Engine, cmd: vk.CommandBuffer) -> (ok: bool) {
	// Begin a render pass connected to our draw image
	color_attachment := attachment_info(self.draw_image.image_view, nil, .COLOR_ATTACHMENT_OPTIMAL)
	depth_attachment := depth_attachment_info(
		self.depth_image.image_view,
		.DEPTH_ATTACHMENT_OPTIMAL,
	)

	render_info := rendering_info(self.draw_extent, &color_attachment, &depth_attachment)
	vk.CmdBeginRendering(cmd, &render_info)

	vk.CmdBindPipeline(cmd, .GRAPHICS, self.mesh_pipeline)

	// Set dynamic viewport and scissor
	viewport := vk.Viewport {
		x        = 0,
		y        = 0,
		width    = f32(self.draw_extent.width),
		height   = f32(self.draw_extent.height),
		minDepth = 0.0,
		maxDepth = 1.0,
	}

	vk.CmdSetViewport(cmd, 0, 1, &viewport)

	scissor := vk.Rect2D {
		offset = {x = 0, y = 0},
		extent = {width = self.draw_extent.width, height = self.draw_extent.height},
	}

	vk.CmdSetScissor(cmd, 0, 1, &scissor)

	matrix4_perspective_reverse_z_f32 :: proc "contextless" (
		fovy, aspect, near: f32,
		flip_y_axis := true,
	) -> (
		m: la.Matrix4f32,
	) #no_bounds_check {
		epsilon :: 0.00000095367431640625 // 2^-20 or about 10^-6
		fov_scale := 1 / math.tan(fovy * 0.5)

		m[0, 0] = fov_scale / aspect
		m[1, 1] = fov_scale

		// Set up reverse-Z configuration
		m[2, 2] = epsilon
		m[2, 3] = near * (1 - epsilon)
		m[3, 2] = -1

		// Handle Vulkan Y-flip if needed
		if flip_y_axis {
			m[1, 1] = -m[1, 1]
		}

		return
	}

	// Create view matrix - place camera at positive Z looking at origin
	view := la.matrix4_translate_f32({0, 0, -5})

	// Create infinite perspective projection matrix with REVERSED depth
	projection := matrix4_perspective_reverse_z_f32(
		f32(la.to_radians(70.0)),
		f32(self.draw_extent.width) / f32(self.draw_extent.height),
		0.1,
		true, // Invert the Y direction to match OpenGL and glTF axis conventions
	)

	// Monkey - ensure matrix order matches shader expectations
	push_constants := GPU_Draw_Push_Constants {
		world_matrix  = projection * view,
		vertex_buffer = self.test_meshes[2].mesh_buffers.vertex_buffer_address,
	}

	vk.CmdPushConstants(
		cmd,
		self.mesh_pipeline_layout,
		{.VERTEX},
		0,
		size_of(GPU_Draw_Push_Constants),
		&push_constants,
	)
	vk.CmdBindIndexBuffer(cmd, self.test_meshes[2].mesh_buffers.index_buffer.buffer, 0, .UINT32)

	vk.CmdDrawIndexed(
		cmd,
		self.test_meshes[2].surfaces[0].count,
		1,
		self.test_meshes[2].surfaces[0].start_index,
		0,
		0,
	)

	vk.CmdEndRendering(cmd)

	return true
}

// Run main loop.
@(require_results)
engine_run :: proc(self: ^Engine) -> (ok: bool) {
	monitor_info := get_primary_monitor_info()

	t: Timer
	timer_init(&t, monitor_info.refresh_rate)

	log.info("Entering main loop...")

	for !glfw.WindowShouldClose(self.window) {
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
