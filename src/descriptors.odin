package main

// Vendor
import vk "vendor:vulkan"

// Libs
import "libs:vkb"

Descriptor_Layout_Builder :: struct {
	bindings: [dynamic]vk.DescriptorSetLayoutBinding,
}

descriptor_layout_add_binding :: proc(
	builder: ^Descriptor_Layout_Builder,
	binding: u32,
	type: vk.DescriptorType,
) {
	new_bind := vk.DescriptorSetLayoutBinding {
		binding         = binding,
		descriptorCount = 1,
		descriptorType  = type,
	}

	append(&builder.bindings, new_bind)
}

descriptor_layout_add_clear :: proc(builder: ^Descriptor_Layout_Builder) {
	clear(&builder.bindings)
}

@(require_results)
descriptor_layout_build :: proc(
	builder: ^Descriptor_Layout_Builder,
	device: ^vkb.Device,
	shader_stages: vk.ShaderStageFlags,
) -> (
	set: vk.DescriptorSetLayout,
	err: Error,
) {
	defer delete(builder.bindings)

	for &b in builder.bindings {
		b.stageFlags += shader_stages
	}

	info := vk.DescriptorSetLayoutCreateInfo {
		sType = .DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
		bindingCount = u32(len(builder.bindings)),
		pBindings = raw_data(builder.bindings),
		flags = {},
	}

	vk.CreateDescriptorSetLayout(device.ptr, &info, nil, &set) or_return

	return
}

Pool_Size_Ratio :: struct {
	type:  vk.DescriptorType,
	ratio: f32,
}

Descriptor_Allocator :: struct {
	pool: vk.DescriptorPool,
}

descriptor_allocator_init_pool :: proc(
	descriptor: ^Descriptor_Allocator,
	device: ^vkb.Device,
	max_sets: u32,
	ratios: []Pool_Size_Ratio,
) -> (
	err: Error,
) {
	pool_sizes := make([]vk.DescriptorPoolSize, len(ratios)) or_return
	defer delete(pool_sizes)

	for r, i in ratios {
		pool_sizes[i] = vk.DescriptorPoolSize {
			type            = r.type,
			descriptorCount = u32(r.ratio) * max_sets,
		}
	}

	pool_info := vk.DescriptorPoolCreateInfo {
		sType = .DESCRIPTOR_POOL_CREATE_INFO,
		flags = {},
		maxSets = max_sets,
		poolSizeCount = u32(len(pool_sizes)),
		pPoolSizes = raw_data(pool_sizes),
	}

	vk.CreateDescriptorPool(device.ptr, &pool_info, nil, &descriptor.pool) or_return

	return
}

descriptor_allocator_clear_descriptor :: proc(
	descriptor: ^Descriptor_Allocator,
	device: ^vkb.Device,
) {
	vk.ResetDescriptorPool(device.ptr, descriptor.pool, {})
}

descriptor_allocator_destroy_pool :: proc(descriptor: ^Descriptor_Allocator, device: ^vkb.Device) {
	vk.DestroyDescriptorPool(device.ptr, descriptor.pool, nil)
}

@(require_results)
descriptor_allocator_allocate :: proc(
	descriptor: ^Descriptor_Allocator,
	device: ^vkb.Device,
	layout: ^vk.DescriptorSetLayout,
) -> (
	ds: vk.DescriptorSet,
	err: Error,
) {
	alloc_info := vk.DescriptorSetAllocateInfo {
		sType              = .DESCRIPTOR_SET_ALLOCATE_INFO,
		descriptorPool     = descriptor.pool,
		descriptorSetCount = 1,
		pSetLayouts        = layout,
	}

	vk.AllocateDescriptorSets(device.ptr, &alloc_info, &ds) or_return

	return
}
