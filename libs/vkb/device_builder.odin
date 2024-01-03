package vk_bootstrap

// Core
import "core:log"
import "core:mem"
import "core:runtime"
import "core:slice"

// Vendor
import vk "vendor:vulkan"

Device_Builder :: struct {
	physical_device:                  ^Physical_Device,
	has_high_priority_graphics_queue: bool,
	flags:                            vk.DeviceCreateFlags,
	p_next_chain:                     [dynamic]^vk.BaseOutStructure,
	queue_descriptions:               []Custom_Queue_Description,
	allocation_callbacks:             ^vk.AllocationCallbacks,
}

// For advanced device queue setup.
Custom_Queue_Description :: struct {
	index:      u32,
	priorities: []f32,
}

init_device_builder :: proc(
	physical_device: ^Physical_Device,
) -> (
	builder: Device_Builder,
	err: Error,
) {
	builder.physical_device = physical_device
	return
}

destroy_device_builder :: proc(self: ^Device_Builder) {
	delete(self.p_next_chain)
}

// Create a `Device`. Return an error if it failed.
@(require_results)
build_device :: proc(self: ^Device_Builder) -> (device: ^Device, err: Error) {
	log.info("Requesting a logical device...")

	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()

	queue_descriptions := make([dynamic]Custom_Queue_Description, context.temp_allocator) or_return
	append(&queue_descriptions, ..self.queue_descriptions[:])

	if len(queue_descriptions) == 0 {
		if self.has_high_priority_graphics_queue {
			for f, index in self.physical_device.queue_families {
				queue_priorities := make(
					[dynamic]f32,
					f.queueCount,
					context.temp_allocator,
				) or_return

				if .GRAPHICS in f.queueFlags {
					for &priority, i in queue_priorities {
						priority = 1.0 if i == index else 0.5
					}
				} else {
					slice.fill(queue_priorities[:], 1.0)
				}

				append(
					&queue_descriptions,
					Custom_Queue_Description{u32(index), queue_priorities[:]},
				)
			}
		} else {
			for _, index in self.physical_device.queue_families {
				append(&queue_descriptions, Custom_Queue_Description{u32(index), {1.0}})
			}
		}
	}

	queue_create_infos := make([dynamic]vk.DeviceQueueCreateInfo, context.temp_allocator) or_return

	for desc in queue_descriptions {
		queue_create_info: vk.DeviceQueueCreateInfo = {
			sType            = .DEVICE_QUEUE_CREATE_INFO,
			queueFamilyIndex = desc.index,
			queueCount       = u32(len(desc.priorities)),
			pQueuePriorities = raw_data(desc.priorities),
		}

		append(&queue_create_infos, queue_create_info)
	}

	// Enable all supported device extensions
	extensions_to_enable := make(
		[dynamic]cstring,
		len(self.physical_device.extensions_to_enable),
		context.temp_allocator,
	) or_return

	append(&extensions_to_enable, ..self.physical_device.extensions_to_enable[:])

	// Extension `VK_KHR_swapchain` is required to present surface
	if self.physical_device.surface != 0 || self.physical_device.defer_surface_initialization {
		append(&extensions_to_enable, vk.KHR_SWAPCHAIN_EXTENSION_NAME)
	}

	final_pnext_chain := make([dynamic]^vk.BaseOutStructure, context.temp_allocator) or_return
	device_create_info: vk.DeviceCreateInfo

	user_defined_phys_dev_features_2 := false
	for &next in self.p_next_chain {
		if next.sType == .PHYSICAL_DEVICE_FEATURES_2 {
			user_defined_phys_dev_features_2 = true
			break
		}
	}

	if user_defined_phys_dev_features_2 && len(self.physical_device.extended_features_chain) > 0 {
		log.error(
			"Vulkan physical device features 2 in pNext chain while using add required extension features",
		)
		return nil, .Physical_Device_Features2_In_P_Next_Chain_With_Add_Required_Extension_Features
	}

	local_features2 := vk.PhysicalDeviceFeatures2 {
		sType = .PHYSICAL_DEVICE_FEATURES_2,
	}

	if !user_defined_phys_dev_features_2 {
		if self.physical_device.instance_version > vk.API_VERSION_1_1 ||
		   self.physical_device.properties2_ext_enabled {
			local_features2.features = self.physical_device.features
			append(&final_pnext_chain, cast(^vk.BaseOutStructure)&local_features2)

			for &features_node in self.physical_device.extended_features_chain {
				append(&final_pnext_chain, cast(^vk.BaseOutStructure)&features_node.p_next)
			}
		} else {
			// Only set device_create_info.pEnabledFeatures when the pNext chain does not contain a
			// vk.PhysicalDeviceFeatures2 structure
			device_create_info.pEnabledFeatures = &self.physical_device.features
		}
	}

	for &pnext in self.p_next_chain {
		append(&final_pnext_chain, pnext)
	}

	setup_p_next_chain(&device_create_info, &final_pnext_chain)

	when ODIN_DEBUG {
		for node in final_pnext_chain {
			assert(node.sType != .APPLICATION_INFO)
		}
	}

	device_create_info.sType = .DEVICE_CREATE_INFO
	device_create_info.flags = self.flags
	device_create_info.queueCreateInfoCount = u32(len(queue_create_infos))
	device_create_info.pQueueCreateInfos = raw_data(queue_create_infos[:])
	device_create_info.enabledExtensionCount = u32(len(extensions_to_enable))
	device_create_info.ppEnabledExtensionNames = raw_data(extensions_to_enable[:])

	alloc_err: mem.Allocator_Error
	device, alloc_err = new(Device)
	if alloc_err != nil {
		log.errorf("Failed to allocate a device object: [%v]", alloc_err)
		return nil, alloc_err
	}
	defer if err != nil {
		free(device);device = nil
	}

	if res := vk.CreateDevice(
		self.physical_device.ptr,
		&device_create_info,
		self.allocation_callbacks,
		&device.ptr,
	); res != .SUCCESS {
		log.fatalf("Failed to create logical device: [%v]", res)
		return device, .Failed_Create_Device
	}

	device.physical_device = self.physical_device
	device.surface = self.physical_device.surface

	device.queue_families = make(
		[]vk.QueueFamilyProperties,
		len(self.physical_device.queue_families),
	) or_return
	copy(device.queue_families[:], self.physical_device.queue_families[:])

	device.allocation_callbacks = self.allocation_callbacks
	device.instance_version = self.physical_device.instance_version

	return
}

// When no custom queue description is given, use this option to make graphics queue the
// priority from others queue.
device_builder_graphics_queue_has_priority :: proc(self: ^Device_Builder, priority: bool = true) {
	self.has_high_priority_graphics_queue = priority
}

// For Advanced Users: specify the exact list of `vk.DeviceQueueCreateInfo`'s needed for the
// application. If a custom queue setup is provided, getting the queues and queue indexes
// is up to the application.
device_builder_custom_queue_setup :: proc(
	self: ^Device_Builder,
	queue_descriptions: []Custom_Queue_Description,
) {
	self.queue_descriptions = queue_descriptions
}

// Add a structure to the pNext chain of `vk.DeviceCreateInfo`.
// The structure must be valid when `device_builder_build()` is called.
device_builder_add_p_next :: proc(self: ^Device_Builder, structure: ^$T) {
	append(&self.p_next_chain, cast(^vk.BaseOutStructure)structure)
}

// Provide custom allocation callbacks.
device_builder_set_allocation_callbacks :: proc(
	self: ^Device_Builder,
	callbacks: ^vk.AllocationCallbacks,
) {
	self.allocation_callbacks = callbacks
}
