package vk_guide

// Core
import "base:runtime"
import sa "core:container/small_array"

// Vendor
import vk "vendor:vulkan"

MAX_BOUND_DESCRIPTOR_SETS :: 8

Descriptor_Sets :: sa.Small_Array(MAX_BOUND_DESCRIPTOR_SETS, vk.DescriptorSetLayoutBinding)

Descriptor_Layout_Builder :: struct {
	bindings: Descriptor_Sets,
}

descriptor_layout_builder_add_binding :: proc(
	self: ^Descriptor_Layout_Builder,
	binding: u32,
	type: vk.DescriptorType,
	loc := #caller_location,
) {
	// Assert that we haven't exceeded the maximum number of descriptor sets
	assert(sa.len(self.bindings) < MAX_BOUND_DESCRIPTOR_SETS, loc = loc)

	new_binding := vk.DescriptorSetLayoutBinding {
		binding         = binding,
		descriptorCount = 1,
		descriptorType  = type,
	}

	sa.push(&self.bindings, new_binding)
}

descriptor_layout_builder_clear :: proc(self: ^Descriptor_Layout_Builder) {
	sa.clear(&self.bindings)
}

descriptor_layout_builder_build :: proc(
	self: ^Descriptor_Layout_Builder,
	device: vk.Device,
	shader_stages: vk.ShaderStageFlags,
	pNext: rawptr = nil,
	flags: vk.DescriptorSetLayoutCreateFlags = {},
	loc := #caller_location,
) -> (
	set: vk.DescriptorSetLayout,
	ok: bool,
) #optional_ok {
	assert(device != nil, "Invalid Vulkan device handle.", loc = loc)
	assert(shader_stages != {}, "No shader stages specified for descriptor set layout.", loc = loc)
	assert(sa.len(self.bindings) > 0, "No bindings added to descriptor layout builder.", loc = loc)

	bindings := sa.slice(&self.bindings)

	for &b in bindings {
		b.stageFlags += shader_stages
	}

	info := vk.DescriptorSetLayoutCreateInfo {
		sType        = .DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
		pNext        = pNext,
		bindingCount = u32(len(bindings)),
		pBindings    = raw_data(bindings),
		flags        = flags,
	}

	vk_check(vk.CreateDescriptorSetLayout(device, &info, nil, &set)) or_return

	return set, true
}

Pool_Size_Ratio :: struct {
	type:  vk.DescriptorType,
	ratio: f32,
}

Descriptor_Allocator :: struct {
	pool: vk.DescriptorPool,
}

descriptor_allocator_init_pool :: proc(
	self: ^Descriptor_Allocator,
	device: vk.Device,
	max_sets: u32,
	pool_ratios: []Pool_Size_Ratio,
) -> (
	ok: bool,
) {
	ta := context.temp_allocator
	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()

	pool_sizes := make([dynamic]vk.DescriptorPoolSize, ta)
	reserve(&pool_sizes, len(pool_ratios))

	for &ratio in pool_ratios {
		append(
			&pool_sizes,
			vk.DescriptorPoolSize {
				type = ratio.type,
				descriptorCount = u32(ratio.ratio) * max_sets,
			},
		)
	}

	pool_info := vk.DescriptorPoolCreateInfo {
		sType         = .DESCRIPTOR_POOL_CREATE_INFO,
		maxSets       = max_sets,
		poolSizeCount = u32(len(pool_sizes)),
		pPoolSizes    = raw_data(pool_sizes[:]),
	}

	vk_check(vk.CreateDescriptorPool(device, &pool_info, nil, &self.pool)) or_return

	return true
}

descriptor_allocator_clear_descriptors :: proc(self: ^Descriptor_Allocator, device: vk.Device) {
	vk.ResetDescriptorPool(device, self.pool, {})
}

descriptor_allocator_destroy_pool :: proc(self: ^Descriptor_Allocator, device: vk.Device) {
	vk.DestroyDescriptorPool(device, self.pool, nil)
}

descriptor_allocator_allocate :: proc(
	self: ^Descriptor_Allocator,
	device: vk.Device,
	layout: ^vk.DescriptorSetLayout,
) -> (
	ds: vk.DescriptorSet,
	ok: bool,
) #optional_ok {
	allocInfo := vk.DescriptorSetAllocateInfo {
		sType              = .DESCRIPTOR_SET_ALLOCATE_INFO,
		descriptorPool     = self.pool,
		descriptorSetCount = 1,
		pSetLayouts        = layout,
	}

	vk_check(vk.AllocateDescriptorSets(device, &allocInfo, &ds)) or_return

	return ds, true
}
