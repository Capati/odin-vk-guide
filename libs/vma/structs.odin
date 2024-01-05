package vma

// Core
import "core:c"

// Vendor
import vk "vendor:vulkan"

// Set of callbacks that the library will call for `vk.AllocateMemory` and `vk.FreeMemory`.
Device_Memory_Callbacks :: struct {
	allocate_proc: Allocate_Device_Memory_Proc,
	free_proc:     Free_Device_Memory_Proc,
	user_data:     rawptr,
}

// Pointers to some Vulkan functions - a subset used by the library.
Vulkan_Functions :: struct {
	unused_1:                                   proc(), //vkGetInstanceProcAddr
	unused_2:                                   proc(), //vkGetDeviceProcAddr
	get_physical_device_properties:             vk.ProcGetPhysicalDeviceProperties,
	get_physical_device_memory_properties:      vk.ProcGetPhysicalDeviceMemoryProperties,
	allocate_memory:                            vk.ProcAllocateMemory,
	free_memory:                                vk.ProcFreeMemory,
	map_memory:                                 vk.ProcMapMemory,
	unmap_memory:                               vk.ProcUnmapMemory,
	flush_mapped_memory_ranges:                 vk.ProcFlushMappedMemoryRanges,
	invalidate_mapped_memory_ranges:            vk.ProcInvalidateMappedMemoryRanges,
	bind_buffer_memory:                         vk.ProcBindBufferMemory,
	bind_image_memory:                          vk.ProcBindImageMemory,
	get_buffer_memory_requirements:             vk.ProcGetBufferMemoryRequirements,
	get_image_memory_requirements:              vk.ProcGetImageMemoryRequirements,
	create_buffer:                              vk.ProcCreateBuffer,
	destroy_buffer:                             vk.ProcDestroyBuffer,
	create_image:                               vk.ProcCreateImage,
	destroy_image:                              vk.ProcDestroyImage,
	cmd_copy_buffer:                            vk.ProcCmdCopyBuffer,
	get_buffer_memory_requirements2_khr:        vk.ProcGetBufferMemoryRequirements2KHR,
	get_image_memory_requirements2_khr:         vk.ProcGetImageMemoryRequirements2KHR,
	bind_buffer_memory2_khr:                    vk.ProcBindBufferMemory2KHR,
	bind_image_memory2_khr:                     vk.ProcBindImageMemory2KHR,
	get_physical_device_memory_properties2_khr: vk.ProcGetPhysicalDeviceMemoryProperties2KHR,
	get_device_buffer_memory_requirements:      vk.ProcGetDeviceBufferMemoryRequirements,
	get_device_image_memory_requirements:       vk.ProcGetDeviceImageMemoryRequirements,
}

// Description of a `Allocator` to be created.
Allocator_Create_Info :: struct {
	flags:                             Allocator_Create_Flags,
	physical_device:                   vk.PhysicalDevice,
	device:                            vk.Device,
	preferred_large_heap_block_size:   vk.DeviceSize,
	allocation_callbacks:              ^vk.AllocationCallbacks,
	device_memory_callbacks:           ^Device_Memory_Callbacks,
	heap_size_limit:                   ^vk.DeviceSize,
	vulkan_functions:                  ^Vulkan_Functions,
	instance:                          vk.Instance,
	vulkan_api_version:                c.uint32_t,
	type_external_memory_handle_types: ^vk.ExternalMemoryHandleTypeFlagsKHR,
}

// Information about existing #VmaAllocator object.
Allocator_Info :: struct {
	instance:        vk.Instance,
	physical_device: vk.PhysicalDevice,
	device:          vk.Device,
}

// Calculated statistics of memory usage e.g. in a specific memory type, heap, custom pool,
// or total.
Statistics :: struct {
	block_count:      c.uint32_t,
	allocation_count: c.uint32_t,
	block_bytes:      vk.DeviceSize,
	allocation_bytes: vk.DeviceSize,
}

