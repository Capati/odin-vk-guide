package vk_bootstrap

// Core
import "core:log"

// Vendor
import vk "vendor:vulkan"

Device :: struct {
	ptr:                  vk.Device,
	physical_device:      ^Physical_Device,
	surface:              vk.SurfaceKHR,
	queue_families:       []vk.QueueFamilyProperties,
	allocation_callbacks: ^vk.AllocationCallbacks,
	instance_version:     u32,
}

Queue_Type :: enum {
	Present,
	Graphics,
	Compute,
	Transfer,
}

destroy_device :: proc(self: ^Device) {
	if self == nil do return
	defer free(self)
	delete(self.queue_families)
	vk.DestroyDevice(self.ptr, self.allocation_callbacks)
}

device_get_queue_index :: proc(self: ^Device, type: Queue_Type) -> (index: u32, err: Error) {
	index = vk.QUEUE_FAMILY_IGNORED

	switch type {
	case .Present:
		index = get_present_queue_index(
			self.queue_families,
			self.physical_device.ptr,
			self.surface,
		)
		if index == vk.QUEUE_FAMILY_IGNORED {
			log.error("Present queue index unavailable.")
			return vk.QUEUE_FAMILY_IGNORED, .Present_Unavailable
		}
	case .Graphics:
		index = get_first_queue_index(self.queue_families, {.GRAPHICS})
		if index == vk.QUEUE_FAMILY_IGNORED {
			log.error("Graphics queue index unavailable.")
			return vk.QUEUE_FAMILY_IGNORED, .Graphics_Unavailable
		}
	case .Compute:
		index = get_separate_queue_index(self.queue_families, {.COMPUTE}, {.TRANSFER})
		if index == vk.QUEUE_FAMILY_IGNORED {
			log.error("Compute queue index unavailable.")
			return vk.QUEUE_FAMILY_IGNORED, .Compute_Unavailable
		}
	case .Transfer:
		index = get_separate_queue_index(self.queue_families, {.TRANSFER}, {.COMPUTE})
		if index == vk.QUEUE_FAMILY_IGNORED {
			log.error("Transfer queue index unavailable.")
			return vk.QUEUE_FAMILY_IGNORED, .Transfer_Unavailable
		}
	}

	return
}

device_get_dedicated_queue_index :: proc(
	self: ^Device,
	type: Queue_Type,
) -> (
	index: u32,
	err: Error,
) {
	index = vk.QUEUE_FAMILY_IGNORED

	#partial switch type {
	case .Compute:
		index = get_dedicated_queue_index(self.queue_families, {.COMPUTE}, {.TRANSFER})
		if index == vk.QUEUE_FAMILY_IGNORED {
			log.error("Dedicated Compute queue index unavailable.")
			return vk.QUEUE_FAMILY_IGNORED, .Compute_Unavailable
		}
	case .Transfer:
		index = get_dedicated_queue_index(self.queue_families, {.TRANSFER}, {.COMPUTE})
		if index == vk.QUEUE_FAMILY_IGNORED {
			log.error("Dedicated Transfer queue index unavailable.")
			return vk.QUEUE_FAMILY_IGNORED, .Transfer_Unavailable
		}
	case:
		return vk.QUEUE_FAMILY_IGNORED, .Invalid_Queue_Family_Index
	}

	return
}

device_get_queue :: proc(self: ^Device, type: Queue_Type) -> (queue: vk.Queue, err: Error) {
	index := device_get_queue_index(self, type) or_return
	vk.GetDeviceQueue(self.ptr, index, 0, &queue)
	return
}

device_get_dedicated_queue :: proc(
	self: ^Device,
	type: Queue_Type,
) -> (
	queue: vk.Queue,
	err: Error,
) {
	index := device_get_dedicated_queue_index(self, type) or_return
	vk.GetDeviceQueue(self.ptr, index, 0, &queue)
	return
}
