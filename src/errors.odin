package main

// Core
import "core:mem"

// Libs
import "libs:vkb"

// Vendor
import vk "vendor:vulkan"

Window_Error :: enum {
	None,
	SDL_Init_Failed,
	Create_Window_Failed,
}

OS_Error :: enum {
	None,
	Read_File_Failed,
}

Error :: union #shared_nil {
	OS_Error,
	Window_Error,
	mem.Allocator_Error,
	vk.Result,
	vkb.Error,
}
