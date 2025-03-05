package vk_guide

// Core
import "base:runtime"

// Vendor
import vk "vendor:vulkan"

Descriptor_Layout_Builder :: struct {
	bindings:  [dynamic]vk.DescriptorSetLayoutBinding,
	allocator: runtime.Allocator,
}

descriptor_layout_builder_init :: proc(
	self: ^Descriptor_Layout_Builder,
	allocator := context.allocator,
) {
	self.bindings.allocator = allocator
	self.allocator = allocator
}

descriptor_layout_builder_destroy :: proc(self: ^Descriptor_Layout_Builder) {
	context.allocator = self.allocator
	delete(self.bindings)
}

descriptor_layout_builder_add_binding :: proc(
	self: ^Descriptor_Layout_Builder,
	binding: u32,
	type: vk.DescriptorType,
) {
	assert(self.allocator.data != nil, "Descriptor Layout Builder not initialized!")

	new_binding := vk.DescriptorSetLayoutBinding {
		binding         = binding,
		descriptorCount = 1,
		descriptorType  = type,
	}

	append(&self.bindings, new_binding)
}

descriptor_layout_builder_clear :: proc(self: ^Descriptor_Layout_Builder) {
	clear(&self.bindings)
}

descriptor_layout_builder_build :: proc(
	self: ^Descriptor_Layout_Builder,
	device: vk.Device,
	shader_stages: vk.ShaderStageFlags,
	pNext: rawptr = nil,
	flags: vk.DescriptorSetLayoutCreateFlags = {},
) -> (
	set: vk.DescriptorSetLayout,
	ok: bool,
) #optional_ok {
	for &b in self.bindings {
		b.stageFlags += shader_stages
	}

	info := vk.DescriptorSetLayoutCreateInfo {
		sType        = .DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
		pNext        = pNext,
		bindingCount = u32(len(self.bindings)),
		pBindings    = raw_data(self.bindings),
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
