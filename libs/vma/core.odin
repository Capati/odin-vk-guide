package vma

STATS_STRING_ENABLED :: 1
VULKAN_VERSION :: 1003000
DEDICATED_ALLOCATION :: 1
BIND_MEMORY2 :: 1
MEMORY_BUDGET :: 1
BUFFER_DEVICE_ADDRESS :: 1
MEMORY_PRIORITY :: 1
EXTERNAL_MEMORY :: 1

@(private)
// Base core handle
Handle :: distinct rawptr

@(private)
// Base core non dispatchable handle
Non_Dispatchable_Handle :: distinct u64

// Represents main object of this library initialized.
Allocator :: distinct Handle

// Represents custom memory pool.
Pool :: distinct Handle

// Represents single memory allocation.
Allocation :: distinct Handle

// An opaque object that represents started defragmentation process.
Defragmentation_Context :: distinct Handle

// Represents single memory allocation done inside `VirtualBlock`.
Virtual_Allocation :: distinct Non_Dispatchable_Handle

// Handle to a virtual block object that allows to use core allocation algorithm without
// allocating any real GPU memory.
Virtual_Block :: distinct Handle
