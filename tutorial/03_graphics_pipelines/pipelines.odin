package vk_guide

// Core
import "base:runtime"
import sa "core:container/small_array"
import "core:log"
import "core:os"

// Vendor
import vk "vendor:vulkan"

load_shader_module :: proc(
	device: vk.Device,
	file_path: string,
) -> (
	shader: vk.ShaderModule,
	ok: bool,
) #optional_ok {
	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
	if code, code_ok := os.read_entire_file(file_path, context.temp_allocator); code_ok {
		return create_shader_module(device, code)
	}
	log.errorf("Failed to load shader file: [%s]", file_path)
	return
}

// Create a new shader module, using the given code.
create_shader_module :: proc(
	device: vk.Device,
	code: []byte,
	loc := #caller_location,
) -> (
	shader: vk.ShaderModule,
	ok: bool,
) #optional_ok {
	assert(device != nil, "Invalid 'Device'", loc)

	create_info := vk.ShaderModuleCreateInfo {
		sType    = .SHADER_MODULE_CREATE_INFO,
		codeSize = len(code),
		pCode    = cast(^u32)raw_data(code),
	}

	vk_check(
		vk.CreateShaderModule(device, &create_info, nil, &shader),
		"failed to create shader module",
	) or_return

	return shader, true
}

MAX_SHADER_STAGES :: #config(MAX_SHADER_STAGES, 4)

Shader_Stages :: sa.Small_Array(MAX_SHADER_STAGES, vk.PipelineShaderStageCreateInfo)

Pipeline_Builder :: struct {
	shader_stages:                 Shader_Stages,
	input_assembly:                vk.PipelineInputAssemblyStateCreateInfo,
	rasterizer:                    vk.PipelineRasterizationStateCreateInfo,
	color_blend_attachment:        vk.PipelineColorBlendAttachmentState,
	multisampling:                 vk.PipelineMultisampleStateCreateInfo,
	pipeline_layout:               vk.PipelineLayout,
	depth_stencil:                 vk.PipelineDepthStencilStateCreateInfo,
	render_info:                   vk.PipelineRenderingCreateInfo,
	color_attachment_format:       vk.Format,
	vertex_binding_descriptions:   [dynamic]vk.VertexInputBindingDescription,
	vertex_attribute_descriptions: [dynamic]vk.VertexInputAttributeDescription,
	tessellation_state:            vk.PipelineTessellationStateCreateInfo,
	base_pipeline:                 vk.Pipeline,
	base_pipeline_index:           i32,
	flags:                         vk.PipelineCreateFlags,
	allocator:                     runtime.Allocator,
	initialized:                   bool,
}

pipeline_builder_init :: proc(self: ^Pipeline_Builder, allocator := context.allocator) {
	assert(self != nil)
	self.vertex_binding_descriptions = make([dynamic]vk.VertexInputBindingDescription, allocator)
	self.vertex_attribute_descriptions = make(
		[dynamic]vk.VertexInputAttributeDescription,
		allocator,
	)
	self.allocator = allocator
	pipeline_builder_clear(self)
	self.initialized = true
}

pipeline_builder_destroy :: proc(self: ^Pipeline_Builder) {
	assert(self != nil)
	context.allocator = self.allocator
	delete(self.vertex_binding_descriptions)
	delete(self.vertex_attribute_descriptions)
}

