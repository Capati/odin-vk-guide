package vk_guide

// Core
import la "core:math/linalg"

// Vendor
import vk "vendor:vulkan"

Material_Pass :: enum u8 {
	Main_Color,
	Transparent,
	Other,
}

Material_Pipeline :: struct {
	pipeline: vk.Pipeline,
	layout:   vk.PipelineLayout,
}


Material_Instance :: struct {
	pipeline:     ^Material_Pipeline,
	material_set: vk.DescriptorSet,
	pass_type:    Material_Pass,
}

Metallic_Roughness_Constants :: struct {
	color_factors:       la.Vector4f32,
	metal_rough_factors: la.Vector4f32,
	// Padding, we need it anyway for uniform buffers
	extra:               [14]la.Vector4f32,
}

Metallic_Roughness_Resources :: struct {
	color_image:         Allocated_Image,
	color_sampler:       vk.Sampler,
	metal_rough_image:   Allocated_Image,
	metal_rough_sampler: vk.Sampler,
	data_buffer:         vk.Buffer,
	data_buffer_offset:  u32,
}

Metallic_Roughness :: struct {
	device:               vk.Device,
	opaque_pipeline:      Material_Pipeline,
	transparent_pipeline: Material_Pipeline,
	material_layout:      vk.DescriptorSetLayout,
	constants:            Metallic_Roughness_Constants,
	resources:            Metallic_Roughness_Resources,
	writer:               Descriptor_Writer,
}

metallic_roughness_build_pipelines :: proc(
	self: ^Metallic_Roughness,
	engine: ^Engine,
) -> (
	ok: bool,
) {
	mesh_frag_shader := create_shader_module(
		engine.vk_device,
		#load("./../../shaders/compiled/mesh.frag.spv"),
	) or_return
	defer vk.DestroyShaderModule(engine.vk_device, mesh_frag_shader, nil)

	mesh_vert_shader := create_shader_module(
		engine.vk_device,
		#load("./../../shaders/compiled/mesh.vert.spv"),
	) or_return
	defer vk.DestroyShaderModule(engine.vk_device, mesh_vert_shader, nil)

	self.device = engine.vk_device

	layout_builder: Descriptor_Layout_Builder
	descriptor_layout_builder_init(&layout_builder, engine.vk_device)
	descriptor_layout_builder_add_binding(&layout_builder, 0, .UNIFORM_BUFFER)
	descriptor_layout_builder_add_binding(&layout_builder, 1, .COMBINED_IMAGE_SAMPLER)
	descriptor_layout_builder_add_binding(&layout_builder, 2, .COMBINED_IMAGE_SAMPLER)
	self.material_layout = descriptor_layout_builder_build(
		&layout_builder,
		{.VERTEX, .FRAGMENT},
	) or_return

	layouts := [2]vk.DescriptorSetLayout {
		engine.gpu_scene_data_descriptor_layout,
		self.material_layout,
	}

	matrix_range := vk.PushConstantRange {
		offset     = 0,
		size       = size_of(GPU_Draw_Push_Constants),
		stageFlags = {.VERTEX},
	}

	pipeline_layout_info := pipeline_layout_create_info()
	pipeline_layout_info.setLayoutCount = 2
	pipeline_layout_info.pSetLayouts = raw_data(layouts[:])
	pipeline_layout_info.pPushConstantRanges = &matrix_range
	pipeline_layout_info.pushConstantRangeCount = 1

	new_layout: vk.PipelineLayout
	vk_check(
		vk.CreatePipelineLayout(engine.vk_device, &pipeline_layout_info, nil, &new_layout),
	) or_return
	defer if !ok {
		vk.DestroyPipelineLayout(engine.vk_device, new_layout, nil)
	}

	self.opaque_pipeline.layout = new_layout
	self.transparent_pipeline.layout = new_layout

	// Build the stage-create-info for both vertex and fragment stages. This lets
	// the pipeline know the shader modules per stage
	pipeline_builder := pipeline_builder_create_default()
	pipeline_builder_set_shaders(&pipeline_builder, mesh_vert_shader, mesh_frag_shader)
	pipeline_builder_set_input_topology(&pipeline_builder, .TRIANGLE_LIST)
	pipeline_builder_set_polygon_mode(&pipeline_builder, .FILL)
	pipeline_builder_set_cull_mode(&pipeline_builder, vk.CullModeFlags_NONE, .CLOCKWISE)
	pipeline_builder_set_multisampling_none(&pipeline_builder)
	pipeline_builder_disable_blending(&pipeline_builder)
	pipeline_builder_enable_depth_test(&pipeline_builder, true, .GREATER_OR_EQUAL)

	// Render format
	pipeline_builder_set_color_attachment_format(&pipeline_builder, engine.draw_image.image_format)
	pipeline_builder_set_depth_attachment_format(
		&pipeline_builder,
		engine.depth_image.image_format,
	)

	// Use the mesh layout we created
	pipeline_builder.pipeline_layout = new_layout

	// Finally build the pipeline
	self.opaque_pipeline.pipeline = pipeline_builder_build(
		&pipeline_builder,
		engine.vk_device,
	) or_return
	defer if !ok {
		vk.DestroyPipeline(engine.vk_device, self.opaque_pipeline.pipeline, nil)
	}

	// Create the transparent variant
	pipeline_builder_enable_blending_additive(&pipeline_builder)
	pipeline_builder_enable_depth_test(&pipeline_builder, false, .GREATER_OR_EQUAL)

	self.transparent_pipeline.pipeline = pipeline_builder_build(
		&pipeline_builder,
		engine.vk_device,
	) or_return
	defer if !ok {
		vk.DestroyPipeline(engine.vk_device, self.transparent_pipeline.pipeline, nil)
	}

	return true
}

