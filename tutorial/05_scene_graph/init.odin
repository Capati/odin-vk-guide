package vk_guide

// Core
import "base:runtime"
import sa "core:container/small_array"
import "core:log"
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
		vk.DestroySemaphore(self.vk_device, frame.render_semaphore, nil)
		vk.DestroySemaphore(self.vk_device, frame.swapchain_semaphore, nil)

		// Flush and destroy the peer frame deletion queue
		deletion_queue_destroy(&frame.deletion_queue)
	}

	// Flush and destroy the global deletion queue
	deletion_queue_destroy(&self.main_deletion_queue)

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
	selector := vkb.init_physical_device_selector(self.vkb.instance) or_return
	defer vkb.destroy_physical_device_selector(&selector)

	vkb.selector_set_minimum_version(&selector, vk.API_VERSION_1_3)
	vkb.selector_set_required_features_13(&selector, features_13)
	vkb.selector_set_required_features_12(&selector, features_12)
	vkb.selector_set_required_features_11(&selector, features_11)
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

	// Initialize global deletion queue
	deletion_queue_init(&self.main_deletion_queue, self.vk_device)

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

	return true
}

engine_destroy_swapchain :: proc(self: ^Engine) {
	vkb.destroy_swapchain(self.vkb.swapchain)
	vkb.swapchain_destroy_image_views(self.vkb.swapchain, self.swapchain_image_views)
	delete(self.swapchain_image_views)
	delete(self.swapchain_images)
}

engine_init_swapchain :: proc(self: ^Engine) -> (ok: bool) {
	engine_create_swapchain(self, self.window_extent.width, self.window_extent.height) or_return

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
		vma.destroy_image(self.vma_allocator, self.draw_image.image, nil)
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
		vma.destroy_image(self.vma_allocator, self.depth_image.image, nil)
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
	// Create a command pool for commands submitted to the graphics queue. We also
	// want the pool to allow for resetting of individual command buffers.
	command_pool_info := command_pool_create_info(
		self.graphics_queue_family,
		{.RESET_COMMAND_BUFFER},
	)

	for &frame in self.frames {
		// Create peer frame deletion queue
		deletion_queue_init(&frame.deletion_queue, self.vk_device)

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

	deletion_queue_push(&self.main_deletion_queue, self.imm_command_pool)

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

	deletion_queue_push(&self.main_deletion_queue, self.imm_fence)

	return true
}

engine_init_descriptors :: proc(self: ^Engine) -> (ok: bool) {
	// Create a descriptor pool that will hold 10 sets with 1 image each
	sizes := []Pool_Size_Ratio {
		{.STORAGE_IMAGE, 1},
		{.UNIFORM_BUFFER, 1},
		{.COMBINED_IMAGE_SAMPLER, 1},
	}

	descriptor_allocator_init_pool(
		&self.global_descriptor_allocator,
		self.vk_device,
		10,
		sizes,
	) or_return
	deletion_queue_push(&self.main_deletion_queue, self.global_descriptor_allocator.pool)

	// Make the descriptor set layout for our compute draw
	{
		builder: Descriptor_Layout_Builder
		descriptor_layout_builder_init(&builder, self.vk_device)
		descriptor_layout_builder_add_binding(&builder, 0, .STORAGE_IMAGE)
		self.draw_image_descriptor_layout = descriptor_layout_builder_build(
			&builder,
			{.COMPUTE},
		) or_return
	}
	deletion_queue_push(&self.main_deletion_queue, self.draw_image_descriptor_layout)

	{
		builder: Descriptor_Layout_Builder
		descriptor_layout_builder_init(&builder, self.vk_device)
		descriptor_layout_builder_add_binding(&builder, 0, .UNIFORM_BUFFER)
		self.gpu_scene_data_descriptor_layout = descriptor_layout_builder_build(
			&builder,
			{.VERTEX, .FRAGMENT},
		) or_return
	}
	deletion_queue_push(&self.main_deletion_queue, self.gpu_scene_data_descriptor_layout)

	{
		builder: Descriptor_Layout_Builder
		descriptor_layout_builder_init(&builder, self.vk_device)
		descriptor_layout_builder_add_binding(&builder, 0, .COMBINED_IMAGE_SAMPLER)
		self.single_image_descriptor_layout = descriptor_layout_builder_build(
			&builder,
			{.FRAGMENT},
		) or_return
	}
	deletion_queue_push(&self.main_deletion_queue, self.single_image_descriptor_layout)

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
		sa.push_back(&frame_sizes, Pool_Size_Ratio{.STORAGE_IMAGE, 3})
		sa.push_back(&frame_sizes, Pool_Size_Ratio{.STORAGE_BUFFER, 3})
		sa.push_back(&frame_sizes, Pool_Size_Ratio{.UNIFORM_BUFFER, 3})
		sa.push_back(&frame_sizes, Pool_Size_Ratio{.COMBINED_IMAGE_SAMPLER, 4})

		descriptor_growable_init(
			&frame.frame_descriptors,
			self.vk_device,
			1000,
			sa.slice(&frame_sizes),
		)

		deletion_queue_push(&self.main_deletion_queue, frame.frame_descriptors)
	}

	return true
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

	deletion_queue_push(&self.main_deletion_queue, self.gradient_pipeline_layout)
	deletion_queue_push(&self.main_deletion_queue, gradient_color.pipeline)
	deletion_queue_push(&self.main_deletion_queue, sky.pipeline)

	return true
}