// Clear all of the structs we need back to `0` with their correct `sType`.
pipeline_builder_clear :: proc(self: ^Pipeline_Builder) {
	assert(self != nil)

	self.input_assembly = {
		sType                  = .PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
		topology               = .TRIANGLE_LIST,
		primitiveRestartEnable = false,
	}

	self.rasterizer = {
		sType                   = .PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
		depthClampEnable        = false,
		rasterizerDiscardEnable = false,
		polygonMode             = .FILL,
		cullMode                = {.BACK},
		frontFace               = .CLOCKWISE,
		depthBiasEnable         = false,
		lineWidth               = 1.0,
	}

	self.color_blend_attachment = {
		blendEnable    = false,
		colorWriteMask = {.R, .G, .B, .A},
	}

	self.multisampling = {
		sType                = .PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
		rasterizationSamples = {._1},
		sampleShadingEnable  = false,
		minSampleShading     = 1.0,
	}

	self.depth_stencil = {
		sType                 = .PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO,
		depthTestEnable       = true,
		depthWriteEnable      = true,
		depthCompareOp        = .LESS,
		depthBoundsTestEnable = false,
		stencilTestEnable     = false,
	}

	self.render_info = {
		sType                   = .PIPELINE_RENDERING_CREATE_INFO,
		colorAttachmentCount    = 1,
		pColorAttachmentFormats = &self.color_attachment_format,
	}

	self.tessellation_state = {
		sType = .PIPELINE_TESSELLATION_STATE_CREATE_INFO,
	}

	sa.clear(&self.shader_stages)
	clear(&self.vertex_binding_descriptions)
	clear(&self.vertex_attribute_descriptions)
	self.pipeline_layout = {}
	self.base_pipeline = {}
	self.base_pipeline_index = -1
	self.flags = {}
}

pipeline_builder_build_pipeline :: proc(
	self: ^Pipeline_Builder,
	device: vk.Device,
) -> (
	pipeline: vk.Pipeline,
	ok: bool,
) #optional_ok {
	ensure(self.initialized, "Pipeline builder not initialized")

	// Make viewport state from our stored viewport and scissor.
	// At the moment we wont support multiple viewports or scissors
	viewport_state := vk.PipelineViewportStateCreateInfo {
		sType         = .PIPELINE_VIEWPORT_STATE_CREATE_INFO,
		viewportCount = 1,
		scissorCount  = 1,
	}

	// Setup dummy color blending. We arent using transparent objects yet,
	// the blending is just "no blend", but we do write to the color attachment
	color_blending := vk.PipelineColorBlendStateCreateInfo {
		sType           = .PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
		logicOpEnable   = false,
		logicOp         = .COPY,
		attachmentCount = 1,
		pAttachments    = &self.color_blend_attachment,
	}

	// Completely clear `VertexInputStateCreateInfo`, as we have no need for it
	vertex_input_info := vk.PipelineVertexInputStateCreateInfo {
		sType                           = .PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
		vertexBindingDescriptionCount   = u32(len(self.vertex_binding_descriptions)),
		pVertexBindingDescriptions      = raw_data(self.vertex_binding_descriptions[:]),
		vertexAttributeDescriptionCount = u32(len(self.vertex_attribute_descriptions)),
		pVertexAttributeDescriptions    = raw_data(self.vertex_attribute_descriptions[:]),
	}

	dynamic_states := [?]vk.DynamicState{.VIEWPORT, .SCISSOR}
	dynamic_info := vk.PipelineDynamicStateCreateInfo {
		sType             = .PIPELINE_DYNAMIC_STATE_CREATE_INFO,
		pDynamicStates    = raw_data(dynamic_states[:]),
		dynamicStateCount = u32(len(dynamic_states)),
	}

	// Build the actual pipeline.
	// We now use all of the info structs we have been writing into into this one
	// to create the pipeline.
	pipeline_info := vk.GraphicsPipelineCreateInfo {
		sType               = .GRAPHICS_PIPELINE_CREATE_INFO,
		// connect the renderInfo to the pNext extension mechanism
		pNext               = &self.render_info,
		flags               = self.flags,
		stageCount          = u32(sa.len(self.shader_stages)),
		pStages             = raw_data(sa.slice(&self.shader_stages)),
		pVertexInputState   = &vertex_input_info,
		pInputAssemblyState = &self.input_assembly,
		pTessellationState  = &self.tessellation_state,
		pViewportState      = &viewport_state,
		pRasterizationState = &self.rasterizer,
		pMultisampleState   = &self.multisampling,
		pDepthStencilState  = &self.depth_stencil,
		pColorBlendState    = &color_blending,
		pDynamicState       = &dynamic_info,
		layout              = self.pipeline_layout,
		basePipelineHandle  = self.base_pipeline,
		basePipelineIndex   = self.base_pipeline_index,
	}

	vk_check(
		vk.CreateGraphicsPipelines(device, 0, 1, &pipeline_info, nil, &pipeline),
		"Failed to create pipeline",
	) or_return

	return pipeline, true
}

