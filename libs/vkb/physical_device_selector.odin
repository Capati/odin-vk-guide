package vk_bootstrap

// Core
import "core:log"
import "core:mem"
import "core:runtime"
import "core:strings"

// Vendor
import vk "vendor:vulkan"

Physical_Device_Selector :: struct {
	instance_info: Instance_Info,
	criteria:      Selection_Criteria,
}

Instance_Info :: struct {
	instance:                vk.Instance,
	surface:                 vk.SurfaceKHR,
	version:                 u32,
	headless:                bool,
	properties2_ext_enabled: bool,
}

//Criteria information to select a suitable gpu.
Selection_Criteria :: struct {
	name:                             string,
	preferred_type:                   Preferred_Device_Type,
	allow_any_type:                   bool,
	require_present:                  bool,
	require_dedicated_transfer_queue: bool,
	require_dedicated_compute_queue:  bool,
	require_separate_transfer_queue:  bool,
	require_separate_compute_queue:   bool,
	required_mem_size:                vk.DeviceSize,
	required_extensions:              [dynamic]cstring,
	required_version:                 u32,
	required_features:                vk.PhysicalDeviceFeatures,
	required_features2:               vk.PhysicalDeviceFeatures2,
	extended_features_chain:          [dynamic]Generic_Feature,
	defer_surface_initialization:     bool,
	use_first_gpu_unconditionally:    bool,
	enable_portability_subset:        bool,
}

Preferred_Device_Type :: enum {
	Other,
	Integrated,
	Discrete,
	Virtual_Gpu,
	CPU,
}

// Requires a `Instance` to construct, needed to pass instance creation info.
init_physical_device_selector :: proc(
	instance: ^Instance,
) -> (
	pd_selector: Physical_Device_Selector,
	err: Error,
) {
	pd_selector = Physical_Device_Selector {
		instance_info = Instance_Info {
			instance = instance.ptr,
			surface = 0,
			version = instance.instance_version,
			headless = instance.headless,
			properties2_ext_enabled = instance.properties2_ext_enabled,
		},
		criteria = Selection_Criteria {
			preferred_type = .Discrete,
			allow_any_type = true,
			require_present = !instance.headless,
			require_dedicated_transfer_queue = false,
			require_dedicated_compute_queue = false,
			require_separate_transfer_queue = false,
			require_separate_compute_queue = false,
			required_mem_size = 0,
			required_version = instance.api_version,
			required_features = {},
			required_features2 = {},
			defer_surface_initialization = false,
			use_first_gpu_unconditionally = false,
			enable_portability_subset = true,
		},
	}

	return
}

destroy_physical_device_selector :: proc(self: ^Physical_Device_Selector) {
	delete(self.criteria.required_extensions)
	delete(self.criteria.extended_features_chain)
}

Device_Selection_Mode :: enum {
	// Return all suitable and partially suitable devices
	Partially_And_Fully_Suitable,
	// Return only physical devices which are fully suitable
	Only_Fully_Suitable,
}

// Return the first device which is suitable.
// Use the `selection` parameter to configure if partially.
@(require_results)
select_physical_device :: proc(
	self: ^Physical_Device_Selector,
	selection: Device_Selection_Mode = .Partially_And_Fully_Suitable,
) -> (
	physical_device: ^Physical_Device,
	err: Error,
) {
	log.info("Selecting a physical device...")

	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()

	selected_devices := selector_select_impl(self, selection, context.temp_allocator) or_return

	if len(selected_devices) == 0 {
		log.errorf("No suitable physical devices are found")
		return nil, .No_Physical_Devices_Found
	}

	defer if len(selected_devices) > 1 {
		for &pd, index in selected_devices {
			if index > 0 {
				destroy_physical_device(pd)
			}
		}
	}

	physical_device = selected_devices[0]

	log.infof("Selected physical device: %s", physical_device.name)

	return
}

