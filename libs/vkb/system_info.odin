package vk_bootstrap

// Core
import "core:log"
import "core:runtime"

// Vendor
import vk "vendor:vulkan"

// Gathers useful information about the available vulkan capabilities, like layers and instance
// extensions. Use this for enabling features conditionally, ie if you would like an extension but
// can use a fallback if it isn't supported but need to know if support is available first.
System_Info :: struct {
	available_layers:            []vk.LayerProperties,
	available_extensions:        []vk.ExtensionProperties,
	validation_layers_available: bool,
	debug_utils_available:       bool,
}

// VK_LAYER_KHRONOS_validation
VALIDATION_LAYER_NAME :: "VK_LAYER_KHRONOS_validation"

// Get information about the available vulkan capabilities.
get_system_info :: proc() -> (info: System_Info, err: Error) {
	layer_count: u32
	if res := vk.EnumerateInstanceLayerProperties(&layer_count, nil); res != .SUCCESS {
		log.errorf("Failed to enumerate instance layer properties count: [%v]", res)
		return {}, .Instance_Layer_Error
	}

	info.available_layers = make([]vk.LayerProperties, layer_count) or_return

	if layer_count > 0 {
		if res := vk.EnumerateInstanceLayerProperties(
			&layer_count,
			raw_data(info.available_layers),
		); res != .SUCCESS {
			log.errorf("Failed to enumerate instance layer properties: [%v]", res)
			return {}, .Instance_Layer_Error
		}

		for layer, i in &info.available_layers {
			if cstring(&layer.layerName[0]) == VALIDATION_LAYER_NAME {
				info.validation_layers_available = true
				break
			}
		}
	}

	extension_count: u32 = 0
	if res := vk.EnumerateInstanceExtensionProperties(nil, &extension_count, nil);
	   res != .SUCCESS {
		log.errorf("Failed to enumerate instance extension properties: [%v]", res)
		return {}, .Instance_Extension_Error
	}

	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()

	available_extensions := make(
		[dynamic]vk.ExtensionProperties,
		extension_count,
		context.temp_allocator,
	) or_return

	if extension_count > 0 {
		if res := vk.EnumerateInstanceExtensionProperties(
			nil,
			&extension_count,
			raw_data(available_extensions),
		); res != .SUCCESS {
			log.errorf("Failed to enumerate instance extension properties: [%v]", res)
			return {}, .Instance_Extension_Error
		}

		// Check if `VK_EXT_debug_utils` extensions is available
		for ext in &available_extensions {
			if cstring(&ext.extensionName[0]) == vk.EXT_DEBUG_UTILS_EXTENSION_NAME {
				info.debug_utils_available = true
				break
			}
		}
	}

	// Check for layer extensions
	for layer in &info.available_layers {
		layer_extension_count: u32 = 0
		if res := vk.EnumerateInstanceExtensionProperties(
			cstring(&layer.layerName[0]),
			&layer_extension_count,
			nil,
		); res != .SUCCESS {
			log.errorf("Failed to enumerate layer extension properties: [%v]", res)
			return {}, .Instance_Extension_Error
		}

		if layer_extension_count == 0 do continue

		layer_extensions := make(
			[]vk.ExtensionProperties,
			layer_extension_count,
			context.temp_allocator,
		) or_return

		if res := vk.EnumerateInstanceExtensionProperties(
			cstring(&layer.layerName[0]),
			&layer_extension_count,
			raw_data(layer_extensions),
		); res != .SUCCESS {
			log.errorf("Failed to enumerate layer extension properties: [%v]", res)
			return {}, .Instance_Extension_Error
		}

		for ext in &layer_extensions {
			found := false
			for available_ext in &available_extensions {
				if cstring(&available_ext.extensionName[0]) == cstring(&ext.extensionName[0]) {
					found = true
					break
				}
			}

			if !found {
				extension_count += 1
				append(&available_extensions, ext)
			}

			if info.debug_utils_available do continue

			// Check if `VK_EXT_debug_utils` extensions is available from this layer extension
			if cstring(&ext.extensionName[0]) == vk.EXT_DEBUG_UTILS_EXTENSION_NAME {
				info.debug_utils_available = true
			}
		}
	}

	info.available_extensions = make([]vk.ExtensionProperties, extension_count) or_return
	copy(info.available_extensions[:], available_extensions[:])

	return
}

destroy_system_info :: proc(self: ^System_Info) {
	delete(self.available_layers)
	delete(self.available_extensions)
}

// Returns true if a layer is available.
is_layer_available :: proc(self: ^System_Info, layer_name: cstring) -> bool {
	if layer_name == nil do return false
	return check_layer_supported(&self.available_layers, layer_name)
}

// Returns true if an extension is available.
is_extension_available :: proc(self: ^System_Info, ext_name: cstring) -> bool {
	if ext_name == nil do return false
	return check_extension_supported(&self.available_extensions, ext_name)
}

check_layer_supported :: proc(
	available_layers: ^[]vk.LayerProperties,
	layer_name: cstring,
) -> bool {
	if layer_name == nil do return false

	for layer in available_layers {
		if (cstring(&layer.layerName[0]) == layer_name) {
			return true
		}
	}

	return false
}

check_extension_supported :: proc(
	available_extensions: ^[]vk.ExtensionProperties,
	ext_name: cstring,
) -> bool {
	if ext_name == nil do return false

	for ext in available_extensions {
		if (cstring(&ext.extensionName[0]) == ext_name) {
			return true
		}
	}

	return false
}

check_layers_supported :: proc(
	available_layers: ^[]vk.LayerProperties,
	required_layers: ^[dynamic]cstring,
) -> bool {
	all_supported := true

	for layer_name in required_layers {
		if check_layer_supported(available_layers, layer_name) do continue
		log.errorf("Required instance layer [%s] not present!", layer_name)
		all_supported = false
	}

	return all_supported
}

check_extensions_supported :: proc(
	available_extensions: ^[]vk.ExtensionProperties,
	required_extensions: ^[dynamic]cstring,
) -> bool {
	all_supported := true

	for ext_name in required_extensions {
		if check_extension_supported(available_extensions, ext_name) do continue
		log.errorf("Required instance extension [%s] not present!", ext_name)
		all_supported = false
	}

	return all_supported
}