pipeline_builder_add_shader :: proc(
	self: ^Pipeline_Builder,
	shader: vk.ShaderModule,
	stage: vk.ShaderStageFlags,
	entry_point: cstring = "main",
) {
	create_info := pipeline_shader_stage_create_info(stage, shader, entry_point)
	sa.push(&self.shader_stages, create_info)
}

pipeline_builder_set_input_topology :: proc(
	self: ^Pipeline_Builder,
	topology: vk.PrimitiveTopology,
	primitive_restart_enable: bool = false,
) {
	self.input_assembly.topology = topology
	self.input_assembly.primitiveRestartEnable = b32(primitive_restart_enable)
}

pipeline_builder_set_polygon_mode :: proc(
	self: ^Pipeline_Builder,
	polygon_mode: vk.PolygonMode,
	line_width: f32 = 1.0,
) {
	self.rasterizer.polygonMode = polygon_mode
	self.rasterizer.lineWidth = line_width
}

pipeline_builder_set_cull_mode :: proc(
	self: ^Pipeline_Builder,
	cull_mode: vk.CullModeFlags,
	front_face: vk.FrontFace,
) {
	self.rasterizer.cullMode = cull_mode
	self.rasterizer.frontFace = front_face
}

pipeline_builder_set_multisampling :: proc(
	self: ^Pipeline_Builder,
	rasterization_samples: vk.SampleCountFlags,
	min_sample_shading: f32 = 1.0,
	sample_mask: ^vk.SampleMask = nil,
	alpha_to_coverage_enable: bool = false,
	alpha_to_one_enable: bool = false,
) {
	self.multisampling.rasterizationSamples = rasterization_samples
	self.multisampling.sampleShadingEnable = min_sample_shading < 1.0
	self.multisampling.minSampleShading = min_sample_shading
	self.multisampling.pSampleMask = sample_mask
	self.multisampling.alphaToCoverageEnable = b32(alpha_to_coverage_enable)
	self.multisampling.alphaToOneEnable = b32(alpha_to_one_enable)
}

pipeline_builder_set_multisampling_none :: proc(self: ^Pipeline_Builder) {
	pipeline_builder_set_multisampling(self, {._1})
}

pipeline_builder_set_blend_state :: proc(
	self: ^Pipeline_Builder,
	blend_enable: bool,
	src_color_blend: vk.BlendFactor,
	dst_color_blend: vk.BlendFactor,
	color_blend_op: vk.BlendOp,
	src_alpha_blend: vk.BlendFactor,
	dst_alpha_blend: vk.BlendFactor,
	alpha_blend_op: vk.BlendOp,
	color_write_mask: vk.ColorComponentFlags,
) {
	self.color_blend_attachment = {
		blendEnable         = b32(blend_enable),
		srcColorBlendFactor = src_color_blend,
		dstColorBlendFactor = dst_color_blend,
		colorBlendOp        = color_blend_op,
		srcAlphaBlendFactor = src_alpha_blend,
		dstAlphaBlendFactor = dst_alpha_blend,
		alphaBlendOp        = alpha_blend_op,
		colorWriteMask      = color_write_mask,
	}
}

pipeline_builder_disable_blending :: proc(self: ^Pipeline_Builder) {
	// Default write mask
	self.color_blend_attachment.colorWriteMask = {.R, .G, .B, .A}
	// No blending
	self.color_blend_attachment.blendEnable = false
}