selector_select_impl :: proc(
	self: ^Physical_Device_Selector,
	selection: Device_Selection_Mode,
	allocator: mem.Allocator,
) -> (
	physical_devices: [dynamic]^Physical_Device,
	err: Error,
) {
	physical_devices.allocator = allocator

	defer if err != nil {
		for &pd in physical_devices {
			destroy_physical_device(pd)
		}
	}

	if (self.criteria.require_present && !self.criteria.defer_surface_initialization) {
		if (self.instance_info.surface == 0) {
			log.errorf("Present is required, but no surface is provided.")
			return {}, .No_Surface_Provided
		}
	}

	// Get the VkPhysicalDevice handles on the system
	physical_device_count: u32
	if res := vk.EnumeratePhysicalDevices(
		self.instance_info.instance,
		&physical_device_count,
		nil,
	); res != .SUCCESS {
		log.errorf("Failed to enumerate physical devices count: [%v]", res)
		return {}, .Failed_Enumerate_Physical_Devices
	}

	if physical_device_count == 0 {
		log.errorf("No physical device with Vulkan support detected.")
		return {}, .No_Physical_Devices_Found
	}

	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD(ignore = allocator == context.temp_allocator)

	vk_physical_devices := make(
		[]vk.PhysicalDevice,
		physical_device_count,
		context.temp_allocator,
	) or_return

	if res := vk.EnumeratePhysicalDevices(
		self.instance_info.instance,
		&physical_device_count,
		raw_data(vk_physical_devices),
	); res != .SUCCESS {
		log.errorf("Failed to enumerate physical devices: [%v]", res)
		return physical_devices, .Failed_Enumerate_Physical_Devices
	}

	fill_out_phys_dev_with_criteria :: proc(
		self: ^Physical_Device_Selector,
		physical_device: ^Physical_Device,
	) -> (
		err: Error,
	) {
		physical_device.features = self.criteria.required_features
		portability_ext_available := false

		if self.criteria.enable_portability_subset {
			for extension in &physical_device.available_extensions {
				if cstring(&extension.extensionName[0]) == "VK_KHR_portability_subset" {
					portability_ext_available = true
					break
				}
			}
		}

		if portability_ext_available {
			append(&physical_device.extensions_to_enable, "VK_KHR_portability_subset")
		}

		append(&physical_device.extensions_to_enable, ..self.criteria.required_extensions[:])

		return
	}

	// if this option is set, always return only the first physical device found
	if self.criteria.use_first_gpu_unconditionally && physical_device_count > 0 {
		physical_device := selector_populate_device_details(
			self,
			vk_physical_devices[0],
			&self.criteria.extended_features_chain,
		) or_return
		fill_out_phys_dev_with_criteria(self, physical_device) or_return

		resize(&physical_devices, 1)
		physical_devices[0] = physical_device

		return
	}

	// Goof check for support device priority (arrange best at the top of the list)
	rate_device_priority :: proc(
		pd: ^Physical_Device,
		criteria: ^Selection_Criteria,
	) -> (
		score: int,
	) {
		// Check some application features support
		if pd.features.geometryShader do score += 250
		if pd.features.tessellationShader do score += 250
		if pd.features.multiViewport do score += 250

		// Maximum possible size of textures affects graphics quality
		score += int(pd.properties.limits.maxImageDimension2D)

		// Discrete GPUs have a significant performance advantage
		#partial switch criteria.preferred_type {
		case .Integrated:
			if pd.properties.deviceType == .INTEGRATED_GPU do score += 1000
		case .Discrete:
			if pd.properties.deviceType == .DISCRETE_GPU do score += 1000
		case .Virtual_Gpu:
			if pd.properties.deviceType == .VIRTUAL_GPU do score += 1000
		case .CPU:
			if pd.properties.deviceType == .CPU do score += 1000
		}

		return
	}

	high_score_device := 0
	fully_supported_count := 0
	partial_supported_count := 0

	// Populate their details and check their suitability
	for vk_pd in vk_physical_devices {
		pd := selector_populate_device_details(
			self,
			vk_pd,
			&self.criteria.extended_features_chain,
		) or_return
		pd.suitable = device_selector_is_device_suitable(self, pd) or_return

		if pd.suitable != .No {
			fill_out_phys_dev_with_criteria(self, pd) or_return

			score := rate_device_priority(pd, &self.criteria)

			if (score > high_score_device) {
				high_score_device = score
				// High score devices are at the beginning of the list
				inject_at(&physical_devices, 0, pd)
			} else {
				append(&physical_devices, pd)
			}

			if pd.suitable == .Yes {
				fully_supported_count += 1
			} else if pd.suitable == .Partial {
				partial_supported_count += 1
			}
		} else {
			destroy_physical_device(pd)
		}
	}

	pd_total := len(physical_devices)

	if pd_total == 0 {
		log.error("No suitable device found")
		return physical_devices, .No_Suitable_Device
	}

	if pd_total == 1 {
		return
	}

	fully_supported := make(
		[dynamic]^Physical_Device,
		fully_supported_count,
		context.temp_allocator,
	) or_return
	partial_supported := make(
		[dynamic]^Physical_Device,
		partial_supported_count,
		context.temp_allocator,
	) or_return

	// Sort into fully and partially suitable devices
	for &pd, i in physical_devices {
		if pd.suitable == .Yes {
			fully_supported[i] = pd
		} else {
			partial_supported[i] = pd
		}
	}

	clear(&physical_devices)

	// Remove the partially suitable elements if they aren't desired
	if selection == .Only_Fully_Suitable && fully_supported_count > 0 {
		resize(&physical_devices, fully_supported_count)
		copy(physical_devices[:], fully_supported[:])
		for &pd in partial_supported {
			destroy_physical_device(pd)
		}
	} else {
		total := fully_supported_count + partial_supported_count
		resize(&physical_devices, total)

		if fully_supported_count > 0 {
			copy(physical_devices[:], fully_supported[:])
		}

		if partial_supported_count > 0 {
			copy(physical_devices[fully_supported_count:], partial_supported[:])
		}
	}

	return
}

