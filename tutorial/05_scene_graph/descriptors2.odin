package vk_guide

// Vendor
import vk "vendor:vulkan"

MAX_POOLS   :: #config(MAX_POOLS, 32)

Ratios      :: [dynamic; MAX_POOL_SIZES]Pool_Size_Ratio
Full_Pools  :: [dynamic; MAX_POOLS]vk.DescriptorPool
Ready_Pools :: [dynamic; MAX_POOLS]vk.DescriptorPool

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

    clear(&self.ratios)
    clear(&self.full_pools)
    clear(&self.ready_pools)

    for r in pool_ratios {
        append(&self.ratios, r)
    }

    new_pool := descriptor_growable_create_pool(self, max_sets) or_return

    // Grow it next allocation
    self.sets_per_pool = u32(f32(max_sets) * 1.5)

    append(&self.ready_pools, new_pool)

    return true
}

descriptor_growable_clear_pools :: proc(self: ^Descriptor_Allocator_Growable) -> (ok: bool) {
    // Reset ready pools
    for &pool in self.ready_pools {
        vk_check(vk.ResetDescriptorPool(self.device, pool, {})) or_return
    }

    // Reset full pools and move them to ready
    for &pool in self.full_pools {
        vk_check(vk.ResetDescriptorPool(self.device, pool, {})) or_return
        append(&self.ready_pools, pool)
    }

    clear(&self.full_pools)

    return true
}

descriptor_growable_destroy_pools :: proc(self: Descriptor_Allocator_Growable) {
    // Destroy ready pools
    for pool in self.ready_pools {
        vk.DestroyDescriptorPool(self.device, pool, nil)
    }

    // Destroy full pools
    for pool in self.full_pools {
        vk.DestroyDescriptorPool(self.device, pool, nil)
    }
}

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
        append(&self.full_pools, pool_to_use)

        pool_to_use = descriptor_growable_get_pool(self) or_return
        alloc_info.descriptorPool = pool_to_use
        vk_check(vk.AllocateDescriptorSets(self.device, &alloc_info, &ds)) or_return
    }

    append(&self.ready_pools, pool_to_use)

    return ds, true
}

descriptor_growable_get_pool :: proc(
    self: ^Descriptor_Allocator_Growable,
) -> (
    pool: vk.DescriptorPool,
    ok: bool,
) {
    if len(self.ready_pools) > 0 {
        // Pop from ready pools
        pool = pop(&self.ready_pools)
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

    for i in 0 ..< len(self.ratios) {
        ratio := &self.ratios[i]
        pool_sizes[i] = vk.DescriptorPoolSize {
            type            = ratio.type,
            descriptorCount = u32(ratio.ratio) * set_count,
        }
    }

    pool_info := vk.DescriptorPoolCreateInfo {
        sType         = .DESCRIPTOR_POOL_CREATE_INFO,
        maxSets       = set_count,
        poolSizeCount = u32(len(self.ratios)),
        pPoolSizes    = raw_data(pool_sizes[:]),
    }

    vk_check(vk.CreateDescriptorPool(self.device, &pool_info, nil, &pool)) or_return

    return pool, true
}

MAX_IMAGE_INFOS  :: #config(MAX_IMAGE_INFOS, 64)
MAX_BUFFER_INFOS :: #config(MAX_BUFFER_INFOS, 64)
MAX_WRITES       :: #config(MAX_WRITES, 128)

Image_Infos      :: [dynamic; MAX_IMAGE_INFOS]vk.DescriptorImageInfo
Buffer_Infos     :: [dynamic; MAX_BUFFER_INFOS]vk.DescriptorBufferInfo
Writes           :: [dynamic; MAX_WRITES]vk.WriteDescriptorSet

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
    assert(cap(self.image_infos) != 0, "No space left in image_infos array", loc)
    assert(cap(self.writes) != 0, "No space left in writes array", loc)

    // Add image info
    append(&self.image_infos,
        vk.DescriptorImageInfo{sampler = sampler, imageView = image, imageLayout = layout})

    info_ptr := &self.image_infos[len(self.image_infos) - 1]

    // Add write
    append(&self.writes, vk.WriteDescriptorSet {
        sType           = .WRITE_DESCRIPTOR_SET,
        dstBinding      = u32(binding),
        dstSet          = 0, // Left empty for now until we need to write it
        descriptorCount = 1,
        descriptorType  = type,
        pImageInfo      = info_ptr,
    })

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
    assert(cap(self.buffer_infos) != 0, "No space left in buffer_infos array", loc)
    assert(cap(self.writes) != 0, "No space left in writes array", loc)

    // Add buffer info
    append(&self.buffer_infos,
        vk.DescriptorBufferInfo{buffer = buffer, offset = offset, range = size})

    info_ptr := &self.buffer_infos[len(self.buffer_infos) - 1]

    // Add write
    append(&self.writes, vk.WriteDescriptorSet {
        sType           = .WRITE_DESCRIPTOR_SET,
        dstBinding      = u32(binding),
        dstSet          = 0, // Left empty for now until we need to write it
        descriptorCount = 1,
        descriptorType  = type,
        pBufferInfo     = info_ptr,
    })

    return true
}

descriptor_writer_clear :: proc(self: ^Descriptor_Writer) {
    clear(&self.image_infos)
    clear(&self.buffer_infos)
    clear(&self.writes)
}

descriptor_writer_update_set :: proc(
    self: ^Descriptor_Writer,
    set: vk.DescriptorSet,
    loc := #caller_location,
) {
    assert(self.device != nil, "Invalid 'Device'", loc)

    for &write in self.writes {
        write.dstSet = set
    }

    if len(self.writes) > 0 {
        vk.UpdateDescriptorSets(
            self.device,
            u32(len(self.writes)),
            raw_data(self.writes[:]),
            0,
            nil,
        )
    }
}
