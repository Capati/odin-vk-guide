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

Error :: union #shared_nil {
	mem.Allocator_Error,
	Window_Error,
	vkb.Error,
	vk.Result,
}