selector_populate_device_details :: proc(
	self: ^Physical_Device_Selector,
	vk_physical_device: vk.PhysicalDevice,
	src_extended_features_chain: ^[dynamic]Generic_Feature,
) -> (
	pd: ^Physical_Device,
	err: Error,
) {
	alloc_err: mem.Allocator_Error
	pd, alloc_err = new(Physical_Device)
	if alloc_err != nil {
		log.errorf("Failed to allocate a physical device object: [%v]", alloc_err)
		return nil, alloc_err
	}
	defer if err != nil {
		free(pd);pd = nil
	}

	pd.ptr = vk_physical_device
	pd.surface = self.instance_info.surface
	pd.defer_surface_initialization = self.criteria.defer_surface_initialization
	pd.instance_version = self.instance_info.version

	// Get device properties
	vk.GetPhysicalDeviceProperties(vk_physical_device, &pd.properties)

	// Set device name
	pd_name := cstring(&pd.properties.deviceName[0])
	if pd_name != nil && pd_name != "" {
		pd.name = strings.clone_from(pd.properties.deviceName[:])
	}

	// Get the device queue families
	queue_family_count: u32
	vk.GetPhysicalDeviceQueueFamilyProperties(vk_physical_device, &queue_family_count, nil)

	if queue_family_count == 0 {
		log.errorf("[%s] No queue family properties found", pd.name)
		return pd, .Queue_Family_Properties_Empty
	}

	pd.queue_families = make([]vk.QueueFamilyProperties, int(queue_family_count)) or_return

	vk.GetPhysicalDeviceQueueFamilyProperties(
		vk_physical_device,
		&queue_family_count,
		raw_data(pd.queue_families),
	)
	defer if err != nil do delete(pd.queue_families)

	// Get device features and memory properties
	vk.GetPhysicalDeviceFeatures(vk_physical_device, &pd.features)
	vk.GetPhysicalDeviceMemoryProperties(vk_physical_device, &pd.memory_properties)

	// Get supported device extensions
	property_count: u32
	if res := vk.EnumerateDeviceExtensionProperties(vk_physical_device, nil, &property_count, nil);
	   res != .SUCCESS {
		log.errorf("Failed to enumerate device extensions properties count: [%s]", res)
		return pd, .Failed_Enumerate_Physical_Device_Extensions
	}

	if property_count == 0 {
		log.errorf("[%s] No device extension properties found", pd.name)
		return pd, .Failed_Enumerate_Physical_Device_Extensions
	}

	pd.available_extensions = make([]vk.ExtensionProperties, property_count)

	if res := vk.EnumerateDeviceExtensionProperties(
		vk_physical_device,
		nil,
		&property_count,
		raw_data(pd.available_extensions),
	); res != .SUCCESS {
		log.errorf("Failed to enumerate device extensions properties: [%s]", res)
		return pd, .Failed_Enumerate_Physical_Device_Extensions
	}
	defer if err != nil do delete(pd.available_extensions)

	// Same value as the non-KHR version
	pd.features2.sType = .PHYSICAL_DEVICE_FEATURES_2
	pd.properties2_ext_enabled = self.instance_info.properties2_ext_enabled

	instance_is_1_1 := self.instance_info.version >= vk.API_VERSION_1_1

	if len(src_extended_features_chain) > 0 &&
	   (instance_is_1_1 || self.instance_info.properties2_ext_enabled) {
		// The required supported will be filled from the requested
		clear(&pd.extended_features_chain)
		append(&pd.extended_features_chain, ..src_extended_features_chain[:])

		local_features := vk.PhysicalDeviceFeatures2 {
			// KHR is same as core here
			sType = .PHYSICAL_DEVICE_FEATURES_2,
			pNext = &pd.extended_features_chain[0].p_next,
		}

		// Use KHR function if not able to use the core function
		if (instance_is_1_1) {
			vk.GetPhysicalDeviceFeatures2(vk_physical_device, &local_features)
		} else {
			vk.GetPhysicalDeviceFeatures2KHR(vk_physical_device, &local_features)
		}
	}

	return
}

