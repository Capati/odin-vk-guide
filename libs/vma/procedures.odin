package vma

// Core
import "core:c"

// Vendor
import vk "vendor:vulkan"

when ODIN_OS == .Windows {
	foreign import vma {"./lib/vma.lib", "system:MSVCRT.lib", "system:libcmt.lib"}
} else when ODIN_OS == .Darwin {
	// TODO(Capati): no mac/os libs yet!
} else when ODIN_OS == .Linux {
	foreign import vma {"lib/libvma.a", "system:stdc++"}
} else {
	foreign import vma "system:vma"
}

// Callback procedure called after successful `vk.AllocateMemory`.
Allocate_Device_Memory_Proc :: proc "c" (
	allocator: Allocator,
	memory_type: c.uint32_t,
	memory: vk.DeviceMemory,
	size: vk.DeviceSize,
	user_data: rawptr,
)

// Callback procedure called before `vk.FreeMemory`.
Free_Device_Memory_Proc :: proc "c" (
	allocator: Allocator,
	memory_type: c.uint32_t,
	memory: vk.DeviceMemory,
	size: vk.DeviceSize,
	user_data: rawptr,
)

// Bind vulkan functions to vma.
create_vulkan_functions :: proc() -> (functions: Vulkan_Functions) {
	functions = Vulkan_Functions {
		get_physical_device_properties             = vk.GetPhysicalDeviceProperties,
		get_physical_device_memory_properties      = vk.GetPhysicalDeviceMemoryProperties,
		allocate_memory                            = vk.AllocateMemory,
		free_memory                                = vk.FreeMemory,
		map_memory                                 = vk.MapMemory,
		unmap_memory                               = vk.UnmapMemory,
		flush_mapped_memory_ranges                 = vk.FlushMappedMemoryRanges,
		invalidate_mapped_memory_ranges            = vk.InvalidateMappedMemoryRanges,
		bind_buffer_memory                         = vk.BindBufferMemory,
		bind_image_memory                          = vk.BindImageMemory,
		get_buffer_memory_requirements             = vk.GetBufferMemoryRequirements,
		get_image_memory_requirements              = vk.GetImageMemoryRequirements,
		create_buffer                              = vk.CreateBuffer,
		destroy_buffer                             = vk.DestroyBuffer,
		create_image                               = vk.CreateImage,
		destroy_image                              = vk.DestroyImage,
		cmd_copy_buffer                            = vk.CmdCopyBuffer,
		get_buffer_memory_requirements2_khr        = vk.GetBufferMemoryRequirements2KHR,
		get_image_memory_requirements2_khr         = vk.GetImageMemoryRequirements2KHR,
		bind_buffer_memory2_khr                    = vk.BindBufferMemory2KHR,
		bind_image_memory2_khr                     = vk.BindImageMemory2KHR,
		get_physical_device_memory_properties2_khr = vk.GetPhysicalDeviceMemoryProperties2KHR,
		get_device_buffer_memory_requirements      = vk.GetDeviceBufferMemoryRequirements,
		get_device_image_memory_requirements       = vk.GetDeviceImageMemoryRequirements,
	}

	return
}

