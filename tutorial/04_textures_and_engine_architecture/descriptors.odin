package vk_guide

// Core
import sa "core:container/small_array"

// Vendor
import vk "vendor:vulkan"

MAX_BOUND_DESCRIPTOR_SETS :: #config(MAX_BOUND_DESCRIPTOR_SETS, 16)

Descriptor_Bindings :: sa.Small_Array(MAX_BOUND_DESCRIPTOR_SETS, vk.DescriptorSetLayoutBinding)

Descriptor_Layout_Builder :: struct {
	device:   vk.Device,
	bindings: Descriptor_Bindings,
}

descriptor_layout_builder_init :: proc(self: ^Descriptor_Layout_Builder, device: vk.Device) {
	self.device = device
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

	sa.push_back(&self.bindings, new_binding)
}

descriptor_layout_builder_clear :: proc(self: ^Descriptor_Layout_Builder) {
	sa.clear(&self.bindings)
}

descriptor_layout_builder_build :: proc(
	self: ^Descriptor_Layout_Builder,
	shader_stages: vk.ShaderStageFlags,
	pNext: rawptr = nil,
	flags: vk.DescriptorSetLayoutCreateFlags = {},
	loc := #caller_location,
) -> (
	set: vk.DescriptorSetLayout,
	ok: bool,
) #optional_ok {
	assert(shader_stages != {}, "No shader stages specified for descriptor set layout.", loc = loc)
	assert(sa.len(self.bindings) > 0, "No bindings added to descriptor layout builder.", loc = loc)

	for &b in sa.slice(&self.bindings) {
		b.stageFlags += shader_stages
	}

	info := vk.DescriptorSetLayoutCreateInfo {
		sType        = .DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
		pNext        = pNext,
		bindingCount = u32(sa.len(self.bindings)),
		pBindings    = raw_data(sa.slice(&self.bindings)),
		flags        = flags,
	}

	vk_check(vk.CreateDescriptorSetLayout(self.device, &info, nil, &set)) or_return

	return set, true
}

Pool_Size_Ratio :: struct {
	type:  vk.DescriptorType,
	ratio: f32,
}

Descriptor_Allocator :: struct {
	device: vk.Device,
	pool:   vk.DescriptorPool,
}

MAX_POOL_SIZES :: #config(MAX_POOL_SIZES, 12)

Pool_Sizes :: sa.Small_Array(MAX_POOL_SIZES, vk.DescriptorPoolSize)