pipeline_builder_set_color_attachment_format :: proc(self: ^Pipeline_Builder, format: vk.Format) {
	self.color_attachment_format = format
	// Connect the format to the `render_info`  structure
	self.render_info.colorAttachmentCount = 1
	self.render_info.pColorAttachmentFormats = &self.color_attachment_format
}

pipeline_builder_set_depth_attachment_format :: proc(self: ^Pipeline_Builder, format: vk.Format) {
	self.render_info.depthAttachmentFormat = format
}

pipeline_builder_set_stencil_attachment_format :: proc(
	self: ^Pipeline_Builder,
	format: vk.Format,
) {
	self.render_info.stencilAttachmentFormat = format
}

pipeline_builder_set_depth_bias :: proc(
	self: ^Pipeline_Builder,
	constant_factor: f32,
	clamp: f32,
	slope_factor: f32,
) {
	self.rasterizer.depthBiasEnable = true
	self.rasterizer.depthBiasConstantFactor = constant_factor
	self.rasterizer.depthBiasClamp = clamp
	self.rasterizer.depthBiasSlopeFactor = slope_factor
}

pipeline_builder_set_depth_state :: proc(
	self: ^Pipeline_Builder,
	depth_test: bool,
	depth_write: bool,
	compare_op: vk.CompareOp,
) {
	self.depth_stencil.depthTestEnable = b32(depth_test)
	self.depth_stencil.depthWriteEnable = b32(depth_write)
	self.depth_stencil.depthCompareOp = compare_op
}

pipeline_builder_set_depth_bounds :: proc(
	self: ^Pipeline_Builder,
	min_depth_bounds: f32,
	max_depth_bounds: f32,
) {
	self.depth_stencil.depthBoundsTestEnable = true
	self.depth_stencil.minDepthBounds = min_depth_bounds
	self.depth_stencil.maxDepthBounds = max_depth_bounds
}

pipeline_builder_disable_depth_test :: proc(self: ^Pipeline_Builder) {
	self.depth_stencil.depthTestEnable = false
	self.depth_stencil.depthWriteEnable = false
	self.depth_stencil.depthCompareOp = .NEVER
	self.depth_stencil.depthBoundsTestEnable = false
	self.depth_stencil.stencilTestEnable = false
	self.depth_stencil.front = {}
	self.depth_stencil.back = {}
	self.depth_stencil.minDepthBounds = 0.0
	self.depth_stencil.maxDepthBounds = 1.0
}

pipeline_builder_set_vertex_input :: proc(
	self: ^Pipeline_Builder,
	binding: u32,
	stride: u32,
	input_rate: vk.VertexInputRate,
	attributes: []vk.VertexInputAttributeDescription,
) {
	binding_desc := vk.VertexInputBindingDescription {
		binding   = binding,
		stride    = stride,
		inputRate = input_rate,
	}
	append(&self.vertex_binding_descriptions, binding_desc)
	append(&self.vertex_attribute_descriptions, ..attributes)
}

pipeline_builder_set_tessellation :: proc(self: ^Pipeline_Builder, patch_control_points: u32) {
	self.tessellation_state.patchControlPoints = patch_control_points
}

pipeline_builder_set_rasterizer_discard :: proc(self: ^Pipeline_Builder, discard_enable: bool) {
	self.rasterizer.rasterizerDiscardEnable = b32(discard_enable)
}

pipeline_builder_set_depth_clamp :: proc(self: ^Pipeline_Builder, clamp_enable: bool) {
	self.rasterizer.depthClampEnable = b32(clamp_enable)
}

pipeline_builder_set_base_pipeline :: proc(
	self: ^Pipeline_Builder,
	base_pipeline: vk.Pipeline,
	base_pipeline_index: i32 = -1,
) {
	self.base_pipeline = base_pipeline
	self.base_pipeline_index = base_pipeline_index
	self.flags += {.DERIVATIVE}
}
