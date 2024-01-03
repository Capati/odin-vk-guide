package vk_bootstrap

// Core
import "core:mem"

@(private)
Instance_Error :: enum {
	None,
	Vulkan_Unavailable,
	Vulkan_Version_Unavailable,
	Vulkan_Version_1_3_Unavailable,
	Vulkan_Version_1_1_Unavailable,
	Vulkan_Version_1_2_Unavailable,
	Failed_Create_Instance,
	Failed_Create_Debug_Messenger,
	Requested_Layers_Not_Present,
	Requested_Extensions_Not_Present,
	Windowing_Extensions_Not_Present,
}

@(private)
Physical_Device_Error :: enum {
	None,
	No_Surface_Provided,
	Failed_Enumerate_Physical_Devices,
	Failed_Enumerate_Physical_Device_Extensions,
	No_Physical_Devices_Found,
	No_Suitable_Device,
}

@(private)
Queue_Error :: enum {
	None,
	Present_Unavailable,
	Graphics_Unavailable,
	Compute_Unavailable,
	Transfer_Unavailable,
	Queue_Index_Out_Of_Range,
	Invalid_Queue_Family_Index,
	Queue_Family_Properties_Empty,
}

@(private)
Device_Error :: enum {
	None,
	Failed_Create_Device,
	Physical_Device_Features2_In_P_Next_Chain_With_Add_Required_Extension_Features,
}

@(private)
Swapchain_Error :: enum {
	None,
	Surface_Handle_Not_Provided,
	Failed_Query_Surface_Support_Details,
	Failed_Create_Swapchain,
	Failed_Get_Swapchain_Images,
	Failed_Create_Swapchain_Image_Views,
	Required_Min_Image_Count_Too_Low,
	Required_Usage_Not_Supported,
}

@(private)
System_Info_Error :: enum {
	None,
	Instance_Layer_Error,
	Instance_Extension_Error,
}

@(private)
Surface_Support_Error :: enum {
	None,
	Surface_Handle_Null,
	Failed_Get_Surface_Capabilities,
	Failed_Enumerate_Surface_Formats,
	Failed_Enumerate_Present_Modes,
	No_Suitable_Desired_Format,
}

Error :: union #shared_nil {
	Instance_Error,
	Physical_Device_Error,
	Queue_Error,
	Device_Error,
	Swapchain_Error,
	System_Info_Error,
	Surface_Support_Error,
	mem.Allocator_Error,
}