device_selector_is_device_suitable :: proc(
	self: ^Physical_Device_Selector,
	pd: ^Physical_Device,
) -> (
	suitable: Physical_Device_Suitable,
	err: Error,
) {
	suitable = .Yes

	// Check if physical device name match criteria
	if self.criteria.name != "" && self.criteria.name != pd.name {
		log.warnf("[%s] is not the required [%s], ignoring...", pd.name, self.criteria.name)
		return .No, nil
	}

	if self.criteria.required_version > pd.properties.apiVersion {
		log.warnf(
			"[%s] does not support required instance version [%u], ignoring...",
			pd.name,
			self.criteria.required_version,
		)
		return .No, nil
	}

	dedicated_compute :=
		get_dedicated_queue_index(pd.queue_families, {.COMPUTE}, {.TRANSFER}) !=
		vk.QUEUE_FAMILY_IGNORED

	dedicated_transfer :=
		get_dedicated_queue_index(pd.queue_families, {.TRANSFER}, {.COMPUTE}) !=
		vk.QUEUE_FAMILY_IGNORED

	separate_compute :=
		get_separate_queue_index(pd.queue_families, {.COMPUTE}, {.TRANSFER}) !=
		vk.QUEUE_FAMILY_IGNORED

	separate_transfer :=
		get_separate_queue_index(pd.queue_families, {.TRANSFER}, {.COMPUTE}) !=
		vk.QUEUE_FAMILY_IGNORED

	present_queue :=
		get_present_queue_index(pd.queue_families, pd.ptr, self.instance_info.surface) !=
		vk.QUEUE_FAMILY_IGNORED

	if self.criteria.require_dedicated_compute_queue && !dedicated_compute {
		log.warnf("[%s] does not support dedicated compute queue, ignoring...", pd.name)
		return .No, nil
	}

	if self.criteria.require_dedicated_transfer_queue && !dedicated_transfer {
		log.warnf("[%s] does not support transfer compute queue, ignoring...", pd.name)
		return .No, nil
	}

	if self.criteria.require_separate_compute_queue && !separate_compute {
		log.warnf("[%s] does not support separate compute queue, ignoring...", pd.name)
		return .No, nil
	}

	if self.criteria.require_separate_transfer_queue && !separate_transfer {
		log.warnf("[%s] does not support separate transfer queue, ignoring...", pd.name)
		return .No, nil
	}

	if self.criteria.require_present &&
	   !present_queue &&
	   !self.criteria.defer_surface_initialization {
		log.warnf("[%s] has no present queue, ignoring...", pd.name)
		return .No, nil
	}

	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()

	if !check_device_extension_support(
		&pd.available_extensions,
		self.criteria.required_extensions[:],
	) {
		log.warnf("[%s] is missing required extensions, ignoring...", pd.name)
		return .No, nil
	}

	if !self.criteria.defer_surface_initialization && self.criteria.require_present {
		// Supported formats
		format_count: u32
		if res := vk.GetPhysicalDeviceSurfaceFormatsKHR(
			pd.ptr,
			self.instance_info.surface,
			&format_count,
			nil,
		); res != .SUCCESS {
			log.errorf(
				"Failed to get physical device [%s] surface formats: [%v], ignoring...",
				pd.name,
				res,
			)
			return .No, nil
		}

		if format_count == 0 do return .No, nil

		// Supported present modes
		present_mode_count: u32
		if res := vk.GetPhysicalDeviceSurfacePresentModesKHR(
			pd.ptr,
			self.instance_info.surface,
			&present_mode_count,
			nil,
		); res != .SUCCESS {
			log.errorf(
				"Failed to get physical device [%s] surface present modes: [%v], ignoring...",
				pd.name,
				res,
			)
			return .No, nil
		}

		if present_mode_count == 0 {
			log.warnf("[%s] has no present modes, ignoring...", pd.name)
			return .No, nil
		}
	}

	if !self.criteria.allow_any_type &&
	   pd.properties.deviceType != cast(vk.PhysicalDeviceType)self.criteria.preferred_type {
		log.warnf(
			"[%s] is not of preferred type: [%v], mark as 'Partial'",
			pd.name,
			self.criteria.preferred_type,
		)
		suitable = .Partial
	}

	if !check_device_features_support(
		pd.features,
		self.criteria.required_features,
		&pd.extended_features_chain,
		&self.criteria.extended_features_chain,
	) {
		log.warnf("[%s] is missing required features support, ignoring...", pd.name)
		return .No, nil
	}

	// Check required memory size
	for i: u32 = 0; i < pd.memory_properties.memoryHeapCount; i += 1 {
		if .DEVICE_LOCAL in pd.memory_properties.memoryHeaps[i].flags {
			if pd.memory_properties.memoryHeaps[i].size < self.criteria.required_mem_size {
				log.warnf(
					"[%s] does not have required [%v] memory, ignoring...",
					pd.name,
					self.criteria.required_mem_size,
				)
				return .No, nil
			}
		}
	}

	return suitable, nil
}