// More detailed statistics than `Statistics`
Detailed_Statistics :: struct {
	statistics:            Statistics,
	unused_range_count:    c.uint32_t,
	allocation_size_min:   vk.DeviceSize,
	allocation_size_max:   vk.DeviceSize,
	unused_range_size_min: vk.DeviceSize,
	unused_range_size_max: vk.DeviceSize,
}

// General statistics from current state of the `Allocator`.
Total_Statistics :: struct {
	memory_type: [32]Detailed_Statistics,
	memory_heap: [16]Detailed_Statistics,
	total:       Detailed_Statistics,
}

// Statistics of current memory usage and available budget for a specific memory heap
Budget :: struct {
	statistics: Statistics,
	usage:      vk.DeviceSize,
	budget:     vk.DeviceSize,
}

// Parameters of new `Allocation`.
Allocation_Create_Info :: struct {
	flags:            Allocation_Create_Flags,
	usage:            Memory_Usage,
	required_flags:   vk.MemoryPropertyFlags,
	preferred_flags:  vk.MemoryPropertyFlags,
	memory_type_bits: c.uint32_t,
	pool:             Pool,
	user_data:        rawptr,
	priority:         c.float,
}

// Describes parameter of created `Pool`.
Pool_Create_Info :: struct {
	memory_type_index:        c.uint32_t,
	flags:                    Pool_Create_Flags,
	block_size:               vk.DeviceSize,
	min_block_count:          c.size_t,
	max_block_count:          c.size_t,
	priority:                 c.float,
	min_allocation_alignment: vk.DeviceSize,
	memory_allocate_next:     rawptr,
}

// Parameters of `Allocation` objects, that can be retrieved using procedure `get_allocation_info`.
Allocation_Info :: struct {
	memory_type:   c.uint32_t,
	device_memory: vk.DeviceMemory,
	offset:        vk.DeviceSize,
	size:          vk.DeviceSize,
	mapped_data:   rawptr,
	user_data:     rawptr,
	name:          cstring,
}

// Parameters for defragmentation
Defragmentation_Info :: struct {
	flags:                    Defragmentation_Flags,
	pool:                     Pool,
	max_bytes_per_pass:       vk.DeviceSize,
	max_allocations_per_pass: c.uint32_t,
}

// Single move of an allocation to be done for defragmentation
Defragmentation_Move :: struct {
	operation:          Defragmentation_Move_Operation,
	src_allocation:     Allocation,
	dst_tmp_allocation: Allocation,
}

// Parameters for incremental defragmentation steps
Defragmentation_Pass_Move_Info :: struct {
	move_count: c.uint32_t,
	moves:      ^Defragmentation_Move,
}

// Statistics returned for defragmentation process in procedure `end_defragmentation`.
Defragmentation_Stats :: struct {
	bytes_moved:                vk.DeviceSize,
	bytes_freed:                vk.DeviceSize,
	allocations_moved:          c.uint32_t,
	device_memory_blocks_freed: c.uint32_t,
}

// Parameters of created `Virtual_Block` object to be passed to `create_virtual_block`.
Virtual_Block_Create_Info :: struct {
	size:                 vk.DeviceSize,
	flags:                Virtual_Block_Create_Flags,
	allocation_callbacks: ^vk.AllocationCallbacks,
}

// Parameters of created virtual allocation to be passed to `virtual_allocate`.
Virtual_Allocation_Create_Info :: struct {
	size:      vk.DeviceSize,
	alignment: vk.DeviceSize,
	flags:     Virtual_Allocation_Create_Flags,
	user_data: rawptr,
}

// Parameters of an existing virtual allocation, returned by `get_virtual_allocation_info`.
Virtual_Allocation_Info :: struct {
	offset:    vk.DeviceSize,
	size:      vk.DeviceSize,
	user_data: rawptr,
}
