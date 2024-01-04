package vk_bootstrap

// Vendor
import vk "vendor:vulkan"

// Finds the first queue which supports the desired operations.
//
// Returns `vk.QUEUE_FAMILY_IGNORED` if none is found.
get_first_queue_index :: proc(
	families: []vk.QueueFamilyProperties,
	desired_flags: vk.QueueFlags,
) -> u32 {
	index := vk.QUEUE_FAMILY_IGNORED

	for f, queue_index in families {
		if (f.queueFlags & desired_flags) == desired_flags {
			return u32(queue_index)
		}
	}

	return index
}

// Finds the queue which is separate from the graphics queue and has the desired flag and
// not the  undesired flag, but will select it if no better options are available compute
// support.
//
// Returns `vk.QUEUE_FAMILY_IGNORED` if none is found.
get_separate_queue_index :: proc(
	families: []vk.QueueFamilyProperties,
	desired_flags: vk.QueueFlags,
	undesired_flags: vk.QueueFlags,
) -> u32 {
	index := vk.QUEUE_FAMILY_IGNORED

	for f, queue_index in families {
		if (f.queueFlags & desired_flags) != desired_flags {
			continue
		}

		if .GRAPHICS in f.queueFlags {
			continue
		}

		if (f.queueFlags & undesired_flags) == {} {
			return cast(u32)queue_index
		} else {
			index = cast(u32)queue_index
		}
	}

	return index
}

// Finds the first queue which supports only the desired flag (not graphics or transfer).
//
// Returns `vk.QUEUE_FAMILY_IGNORED` if none is found.
get_dedicated_queue_index :: proc(
	families: []vk.QueueFamilyProperties,
	desired_flags: vk.QueueFlags,
	undesired_flags: vk.QueueFlags,
) -> u32 {
	for f, queue_index in families {
		if (f.queueFlags & desired_flags) != desired_flags {
			continue
		}

		if .GRAPHICS in f.queueFlags {
			continue
		}

		if (f.queueFlags & undesired_flags) != {} {
			continue
		}

		return cast(u32)queue_index
	}

	return vk.QUEUE_FAMILY_IGNORED
}

// Finds the first queue which supports presenting.
//
// Returns `vk.QUEUE_FAMILY_IGNORED` if none is found.
get_present_queue_index :: proc(
	families: []vk.QueueFamilyProperties,
	vk_physical_device: vk.PhysicalDevice,
	surface: vk.SurfaceKHR = 0,
) -> u32 {
	for _, queue_index in families {
		present_support: b32 = false

		if surface != 0 {
			if vk.GetPhysicalDeviceSurfaceSupportKHR(
				   vk_physical_device,
				   cast(u32)queue_index,
				   surface,
				   &present_support,
			   ) !=
			   .SUCCESS {
				return vk.QUEUE_FAMILY_IGNORED
			}

			if bool(present_support) {
				return cast(u32)queue_index
			}
		}
	}

	return vk.QUEUE_FAMILY_IGNORED
}