engine_init_mesh_pipeline :: proc(self: ^Engine) -> (ok: bool) {
	triangle_frag_shader := create_shader_module(
		self.vk_device,
		#load("./../../shaders/compiled/tex_image.frag.spv"),
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
	pipeline_layout_info.pSetLayouts = &self.single_image_descriptor_layout
	pipeline_layout_info.setLayoutCount = 1

	vk_check(
		vk.CreatePipelineLayout(
			self.vk_device,
			&pipeline_layout_info,
			nil,
			&self.mesh_pipeline_layout,
		),
	) or_return
	deletion_queue_push(&self.main_deletion_queue, self.mesh_pipeline_layout)

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
	pipeline_builder_disable_blending(&builder)
	// pipeline_builder_enable_blending_additive(&builder)
	// No depth testing
	// pipeline_builder_disable_depth_test(&builder)
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
	// Compute pipelines
	engine_init_background_pipeline(self) or_return

	// Graphics pipelines
	// engine_init_triangle_pipeline(self) or_return
	engine_init_mesh_pipeline(self) or_return

	metallic_roughness_build_pipelines(&self.metal_rough_material, self) or_return
	deletion_queue_push(&self.main_deletion_queue, self.metal_rough_material)

	return true
}

// odinfmt: disable
setup_imgui_style :: proc() {
    style := im.get_style()
    colors := &style.colors

    // Base colors for a pleasant and modern dark theme with dark accents
    colors[im.Col.Text]                  = {0.92, 0.93, 0.94, 1.00}  // Light grey text for readability
    colors[im.Col.Text_Disabled]         = {0.50, 0.52, 0.54, 1.00}  // Subtle grey for disabled text
    colors[im.Col.Window_Bg]             = {0.14, 0.14, 0.16, 1.00}  // Dark background with a hint of blue
    colors[im.Col.Child_Bg]              = {0.16, 0.16, 0.18, 1.00}  // Slightly lighter for child elements
    colors[im.Col.Popup_Bg]              = {0.18, 0.18, 0.20, 1.00}  // Popup background
    colors[im.Col.Border]                = {0.28, 0.29, 0.30, 0.60}  // Soft border color
    colors[im.Col.Border_Shadow]         = {0.00, 0.00, 0.00, 0.00}  // No border shadow
    colors[im.Col.Frame_Bg]              = {0.20, 0.22, 0.24, 1.00}  // Frame background
    colors[im.Col.Frame_Bg_Hovered]      = {0.22, 0.24, 0.26, 1.00}  // Frame hover effect
    colors[im.Col.Frame_Bg_Active]       = {0.24, 0.26, 0.28, 1.00}  // Active frame background
    colors[im.Col.Title_Bg]              = {0.14, 0.14, 0.16, 1.00}  // Title background
    colors[im.Col.Title_Bg_Active]       = {0.16, 0.16, 0.18, 1.00}  // Active title background
    colors[im.Col.Title_Bg_Collapsed]    = {0.14, 0.14, 0.16, 1.00}  // Collapsed title background
    colors[im.Col.Menu_Bar_Bg]           = {0.20, 0.20, 0.22, 1.00}  // Menu bar background
    colors[im.Col.Scrollbar_Bg]          = {0.16, 0.16, 0.18, 1.00}  // Scrollbar background
    colors[im.Col.Scrollbar_Grab]        = {0.24, 0.26, 0.28, 1.00}  // Dark accent for scrollbar grab
    colors[im.Col.Scrollbar_Grab_Hovered]= {0.28, 0.30, 0.32, 1.00}  // Scrollbar grab hover
    colors[im.Col.Scrollbar_Grab_Active] = {0.32, 0.34, 0.36, 1.00}  // Scrollbar grab active
    colors[im.Col.Check_Mark]            = {0.46, 0.56, 0.66, 1.00}  // Dark blue checkmark
    colors[im.Col.Slider_Grab]           = {0.36, 0.46, 0.56, 1.00}  // Dark blue slider grab
    colors[im.Col.Slider_Grab_Active]    = {0.40, 0.50, 0.60, 1.00}  // Active slider grab
    colors[im.Col.Button]                = {0.24, 0.34, 0.44, 1.00}  // Dark blue button
    colors[im.Col.Button_Hovered]        = {0.28, 0.38, 0.48, 1.00}  // Button hover effect
    colors[im.Col.Button_Active]         = {0.32, 0.42, 0.52, 1.00}  // Active button
    colors[im.Col.Header]                = {0.24, 0.34, 0.44, 1.00}  // Header color similar to button
    colors[im.Col.Header_Hovered]        = {0.28, 0.38, 0.48, 1.00}  // Header hover effect
    colors[im.Col.Header_Active]         = {0.32, 0.42, 0.52, 1.00}  // Active header
    colors[im.Col.Separator]             = {0.28, 0.29, 0.30, 1.00}  // Separator color
    colors[im.Col.Separator_Hovered]     = {0.46, 0.56, 0.66, 1.00}  // Hover effect for separator
    colors[im.Col.Separator_Active]      = {0.46, 0.56, 0.66, 1.00}  // Active separator
    colors[im.Col.Resize_Grip]           = {0.36, 0.46, 0.56, 1.00}  // Resize grip
    colors[im.Col.Resize_Grip_Hovered]   = {0.40, 0.50, 0.60, 1.00}  // Hover effect for resize grip
    colors[im.Col.Resize_Grip_Active]    = {0.44, 0.54, 0.64, 1.00}  // Active resize grip
    colors[im.Col.Tab]                   = {0.20, 0.22, 0.24, 1.00}  // Inactive tab
    colors[im.Col.Tab_Hovered]           = {0.28, 0.38, 0.48, 1.00}  // Hover effect for tab
    colors[im.Col.Tab_Selected]          = {0.24, 0.34, 0.44, 1.00}  // Active tab color (TabActive)
    colors[im.Col.Tab_Dimmed]            = {0.20, 0.22, 0.24, 1.00}  // Unfocused tab (TabUnfocused)
    colors[im.Col.Tab_Dimmed_Selected]   = {0.24, 0.34, 0.44, 1.00}  // Active but unfocused tab (TabUnfocusedActive)
    colors[im.Col.Docking_Preview]       = {0.24, 0.34, 0.44, 0.70}  // Docking preview
    colors[im.Col.Docking_Empty_Bg]      = {0.14, 0.14, 0.16, 1.00}  // Empty docking background
    colors[im.Col.Plot_Lines]            = {0.46, 0.56, 0.66, 1.00}  // Plot lines
    colors[im.Col.Plot_Lines_Hovered]    = {0.46, 0.56, 0.66, 1.00}  // Hover effect for plot lines
    colors[im.Col.Plot_Histogram]        = {0.36, 0.46, 0.56, 1.00}  // Histogram color
    colors[im.Col.Plot_Histogram_Hovered]= {0.40, 0.50, 0.60, 1.00}  // Hover effect for histogram
    colors[im.Col.Table_Header_Bg]       = {0.20, 0.22, 0.24, 1.00}  // Table header background
    colors[im.Col.Table_Border_Strong]   = {0.28, 0.29, 0.30, 1.00}  // Strong border for tables
    colors[im.Col.Table_Border_Light]    = {0.24, 0.25, 0.26, 1.00}  // Light border for tables
    colors[im.Col.Table_Row_Bg]          = {0.20, 0.22, 0.24, 1.00}  // Table row background
    colors[im.Col.Table_Row_Bg_Alt]      = {0.22, 0.24, 0.26, 1.00}  // Alternate row background
    colors[im.Col.Text_Selected_Bg]      = {0.24, 0.34, 0.44, 0.35}  // Selected text background
    colors[im.Col.Drag_Drop_Target]      = {0.46, 0.56, 0.66, 0.90}  // Drag and drop target
    colors[im.Col.Nav_Cursor]            = {0.46, 0.56, 0.66, 1.00}  // Navigation highlight (NavHighlight)
    colors[im.Col.Nav_Windowing_Highlight]= {1.00, 1.00, 1.00, 0.70}  // Windowing highlight
    colors[im.Col.Nav_Windowing_Dim_Bg]  = {0.80, 0.80, 0.80, 0.20}  // Dim background for windowing
    colors[im.Col.Modal_Window_Dim_Bg]   = {0.80, 0.80, 0.80, 0.35}  // Dim background for modal windows

    // Style adjustments
    style.window_rounding    = 8.0  // Softer rounded corners for windows
    style.frame_rounding     = 4.0  // Rounded corners for frames
    style.scrollbar_rounding = 6.0  // Rounded corners for scrollbars
    style.grab_rounding      = 4.0  // Rounded corners for grab elements
    style.child_rounding     = 4.0  // Rounded corners for child windows

    style.window_title_align = {0.50, 0.50}  // Centered window title
    style.window_padding     = {10.0, 10.0}  // Comfortable padding
    style.frame_padding      = {6.0, 4.0}    // Frame padding
    style.item_spacing       = {8.0, 8.0}    // Item spacing
    style.item_inner_spacing = {8.0, 6.0}    // Inner item spacing
    style.indent_spacing     = 22.0          // Indentation spacing

    style.scrollbar_size = 16.0  // Scrollbar size
    style.grab_min_size  = 10.0  // Minimum grab size

    style.anti_aliased_lines = true  // Enable anti-aliased lines
    style.anti_aliased_fill  = true  // Enable anti-aliased fill
}
// odinfmt: enable

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
		api_version = self.vkb.instance.api_version,
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
		self.vkb.instance.api_version,
		proc "c" (function_name: cstring, user_data: rawptr) -> vk.ProcVoidFunction {
			engine := cast(^Engine)user_data
			return vk.GetInstanceProcAddr(engine.vk_instance, function_name)
		},
		self,
	) or_return

	im_vk.init(&init_info) or_return
	defer if !ok {im_vk.shutdown()}

	deletion_queue_push(&self.main_deletion_queue, imgui_pool)
	deletion_queue_push(&self.main_deletion_queue, im_vk.shutdown)
	deletion_queue_push(&self.main_deletion_queue, im_glfw.shutdown)

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
	self.white_image = create_image_from_data(
		self,
		&white,
		{1, 1, 1},
		.R8G8B8A8_UNORM,
		{.SAMPLED},
	) or_return
	deletion_queue_push(&self.main_deletion_queue, self.white_image)

	grey := pack_unorm_4x8({0.66, 0.66, 0.66, 1})
	self.grey_image = create_image_from_data(
		self,
		&grey,
		{1, 1, 1},
		.R8G8B8A8_UNORM,
		{.SAMPLED},
	) or_return
	deletion_queue_push(&self.main_deletion_queue, self.grey_image)

	black := pack_unorm_4x8({0, 0, 0, 0})
	self.black_image = create_image_from_data(
		self,
		&black,
		{1, 1, 1},
		.R8G8B8A8_UNORM,
		{.SAMPLED},
	) or_return
	deletion_queue_push(&self.main_deletion_queue, self.black_image)

	// Checkerboard image
	magenta := pack_unorm_4x8({1, 0, 1, 1})
	pixels: [16 * 16]u32
	for x in 0 ..< 16 {
		for y in 0 ..< 16 {
			pixels[y * 16 + x] = ((x % 2) ~ (y % 2)) != 0 ? magenta : black
		}
	}
	self.error_checkerboard_image = create_image_from_data(
		self,
		raw_data(pixels[:]),
		{16, 16, 1},
		.R8G8B8A8_UNORM,
		{.SAMPLED},
	) or_return
	deletion_queue_push(&self.main_deletion_queue, self.error_checkerboard_image)

	sampler_info := vk.SamplerCreateInfo {
		sType     = .SAMPLER_CREATE_INFO,
		magFilter = .NEAREST,
		minFilter = .NEAREST,
	}

	vk_check(
		vk.CreateSampler(self.vk_device, &sampler_info, nil, &self.default_sampler_nearest),
	) or_return
	deletion_queue_push(&self.main_deletion_queue, self.default_sampler_nearest)

	sampler_info.magFilter = .LINEAR
	sampler_info.minFilter = .LINEAR

	vk_check(
		vk.CreateSampler(self.vk_device, &sampler_info, nil, &self.default_sampler_linear),
	) or_return
	deletion_queue_push(&self.main_deletion_queue, self.default_sampler_linear)

	// DDefault the material textures
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
		.Cpu_To_Gpu,
	) or_return
	deletion_queue_push(&self.main_deletion_queue, material_constants)

	// Write the buffer
	scene_uniform_data := cast(^Metallic_Roughness_Constants)material_constants.info.mapped_data
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
	default_material_idx := append_and_get_idx(&self.scene.materials, self.default_material_data)

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
