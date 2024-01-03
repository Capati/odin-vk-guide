package vk_bootstrap

// Core
import "core:dynlib"

// Vendor
import vk "vendor:vulkan"

@(private = "file")
_vulkan_lib: dynlib.Library = nil

@(init)
@(private = "file")
init_vulkan_library :: proc() {
	loaded := false

	// Load Vulkan library by platform
	when ODIN_OS == .Windows {
		_vulkan_lib, loaded = dynlib.load_library("vulkan-1.dll")
	} else when ODIN_OS == .Darwin {
		_vulkan_lib, loaded = dynlib.load_library("libvulkan.dylib", true)

		if !loaded {
			_vulkan_lib, loaded = dynlib.load_library("libvulkan.1.dylib", true)
		}

		if !loaded {
			_vulkan_lib, loaded = dynlib.load_library("libMoltenVK.dylib", true)
		}
	} else {
		_vulkan_lib, loaded = dynlib.load_library("libvulkan.so.1", true)

		if !loaded {
			_vulkan_lib, loaded = dynlib.load_library("libvulkan.so", true)
		}
	}

	if !loaded || _vulkan_lib == nil {
		panic("Failed to load Vulkan library!")
	}

	vk_get_instance_proc_addr, found := dynlib.symbol_address(_vulkan_lib, "vkGetInstanceProcAddr")

	if !found {
		panic("Failed to get instance process address!")
	}

	// load the base vulkan procedures before we start using them
	vk.load_proc_addresses_global(vk_get_instance_proc_addr)
}

@(fini)
@(private = "file")
deinit_vulkan_library :: proc() {
	dynlib.unload_library(_vulkan_lib)
}