@(default_calling_convention = "c")
foreign vma {
	// Creates `Allocator` object.
	@(link_name = "vmaCreateAllocator")
	create_allocator :: proc(create_info: ^Allocator_Create_Info, allocator: ^Allocator) -> vk.Result ---

	// Destroys allocator object.
	@(link_name = "vmaDestroyAllocator")
	destroy_allocator :: proc(allocator: Allocator) ---

	// Returns information about existing `Allocator` object - handle to Vulkan device etc.
	@(link_name = "vmaGetAllocatorInfo")
	get_allocator_info :: proc(allocator: Allocator, allocator_info: ^Allocator_Info) ---

	// `PhysicalDeviceProperties` are fetched from physicalDevice by the allocator.
	@(link_name = "vmaGetPhysicalDeviceProperties")
	get_physical_device_properties :: proc(allocator: Allocator, physical_device_properties: ^^vk.PhysicalDeviceProperties) ---

	// `PhysicalDeviceMemoryProperties` are fetched from physicalDevice by the allocator.
	@(link_name = "vmaGetMemoryProperties")
	get_memory_properties :: proc(allocator: Allocator, physical_device_memory_properties: ^^vk.PhysicalDeviceMemoryProperties) ---

	// Given Memory Type Index, returns Property Flags of this memory type
	@(link_name = "vmaGetMemoryTypeProperties")
	get_memory_type_properties :: proc(allocator: Allocator, memory_type_index: c.uint32_t, flags: ^vk.MemoryPropertyFlags) ---

	// Sets index of the current frame.
	@(link_name = "vmaSetCurrentFrameIndex")
	set_current_frame_index :: proc(allocator: Allocator, frame_index: c.uint32_t) ---

	// Retrieves statistics from current state of the `Allocator`.
	@(link_name = "vmaCalculateStatistics")
	calculate_statistics :: proc(allocator: Allocator, stats: ^Total_Statistics) ---

	// Retrieves information about current memory usage and budget for all memory heaps.
	@(link_name = "vmaGetHeapBudgets")
	get_heap_budgets :: proc(allocator: Allocator, budgets: ^Budget) ---

	// Helps to find `memory_type_index`, given `memory_type_bits` and `Allocation_Create_Info`.
	@(link_name = "vmaFindMemoryTypeIndex")
	find_memory_type_index :: proc(allocator: Allocator, memory_type_bits: c.uint32_t, allocation_create_info: ^Allocation_Create_Info, memory_type_index: ^c.uint32_t) -> vk.Result ---

	// Helps to find `memory_type_index`, given `vk.BufferCreateInfo` and `Allocation_Create_Info`.
	@(link_name = "vmaFindMemoryTypeIndexForBufferInfo")
	find_memory_type_index_for_buffer_info :: proc(allocator: Allocator, buffer_create_info: ^vk.BufferCreateInfo, allocation_create_info: ^Allocation_Create_Info, memory_type_index: ^c.uint32_t) -> vk.Result ---

	// Helps to find `memory_type_index`, given `vk.ImageCreateInfo` and `Allocation_Create_Info`.
	@(link_name = "vmaFindMemoryTypeIndexForImageInfo")
	find_memory_type_index_for_image_info :: proc(allocator: Allocator, image_create_info: ^vk.ImageCreateInfo, allocation_create_info: ^Allocation_Create_Info, memory_type_index: ^c.uint32_t) -> vk.Result ---

	// Allocates Vulkan device memory and creates `Pool` object.
	@(link_name = "vmaCreatePool")
	create_pool :: proc(allocator: Allocator, create_info: ^Pool_Create_Info, pool: ^Pool) -> vk.Result ---

	// Destroys `Pool` object and frees Vulkan device memory.
	@(link_name = "vmaDestroyPool")
	destroy_pool :: proc(allocator: Allocator, pool: Pool) ---

	// Retrieves statistics of existing `Pool` object.
	@(link_name = "vmaGetPoolStatistics")
	get_pool_statistics :: proc(allocator: Allocator, pool: Pool, pool_stats: ^Statistics) ---

	// Retrieves detailed statistics of existing `Pool` object.
	@(link_name = "vmaCalculatePoolStatistics")
	calculate_pool_statistics :: proc(allocator: Allocator, pool: Pool, pool_stats: ^Detailed_Statistics) ---

	// Checks magic number in margins around all allocations in given memory pool in search for
	// corruptions.
	@(link_name = "vmaCheckPoolCorruption")
	check_pool_corruption :: proc(allocator: Allocator, pool: Pool) -> vk.Result ---

	// Retrieves name of a custom pool.
	@(link_name = "vmaGetPoolName")
	get_pool_name :: proc(allocator: Allocator, pool: Pool, name: ^cstring) ---

	// Sets name of a custom pool.
	@(link_name = "vmaSetPoolName")
	set_pool_name :: proc(allocator: Allocator, pool: Pool, name: cstring) ---

	// General purpose memory allocation.
	@(link_name = "vmaAllocateMemory")
	allocate_memory :: proc(allocator: Allocator, vk_memory_requirements: ^vk.MemoryRequirements, create_info: ^Allocation_Create_Info, allocation: ^Allocation, allocation_info: ^Allocation_Info) -> vk.Result ---

	// General purpose memory allocation for multiple allocation objects at once.
	@(link_name = "vmaAllocateMemoryPages")
	allocate_memory_pages :: proc(allocator: Allocator, vk_memory_requirements: ^vk.MemoryRequirements, create_info: ^Allocation_Create_Info, allocation_count: c.size_t, allocations: ^Allocation, allocation_info: ^Allocation_Info) -> vk.Result ---

	// Allocates memory suitable for given `vk.Buffer`.
	@(link_name = "vmaAllocateMemoryForBuffer")
	allocate_memory_for_buffer :: proc(allocator: Allocator, buffer: vk.Buffer, create_info: ^Allocation_Create_Info, allocation: ^Allocation, allocation_info: ^Allocation_Info) -> vk.Result ---

	// Allocates memory suitable for given `vk.Image`.
	@(link_name = "vmaAllocateMemoryForImage")
	allocate_memory_for_image :: proc(allocator: Allocator, image: vk.Image, create_info: ^Allocation_Create_Info, allocation: ^Allocation, allocation_info: ^Allocation_Info) -> vk.Result ---

	// Frees memory previously allocated using `allocate_memory()`, `allocate_memory_for_buffer()`,
	// or `allocate_memory_for_image()`.
	@(link_name = "vmaFreeMemory")
	free_memory :: proc(allocator: Allocator, allocation: Allocation) ---

	// Frees memory and destroys multiple allocations.
	@(link_name = "vmaFreeMemoryPages")
	free_memory_pages :: proc(allocator: Allocator, allocation_count: c.size_t, allocations: ^Allocation) ---

	// Returns current information about specified allocation.
	@(link_name = "vmaGetAllocationInfo")
	get_allocation_info :: proc(allocator: Allocator, allocation: Allocation, allocation_info: ^Allocation_Info) ---

	// Sets `user_data` in given allocation to new value.
	@(link_name = "vmaSetAllocationUserData")
	set_allocation_user_data :: proc(allocator: Allocator, allocation: Allocation, user_data: rawptr) ---

	// Sets `nae` in given allocation to new value.
	@(link_name = "vmaSetAllocationName")
	set_allocation_name :: proc(allocator: Allocator, allocation: Allocation, name: cstring) ---

	// Given an allocation, returns Property Flags of its memory type.
	@(link_name = "vmaGetAllocationMemoryProperties")
	get_allocation_memory_properties :: proc(allocator: Allocator, allocation: Allocation, flags: ^vk.MemoryPropertyFlags) ---

	// Maps memory represented by given allocation and returns pointer to it.
	@(link_name = "vmaMapMemory")
	map_memory :: proc(allocator: Allocator, allocation: Allocation, data: ^rawptr) -> vk.Result ---

	// Unmaps memory represented by given allocation, mapped previously using `map_memory()`.
	@(link_name = "vmaUnmapMemory")
	unmap_memory :: proc(allocator: Allocator, allocation: Allocation) ---

	// Flushes memory of given allocation.
	@(link_name = "vmaFlushAllocation")
	flush_allocation :: proc(allocator: Allocator, allocation: Allocation, offset: vk.DeviceSize, size: vk.DeviceSize) -> vk.Result ---

	// Invalidates memory of given allocation.
	@(link_name = "vmaInvalidateAllocation")
	invalidate_allocation :: proc(allocator: Allocator, allocation: Allocation, offset: vk.DeviceSize, size: vk.DeviceSize) -> vk.Result ---

	// Flushes memory of given set of allocations.
	@(link_name = "vmaFlushAllocations")
	flush_allocations :: proc(allocator: Allocator, allocation_count: c.uint32_t, allocations: ^Allocation, offsets: ^vk.DeviceSize, sizes: ^vk.DeviceSize) -> vk.Result ---

	// Invalidates memory of given set of allocations.
	@(link_name = "vmaInvalidateAllocations")
	invalidate_allocations :: proc(allocator: Allocator, allocation_count: c.uint32_t, allocations: ^Allocation, offsets: ^vk.DeviceSize, sizes: ^vk.DeviceSize) -> vk.Result ---

	// Checks magic number in margins around all allocations in given memory types (in both default
	// and custom pools) in search for corruptions.
	@(link_name = "vmaCheckCorruption")
	check_corruption :: proc(allocator: Allocator, memory_type_bits: c.uint32_t) -> vk.Result ---

	// Begins defragmentation process.
	@(link_name = "vmaBeginDefragmentation")
	begin_defragmentation :: proc(allocator: Allocator, info: ^Defragmentation_Info, ctx: ^Defragmentation_Context) -> vk.Result ---

	// Ends defragmentation process.
	@(link_name = "vmaEndDefragmentation")
	end_defragmentation :: proc(allocator: Allocator, ctx: Defragmentation_Context, pStats: ^Defragmentation_Stats) ---

	// Starts single defragmentation pass.
	@(link_name = "vmaBeginDefragmentationPass")
	begin_defragmentation_pass :: proc(allocator: Allocator, ctx: Defragmentation_Context, pass_info: ^Defragmentation_Pass_Move_Info) -> vk.Result ---

	// Ends single defragmentation pass.
	@(link_name = "vmaEndDefragmentationPass")
	end_defragmentation_pass :: proc(allocator: Allocator, ctx: Defragmentation_Context, pPassInfo: ^Defragmentation_Pass_Move_Info) -> vk.Result ---

	// Binds buffer to allocation.
	@(link_name = "vmaBindBufferMemory")
	bind_buffer_memory :: proc(allocator: Allocator, allocation: Allocation, buffer: vk.Buffer) -> vk.Result ---

	// Binds buffer to allocation with additional parameters.
	@(link_name = "vmaBindBufferMemory2")
	bind_buffer_memory2 :: proc(allocator: Allocator, allocation: Allocation, allocation_local_offset: vk.DeviceSize, buffer: vk.Buffer, next: rawptr) -> vk.Result ---

	// Binds image to allocation.
	@(link_name = "vmaBindImageMemory")
	bind_image_memory :: proc(allocator: Allocator, allocation: Allocation, image: vk.Image) -> vk.Result ---

	// Binds image to allocation with additional parameters.
	@(link_name = "vmaBindImageMemory2")
	bind_image_memory2 :: proc(allocator: Allocator, allocation: Allocation, allocation_local_offset: vk.DeviceSize, image: vk.Image, next: rawptr) -> vk.Result ---

	// Creates a new `VkBuffer`, allocates and binds memory for it.
	@(link_name = "vmaCreateBuffer")
	create_buffer :: proc(allocator: Allocator, buffer_create_info: ^vk.BufferCreateInfo, allocation_create_info: ^Allocation_Create_Info, buffer: ^vk.Buffer, allocation: ^Allocation, allocation_info: ^Allocation_Info) -> vk.Result ---

	// Creates a buffer with additional minimum alignment.
	@(link_name = "vmaCreateBufferWithAlignment")
	create_buffer_with_alignment :: proc(allocator: Allocator, buffer_create_info: ^vk.BufferCreateInfo, allocation_create_info: ^Allocation_Create_Info, min_alignment: vk.DeviceSize, buffer: ^vk.Buffer, allocation: ^Allocation, allocation_info: ^Allocation_Info) -> vk.Result ---

	// Creates a new `vk.Buffer`, binds already created memory for it.
	@(link_name = "vmaCreateAliasingBuffer")
	create_aliasing_buffer :: proc(allocator: Allocator, allocation: Allocation, buffer_create_info: ^vk.BufferCreateInfo, buffer: ^vk.Buffer) -> vk.Result ---

	// Destroys Vulkan buffer and frees allocated memory.
	@(link_name = "vmaDestroyBuffer")
	destroy_buffer :: proc(allocator: Allocator, buffer: vk.Buffer, allocation: Allocation) ---

	// Function similar to `create_buffer()`.
	@(link_name = "vmaCreateImage")
	create_image :: proc(allocator: Allocator, image_create_info: ^vk.ImageCreateInfo, allocation_create_info: ^Allocation_Create_Info, image: ^vk.Image, allocation: ^Allocation, allocation_info: ^Allocation_Info) -> vk.Result ---

	// Function similar to `create_aliasing_buffer()`.
	@(link_name = "vmaCreateAliasingImage")
	create_aliasing_image :: proc(allocator: Allocator, allocation: Allocation, image_create_info: ^vk.ImageCreateInfo, image: ^vk.Image) -> vk.Result ---

	// Destroys Vulkan image and frees allocated memory.
	@(link_name = "vmaDestroyImage")
	destroy_image :: proc(allocator: Allocator, image: vk.Image, allocation: Allocation) ---

	// Creates new `Virtual_Block` object.
	@(link_name = "vmaCreateVirtualBlock")
	create_virtual_block :: proc(create_info: ^Virtual_Block_Create_Info, virtual_block: ^Virtual_Block) -> vk.Result ---

	// Destroys `Virtual_Block` object.
	@(link_name = "vmaDestroyVirtualBlock")
	destroy_virtual_block :: proc(virtual_block: Virtual_Block) ---

	// Returns true of the `Virtual_Block` is empty - contains 0 virtual allocations and has all
	// its space available for new allocations.
	@(link_name = "vmaIsVirtualBlockEmpty")
	is_virtual_block_empty :: proc(virtual_block: Virtual_Block) -> c.bool ---

	// Returns information about a specific virtual allocation within a virtual block, like its
	// size and `user_data` pointer.
	@(link_name = "vmaGetVirtualAllocationInfo")
	get_virtual_allocation_info :: proc(virtual_block: Virtual_Block, allocation: Virtual_Allocation, virtual_alloc_info: ^Virtual_Allocation_Info) ---

	// Allocates new virtual allocation inside given #VmaVirtualBlock.
	@(link_name = "vmaVirtualAllocate")
	virtual_allocate :: proc(virtual_block: Virtual_Block, create_info: ^Virtual_Allocation_Create_Info, allocation: ^Virtual_Allocation, offset: ^vk.DeviceSize) -> vk.Result ---

	// Frees virtual allocation inside given #VmaVirtualBlock.
	@(link_name = "vmaVirtualFree")
	virtual_free :: proc(virtual_block: Virtual_Block, allocation: Virtual_Allocation) ---

	// Frees all virtual allocations inside given #VmaVirtualBlock.
	@(link_name = "vmaClearVirtualBlock")
	clear_virtual_block :: proc(virtual_block: Virtual_Block) ---

	// Changes custom pointer associated with given virtual allocation.
	@(link_name = "vmaSetVirtualAllocationUserData")
	set_virtual_allocation_user_data :: proc(virtual_block: Virtual_Block, allocation: Virtual_Allocation, user_data: rawptr) ---

	// Calculates and returns statistics about virtual allocations and memory usage in given
	// `Virtual_Block`.
	@(link_name = "vmaGetVirtualBlockStatistics")
	get_virtual_block_statistics :: proc(virtual_block: Virtual_Block, stats: ^Statistics) ---

	// Calculates and returns detailed statistics about virtual allocations and memory usage in given `Virtual_Block`.
	@(link_name = "vmaCalculateVirtualBlockStatistics")
	calculate_virtual_block_statistics :: proc(virtual_block: Virtual_Block, stats: ^Detailed_Statistics) ---

	// Builds and returns a null-terminated string in JSON format with information about given
	// `Virtual_Block`.
	@(link_name = "vmaBuildVirtualBlockStatsString")
	build_virtual_block_stats_string :: proc(virtual_block: Virtual_Block, stats_string: ^cstring, detailed_map: c.bool) ---

	// Frees a string returned by `build_virtual_block_stats_string()`.
	@(link_name = "vmaFreeVirtualBlockStatsString")
	free_virtual_block_stats_string :: proc(virtual_block: Virtual_Block, stats_string: cstring) ---

	// Builds and returns statistics as a null-terminated string in JSON format.
	@(link_name = "vmaBuildStatsString")
	build_stats_string :: proc(allocator: Allocator, stats_string: ^cstring, detailed_map: c.bool) ---

	// Frees a string returned by `build_stats_string()`.
	@(link_name = "vmaFreeStatsString")
	free_stats_string :: proc(allocator: Allocator, stats_string: cstring) ---
}