descriptor_allocator_init_pool :: proc(
	self: ^Descriptor_Allocator,
	device: vk.Device,
	max_sets: u32,
	pool_ratios: []Pool_Size_Ratio,
) -> (
	ok: bool,
) {
	self.device = device

	pool_sizes: Pool_Sizes

	for &ratio in pool_ratios {
		sa.push_back(
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
		poolSizeCount = u32(sa.len(pool_sizes)),
		pPoolSizes    = raw_data(sa.slice(&pool_sizes)),
	}

	vk_check(vk.CreateDescriptorPool(device, &pool_info, nil, &self.pool)) or_return

	return true
}

descriptor_allocator_clear_descriptors :: proc(self: ^Descriptor_Allocator) {
	vk.ResetDescriptorPool(self.device, self.pool, {})
}

descriptor_allocator_destroy_pool :: proc(self: ^Descriptor_Allocator) {
	vk.DestroyDescriptorPool(self.device, self.pool, nil)
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

// =============================================================================
// Descriptor Allocator Growable
// =============================================================================

MAX_POOLS :: #config(MAX_POOLS, 32)

Ratios :: sa.Small_Array(MAX_POOL_SIZES, Pool_Size_Ratio)
Full_Pools :: sa.Small_Array(MAX_POOLS, vk.DescriptorPool)
Ready_Pools :: sa.Small_Array(MAX_POOLS, vk.DescriptorPool)

Descriptor_Allocator_Growable :: struct {
	device:        vk.Device,
	ratios:        Ratios,
	full_pools:    Full_Pools,
	ready_pools:   Ready_Pools,
	sets_per_pool: u32,
}

descriptor_growable_init :: proc(
	self: ^Descriptor_Allocator_Growable,
	device: vk.Device,
	max_sets: u32,
	pool_ratios: []Pool_Size_Ratio,
) -> (
	ok: bool,
) {
	self.device = device

	sa.clear(&self.ratios)
	sa.clear(&self.full_pools)
	sa.clear(&self.ready_pools)

	for r in pool_ratios {
		sa.push_back(&self.ratios, r)
	}

	new_pool := descriptor_growable_create_pool(self, max_sets) or_return

	// Grow it next allocation
	self.sets_per_pool = u32(f32(max_sets) * 1.5)

	sa.push_back(&self.ready_pools, new_pool)

	return true
}

descriptor_growable_clear_pools :: proc(self: ^Descriptor_Allocator_Growable) -> (ok: bool) {
	// Reset ready pools
	for &pool in sa.slice(&self.ready_pools) {
		vk_check(vk.ResetDescriptorPool(self.device, pool, {})) or_return
	}

	// Reset full pools and move them to ready
	for &pool in sa.slice(&self.full_pools) {
		vk_check(vk.ResetDescriptorPool(self.device, pool, {})) or_return
		sa.push_back(&self.ready_pools, pool)
	}

	sa.clear(&self.full_pools)

	return true
}

descriptor_growable_destroy_pools :: proc(self: Descriptor_Allocator_Growable) {
	// Destroy ready pools
	for i in 0 ..< sa.len(self.ready_pools) {
		pool := sa.get(self.ready_pools, i)
		vk.DestroyDescriptorPool(self.device, pool, nil)
	}

	// Destroy full pools
	for i in 0 ..< sa.len(self.full_pools) {
		pool := sa.get(self.full_pools, i)
		vk.DestroyDescriptorPool(self.device, pool, nil)
	}
}

@(require_results)
descriptor_growable_allocate :: proc(
	self: ^Descriptor_Allocator_Growable,
	layout: ^vk.DescriptorSetLayout,
	pNext: rawptr = nil,
) -> (
	ds: vk.DescriptorSet,
	ok: bool,
) {
	// Get or create a pool to allocate from
	pool_to_use := descriptor_growable_get_pool(self) or_return

	alloc_info := vk.DescriptorSetAllocateInfo {
		pNext              = pNext,
		sType              = .DESCRIPTOR_SET_ALLOCATE_INFO,
		descriptorPool     = pool_to_use,
		descriptorSetCount = 1,
		pSetLayouts        = layout,
	}

	result := vk.AllocateDescriptorSets(self.device, &alloc_info, &ds)

	// Allocation failed. Try again
	if result == .ERROR_OUT_OF_POOL_MEMORY || result == .ERROR_FRAGMENTED_POOL {
		sa.push_back(&self.full_pools, pool_to_use)

		pool_to_use = descriptor_growable_get_pool(self) or_return
		alloc_info.descriptorPool = pool_to_use
		vk_check(vk.AllocateDescriptorSets(self.device, &alloc_info, &ds)) or_return
	}

	sa.push_back(&self.ready_pools, pool_to_use)

	return ds, true
}

descriptor_growable_get_pool :: proc(
	self: ^Descriptor_Allocator_Growable,
) -> (
	pool: vk.DescriptorPool,
	ok: bool,
) {
	if sa.len(self.ready_pools) > 0 {
		// Pop from ready pools
		pool = sa.pop_back(&self.ready_pools)
	} else {
		// Need to create a new pool
		pool = descriptor_growable_create_pool(self, self.sets_per_pool) or_return

		// Grow pool size by 50% each time, with an upper limit
		self.sets_per_pool = u32(f32(self.sets_per_pool) * 1.5)
		// 4096 is the maximum number of descriptor sets per pool supported by most Vulkan
		// implementations. Using 4092 instead of 4096 for alignment/padding safety
		if self.sets_per_pool > 4092 {
			self.sets_per_pool = 4092
		}
	}
	return pool, true
}

descriptor_growable_create_pool :: proc(
	self: ^Descriptor_Allocator_Growable,
	set_count: u32,
) -> (
	pool: vk.DescriptorPool,
	ok: bool,
) {
	pool_sizes: [MAX_POOL_SIZES]vk.DescriptorPoolSize

	for i in 0 ..< sa.len(self.ratios) {
		ratio := sa.get_ptr(&self.ratios, i)
		pool_sizes[i] = vk.DescriptorPoolSize {
			type            = ratio.type,
			descriptorCount = u32(ratio.ratio) * set_count,
		}
	}

	pool_info := vk.DescriptorPoolCreateInfo {
		sType         = .DESCRIPTOR_POOL_CREATE_INFO,
		maxSets       = set_count,
		poolSizeCount = u32(sa.len(self.ratios)),
		pPoolSizes    = &pool_sizes[0],
	}

	vk_check(vk.CreateDescriptorPool(self.device, &pool_info, nil, &pool)) or_return

	return pool, true
}

// =============================================================================
// Descriptor Writer
// =============================================================================

MAX_IMAGE_INFOS :: #config(MAX_IMAGE_INFOS, 64)
MAX_BUFFER_INFOS :: #config(MAX_BUFFER_INFOS, 64)
MAX_WRITES :: #config(MAX_WRITES, 128)

Image_Infos :: sa.Small_Array(MAX_IMAGE_INFOS, vk.DescriptorImageInfo)
Buffer_Infos :: sa.Small_Array(MAX_BUFFER_INFOS, vk.DescriptorBufferInfo)
Writes :: sa.Small_Array(MAX_WRITES, vk.WriteDescriptorSet)

Descriptor_Writer :: struct {
	device:       vk.Device,
	image_infos:  Image_Infos,
	buffer_infos: Buffer_Infos,
	writes:       Writes,
}

descriptor_writer_init :: proc(self: ^Descriptor_Writer, device: vk.Device) {
	self.device = device
}

descriptor_writer_write_image :: proc(
	self: ^Descriptor_Writer,
	binding: int,
	image: vk.ImageView,
	sampler: vk.Sampler,
	layout: vk.ImageLayout,
	type: vk.DescriptorType,
	loc := #caller_location,
) -> bool {
	assert(sa.space(self.image_infos) != 0, "No space left in image_infos array", loc)
	assert(sa.space(self.writes) != 0, "No space left in writes array", loc)

	// Add image info
	sa.push_back(
		&self.image_infos,
		vk.DescriptorImageInfo{sampler = sampler, imageView = image, imageLayout = layout},
	)

	info_ptr := sa.get_ptr(&self.image_infos, sa.len(self.image_infos) - 1)

	// Add write
	sa.push_back(
		&self.writes,
		vk.WriteDescriptorSet {
			sType           = .WRITE_DESCRIPTOR_SET,
			dstBinding      = u32(binding),
			dstSet          = 0, // Left empty for now until we need to write it
			descriptorCount = 1,
			descriptorType  = type,
			pImageInfo      = info_ptr,
		},
	)

	return true
}

descriptor_writer_write_buffer :: proc(
	self: ^Descriptor_Writer,
	binding: int,
	buffer: vk.Buffer,
	size: vk.DeviceSize,
	offset: vk.DeviceSize,
	type: vk.DescriptorType,
	loc := #caller_location,
) -> bool {
	assert(sa.space(self.buffer_infos) != 0, "No space left in buffer_infos array", loc)
	assert(sa.space(self.writes) != 0, "No space left in writes array", loc)

	// Add buffer info
	sa.push_back(
		&self.buffer_infos,
		vk.DescriptorBufferInfo{buffer = buffer, offset = offset, range = size},
	)

	info_ptr := sa.get_ptr(&self.buffer_infos, sa.len(self.buffer_infos) - 1)

	// Add write
	sa.push_back(
		&self.writes,
		vk.WriteDescriptorSet {
			sType           = .WRITE_DESCRIPTOR_SET,
			dstBinding      = u32(binding),
			dstSet          = 0, // Left empty for now until we need to write it
			descriptorCount = 1,
			descriptorType  = type,
			pBufferInfo     = info_ptr,
		},
	)

	return true
}

descriptor_writer_clear :: proc(self: ^Descriptor_Writer) {
	sa.clear(&self.image_infos)
	sa.clear(&self.buffer_infos)
	sa.clear(&self.writes)
}

descriptor_writer_update_set :: proc(
	self: ^Descriptor_Writer,
	set: vk.DescriptorSet,
	loc := #caller_location,
) {
	assert(self.device != nil, "Invalid 'Device'", loc)

	for &write in sa.slice(&self.writes) {
		write.dstSet = set
	}

	if sa.len(self.writes) > 0 {
		vk.UpdateDescriptorSets(
			self.device,
			u32(sa.len(self.writes)),
			raw_data(sa.slice(&self.writes)),
			0,
			nil,
		)
	}
}
