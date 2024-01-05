package main

// Vendor
import vk "vendor:vulkan"

FRAME_OVERLAP: u32 : 2

Frame_Data :: struct {
	command_pool:        vk.CommandPool,
	main_command_buffer: vk.CommandBuffer,
	swapchain_semaphore: vk.Semaphore,
	render_semaphore:    vk.Semaphore,
	render_fence:        vk.Fence,
	deletors:            Deletion_Queue,
}

engine_get_current_frame :: proc() -> Frame_Data {
	return _ctx.frames[_ctx.frame_number % FRAME_OVERLAP]
}
