package vma

@(private)
Flags :: distinct u32

// Flags for created #VmaAllocator.
Allocator_Create_Flags :: distinct bit_set[Allocator_Create_Flag;Flags]
Allocator_Create_Flag :: enum Flags {
	Externally_Synchronized    = 0,
	Khr_Dedicated_Allocation   = 1,
	Khr_Bind_Memory2           = 2,
	Ext_Memory_Budget          = 3,
	Amd_Device_Coherent_Memory = 4,
	Buffer_Device_Address      = 5,
	Ext_Memory_Priority        = 6,
}

// Intended usage of the allocated memory.
Memory_Usage :: enum Flags {
	Unknown              = 0,
	Gpu_Only             = 1,
	Cpu_Only             = 2,
	Cpu_To_Gpu           = 3,
	Gpu_To_Cpu           = 4,
	Cpu_Copy             = 5,
	Gpu_Lazily_Allocated = 6,
	Auto                 = 7,
	Auto_Prefer_Device   = 8,
	Auto_Prefer_Host     = 9,
}

// Flags to be passed as `Allocation_Create_Info.flags`.
Allocation_Create_Flags :: distinct bit_set[Allocation_Create_Flag;Flags]
Allocation_Create_Flag :: enum Flags {
	Dedicated_Memory                   = 0,
	Never_Allocate                     = 1,
	Mapped                             = 2,
	User_Data_Copy_String              = 5,
	Upper_Address                      = 6,
	Dont_Bind                          = 7,
	Within_Budget                      = 8,
	Can_Alias                          = 9,
	Host_Access_Sequential_Write       = 10,
	Host_Access_Random                 = 11,
	Host_Access_Allow_Transfer_Instead = 12,
	Strategy_Min_Memory                = 16,
	Strategy_Min_Time                  = 17,
	Strategy_Min_Offset                = 18,
	Strategy_Best_Fit                  = Strategy_Min_Memory,
	Strategy_First_Fit                 = Strategy_Min_Time,
	Strategy_Mask                      = Strategy_Min_Memory | Strategy_Min_Time | Strategy_Min_Offset,
}

// Flags to be passed as `Pool_Create_Info.flags`.
Pool_Create_Flags :: distinct bit_set[Pool_Create_Flag;Flags]
Pool_Create_Flag :: enum Flags {
	Ignore_Buffer_Image_Granularity = 1,
	Linear_Algorithm                = 2,
	Algorithm_Mask                  = Linear_Algorithm,
}

//Flags to be passed as `Defragmentation_Info.flags`.
Defragmentation_Flags :: distinct bit_set[Defragmentation_Flag;Flags]
Defragmentation_Flag :: enum Flags {
	Algorithm_Fast      = 0,
	Algorithm_Balanced  = 1,
	Algorithm_Full      = 2,
	Algorithm_Extensive = 3,
	Algorithm_Mask      = Algorithm_Fast | Algorithm_Balanced | Algorithm_Full | Algorithm_Extensive,
}

// Operation performed on single defragmentation move. See structure `Defragmentation_Move`.
Defragmentation_Move_Operation :: enum Flags {
	Copy    = 0,
	Ignore  = 1,
	Destroy = 2,
}

// Flags to be passed as `Virtual_Block_Create_Info.flags`.
Virtual_Block_Create_Flags :: distinct bit_set[Virtual_Block_Create_Flag;Flags]
Virtual_Block_Create_Flag :: enum Flags {
	Linear_Algorithm = 1,
	Algorithm_Mask   = Linear_Algorithm,
}

// Flags to be passed as `Virtual_Allocation_Create_Info.flags`.
Virtual_Allocation_Create_Flags :: distinct bit_set[Virtual_Allocation_Create_Flag;Flags]
Virtual_Allocation_Create_Flag :: enum Flags {
	Upper_Address       = 7,
	Strategy_Min_Memory = 17,
	Strategy_Min_Time   = 18,
	Strategy_Min_Offset = 19,
	Strategy_Mask       = Strategy_Min_Memory | Strategy_Min_Time | Strategy_Min_Offset,
}
