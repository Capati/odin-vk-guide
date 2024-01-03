package main

// Libs
import "libs:vk-bootstrap/vkb"

Window_Error :: enum {
	None,
	SDL_Init_Failed,
	Create_Window_Failed,
}

Vulkan_Error :: enum {
	None,
	Vulkan_Create_Error,
	Vulkan_Allocate_Error,
}

Error :: union #shared_nil {
	Window_Error,
	vkb.Error,
	Vulkan_Error,
}