// Set the surface in which the physical device should render to.
// Be sure to set it if swapchain functionality is to be used.
selector_set_surface :: proc(self: ^Physical_Device_Selector, surface: vk.SurfaceKHR) {
	self.instance_info.surface = surface
}

// Set the name of the device to select.
selector_set_name :: proc(self: ^Physical_Device_Selector, name: string) {
	self.criteria.name = name
}

// Set the desired physical device type to select. Defaults to `PreferredDeviceType.Discrete`.
selector_prefer_gpu_device_type :: proc(
	self: ^Physical_Device_Selector,
	type: Preferred_Device_Type = .Discrete,
) {
	self.criteria.preferred_type = type
}

// Allow selection of a gpu device type that isn't the preferred physical device type.
// Defaults to true.
selector_allow_any_gpu_device_type :: proc(
	self: ^Physical_Device_Selector,
	allow_any_type: bool = true,
) {
	self.criteria.allow_any_type = allow_any_type
}

// Require that a physical device supports presentation. Defaults to true.
selector_require_present :: proc(self: ^Physical_Device_Selector, required: bool = true) {
	self.criteria.require_present = required
}

// Require a queue family that supports compute operations but not graphics nor transfer.
selector_require_dedicated_compute_queue :: proc(self: ^Physical_Device_Selector) {
	self.criteria.require_dedicated_compute_queue = true
}

// Require a queue family that supports transfer operations but not graphics nor compute.
selector_require_dedicated_transfer_queue :: proc(self: ^Physical_Device_Selector) {
	self.criteria.require_dedicated_transfer_queue = true
}

// Require a queue family that supports compute operations but not graphics.
selector_require_separate_compute_queue :: proc(self: ^Physical_Device_Selector) {
	self.criteria.require_separate_compute_queue = true
}

// Require a queue family that supports transfer operations but not graphics.
selector_require_separate_transfer_queue :: proc(self: ^Physical_Device_Selector) {
	self.criteria.require_separate_transfer_queue = true
}

// Require a memory heap from VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT with `size` memory available.
selector_required_device_memory_size :: proc(
	self: ^Physical_Device_Selector,
	size: vk.DeviceSize,
) {
	self.criteria.required_mem_size = size
}

// Require a physical device which supports a specific extension.
selector_add_required_extension :: proc(self: ^Physical_Device_Selector, extension: cstring) {
	append(&self.criteria.required_extensions, extension)
}

// Require a physical device which supports a set of extensions.
selector_add_required_extensions :: proc(self: ^Physical_Device_Selector, extensions: ^[]cstring) {
	for ext in extensions {
		append(&self.criteria.required_extensions, ext)
	}
}

// Require a physical device which supports a set of extensions by count.
selector_add_required_extensions_count :: proc(
	self: ^Physical_Device_Selector,
	count: uint,
	extensions: ^[]cstring,
) {
	if count == 0 || count > len(extensions) do return
	for i: uint = 0; i < count; i += 1 {
		append(&self.criteria.required_extensions, extensions[i])
	}
}

