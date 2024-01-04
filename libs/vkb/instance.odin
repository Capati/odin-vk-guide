package vk_bootstrap

// Vendor
import vk "vendor:vulkan"

Instance :: struct {
	ptr:                     vk.Instance,
	debug_messenger:         vk.DebugUtilsMessengerEXT,
	allocation_callbacks:    ^vk.AllocationCallbacks,
	headless:                bool,
	properties2_ext_enabled: bool,
	instance_version:        u32,
	api_version:             u32,
}

// Destroy the surface created from this instance.
destroy_surface :: proc(self: ^Instance, surface: vk.SurfaceKHR) {
	if self != nil && self.ptr != nil && surface != 0 {
		vk.DestroySurfaceKHR(self.ptr, surface, self.allocation_callbacks)
	}
}

// Destroy the instance and the debug messenger.
destroy_instance :: proc(self: ^Instance) {
	if self == nil do return
	defer free(self)
	if self.ptr != nil {
		if self.debug_messenger != 0 {
			vk.DestroyDebugUtilsMessengerEXT(self.ptr, self.debug_messenger, nil)
		}
		vk.DestroyInstance(self.ptr, nil)
	}
}