metallic_roughness_clear_resources :: proc(self: Metallic_Roughness) {
	vk.DestroyDescriptorSetLayout(self.device, self.material_layout, nil)
	vk.DestroyPipelineLayout(self.device, self.transparent_pipeline.layout, nil)

	vk.DestroyPipeline(self.device, self.transparent_pipeline.pipeline, nil)
	vk.DestroyPipeline(self.device, self.opaque_pipeline.pipeline, nil)
}

metallic_roughness_write :: proc(
	self: ^Metallic_Roughness,
	device: vk.Device,
	pass: Material_Pass,
	resources: ^Metallic_Roughness_Resources,
	descriptor_allocator: ^Descriptor_Allocator,
) -> (
	material: Material_Instance,
	ok: bool,
) {
	material.pass_type = pass

	if pass == .Transparent {
		material.pipeline = &self.transparent_pipeline
	} else {
		material.pipeline = &self.opaque_pipeline
	}

	material.material_set = descriptor_allocator_allocate(
		descriptor_allocator,
		device,
		&self.material_layout,
	) or_return

	descriptor_writer_init(&self.writer, device)
	descriptor_writer_clear(&self.writer)
	descriptor_writer_write_buffer(
		&self.writer,
		0,
		resources.data_buffer,
		size_of(Metallic_Roughness_Resources),
		vk.DeviceSize(resources.data_buffer_offset),
		.UNIFORM_BUFFER,
	) or_return
	descriptor_writer_write_image(
		&self.writer,
		1,
		resources.color_image.image_view,
		resources.color_sampler,
		.SHADER_READ_ONLY_OPTIMAL,
		.COMBINED_IMAGE_SAMPLER,
	) or_return
	descriptor_writer_write_image(
		&self.writer,
		2,
		resources.metal_rough_image.image_view,
		resources.metal_rough_sampler,
		.SHADER_READ_ONLY_OPTIMAL,
		.COMBINED_IMAGE_SAMPLER,
	) or_return

	descriptor_writer_update_set(&self.writer, material.material_set)

	return material, true
}