// Require a physical device that supports a `major` and `minor` version of vulkan.
// Should be constructed with `vk.MAKE_VERSION` or `vk.API_VERSION_X_X`.
selector_set_minimum_version :: proc(self: ^Physical_Device_Selector, version: u32) {
	major := version >> 22 & 0xFF
	minor := version >> 12 & 0xFF
	self.criteria.required_version = vk.MAKE_VERSION(major, minor, 0)
}

// By default PhysicalDeviceSelector enables the portability subset if available
// This function disables that behavior
selector_disable_portability_subset :: proc(self: ^Physical_Device_Selector) {
	self.criteria.enable_portability_subset = false
}

// Require a physical device which supports the features in `vk.PhysicalDeviceFeatures`.
selector_set_required_features :: proc(
	self: ^Physical_Device_Selector,
	features: vk.PhysicalDeviceFeatures,
) {
	self.criteria.required_features = features
}

// Require a physical device which supports a specific set of general/extension features.
// If this function is used, the user should not put their own `vk.PhysicalDeviceFeatures2` in
// the `pNext` chain of `vk.DeviceCreateInfo`.
selector_add_required_extension_features :: proc(self: ^Physical_Device_Selector, feature: $T) {
	feature := feature
	generic := create_generic_features(&feature)
	append(&self.criteria.extended_features_chain, generic)
}

// Require a physical device which supports the features in VkPhysicalDeviceVulkan11Features.
// Must have vulkan version 1.2 - This is due to the VkPhysicalDeviceVulkan11Features struct being added in 1.2, not 1.1
selector_set_required_features_11 :: proc(
	self: ^Physical_Device_Selector,
	features_11: vk.PhysicalDeviceVulkan11Features,
) {
	features_11 := features_11
	features_11.sType = .PHYSICAL_DEVICE_VULKAN_1_1_FEATURES
	selector_add_required_extension_features(self, features_11)
}

// Require a physical device which supports the features in VkPhysicalDeviceVulkan12Features.
// Must have vulkan version 1.2
selector_set_required_features_12 :: proc(
	self: ^Physical_Device_Selector,
	features_12: vk.PhysicalDeviceVulkan12Features,
) {
	features_12 := features_12
	features_12.sType = .PHYSICAL_DEVICE_VULKAN_1_2_FEATURES
	selector_add_required_extension_features(self, features_12)
}

// Require a physical device which supports the features in VkPhysicalDeviceVulkan13Features.
// Must have vulkan version 1.3
selector_set_required_features_13 :: proc(
	self: ^Physical_Device_Selector,
	features_13: vk.PhysicalDeviceVulkan13Features,
) {
	features_13 := features_13
	features_13.sType = .PHYSICAL_DEVICE_VULKAN_1_3_FEATURES
	selector_add_required_extension_features(self, features_13)
}

// Used when surface creation happens after physical device selection.
// Warning: This disables checking if the physical device supports a given surface.
selector_defer_surface_initialization :: proc(self: ^Physical_Device_Selector) {
	self.criteria.defer_surface_initialization = true
}

// Ignore all criteria and choose the first physical device that is available.
// Only use when: The first gpu in the list may be set by global user preferences and an
// application may wish to respect it.
selector_select_first_device_unconditionally :: proc(
	self: ^Physical_Device_Selector,
	unconditionally: bool = true,
) {
	self.criteria.use_first_gpu_unconditionally = unconditionally
}

selector_check_device_extension_feature_support :: proc(
	self: ^Physical_Device_Selector,
	physical_device: ^Physical_Device,
	feature: $T,
) -> (
	supported: T,
) {
	feature := feature
	generic := create_generic_features(&feature)
	supported = T{}

	instance_is_1_1 := self.instance_info.version >= vk.API_VERSION_1_1

	local_features := vk.PhysicalDeviceFeatures2 {
		// KHR is same as core here
		sType = .PHYSICAL_DEVICE_FEATURES_2,
		pNext = &supported,
	}

	if (instance_is_1_1) {
		vk.GetPhysicalDeviceFeatures2(physical_device.ptr, &local_features)
	} else {
		vk.GetPhysicalDeviceFeatures2KHR(physical_device.ptr, &local_features)
	}

	return
}
