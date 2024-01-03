package vk_bootstrap

// Core
import "core:log"
import "core:mem"
import "core:runtime"
import "core:strings"

// Vendor
import vk "vendor:vulkan"

Instance_Builder :: struct {
	// vk.ApplicationInfo
	app_name:                     string,
	engine_name:                  string,
	application_version:          u32,
	engine_version:               u32,
	minimum_instance_version:     u32,
	required_api_version:         u32,

	// vk.InstanceCreateInfo
	layers:                       [dynamic]cstring,
	extensions:                   [dynamic]cstring,
	flags:                        vk.InstanceCreateFlags,

	// Debug callback
	debug_callback:               vk.ProcDebugUtilsMessengerCallbackEXT,
	debug_message_severity:       vk.DebugUtilsMessageSeverityFlagsEXT,
	debug_message_type:           vk.DebugUtilsMessageTypeFlagsEXT,
	debug_user_data_pointer:      rawptr,

	// Validation features
	disabled_validation_checks:   [dynamic]vk.ValidationCheckEXT,
	enabled_validation_features:  [dynamic]vk.ValidationFeatureEnableEXT,
	disabled_validation_features: [dynamic]vk.ValidationFeatureDisableEXT,

	// Custom allocator
	allocation_callbacks:         ^vk.AllocationCallbacks,

	// Switch
	request_validation_layers:    bool,
	enable_validation_layers:     bool,
	use_debug_messenger:          bool,
	headless_context:             bool,

	// System information
	info:                         System_Info,
}

_logger: log.Logger

// Create an `Instance_Builder` with some defaults.
init_instance_builder :: proc() -> (builder: Instance_Builder, err: Error) {
	_logger = context.logger

	builder.required_api_version = vk.API_VERSION_1_0
	builder.debug_callback = default_debug_callback
	builder.debug_message_severity = {.WARNING, .ERROR}
	builder.debug_message_type = {.GENERAL, .VALIDATION, .PERFORMANCE}

	// Get supported layers and extensions
	builder.info = get_system_info() or_return

	return
}

// Destroy the `Instance_Builder` and internal data.
destroy_instance_builder :: proc(self: ^Instance_Builder) {
	delete(self.layers)
	delete(self.extensions)
	delete(self.disabled_validation_checks)
	delete(self.enabled_validation_features)
	delete(self.disabled_validation_features)
	destroy_system_info(&self.info)
}

// Create a `VkInstance`. Return an error if it failed.
@(require_results)
build_instance :: proc(self: ^Instance_Builder) -> (instance: ^Instance, err: Error) {
	log.info("Building instance...")

	// Current supported instance version
	instance_version := cast(u32)vk.API_VERSION_1_0

	// Check instance version support
	if (self.minimum_instance_version > vk.API_VERSION_1_0 ||
		   self.required_api_version > vk.API_VERSION_1_0) {

		if res := vk.EnumerateInstanceVersion(&instance_version); res != .SUCCESS {
			return nil, .Vulkan_Version_Unavailable
		}

		if (instance_version < self.minimum_instance_version ||
			   (self.minimum_instance_version == 0 &&
					   instance_version < self.required_api_version)) {
			if VK_VERSION_MINOR(self.required_api_version) == 3 {
				return nil, .Vulkan_Version_1_3_Unavailable
			} else if VK_VERSION_MINOR(self.required_api_version) == 2 {
				return nil, .Vulkan_Version_1_2_Unavailable
			} else if (VK_VERSION_MINOR(self.required_api_version) == 1) {
				return nil, .Vulkan_Version_1_1_Unavailable
			} else {
				return nil, .Vulkan_Version_Unavailable
			}
		}
	}

	api_version := instance_version
	if self.required_api_version > vk.API_VERSION_1_1 {
		api_version = self.required_api_version
	}

	log.infof(
		"Selected API version: [%d.%d.%d]",
		VK_VERSION_MAJOR(api_version),
		VK_VERSION_MINOR(api_version),
		VK_VERSION_PATCH(api_version),
	)

	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()

	app_info := vk.ApplicationInfo{}
	app_info.sType = .APPLICATION_INFO
	app_info.pNext = nil
	app_info.pApplicationName =
		self.app_name != "" ? strings.clone_to_cstring(self.app_name, context.temp_allocator) : ""
	app_info.applicationVersion = self.application_version
	app_info.pEngineName =
		self.engine_name != "" \
		? strings.clone_to_cstring(self.engine_name, context.temp_allocator) \
		: ""
	app_info.engineVersion = self.engine_version
	app_info.apiVersion = api_version

	extensions := make([dynamic]cstring, context.temp_allocator) or_return
	append(&extensions, ..self.extensions[:])

	if self.use_debug_messenger && !self.info.debug_utils_available {
		log.warnf(
			"Debug messenger was enabled but the required extension [%s] is not available; disabling...",
			vk.EXT_DEBUG_UTILS_EXTENSION_NAME,
		)
	} else {
		if self.debug_callback != nil {
			log.infof("Extension [%s] enabled", vk.EXT_DEBUG_UTILS_EXTENSION_NAME)
			append(&extensions, vk.EXT_DEBUG_UTILS_EXTENSION_NAME)
		} else {
			log.warnf(
				"Debug extension [%s] is available, but no callback was set; disabling debug reporting...",
				vk.EXT_DEBUG_UTILS_EXTENSION_NAME,
			)
		}
	}

	// Note that support for the vk.KHR_GET_PHYSICAL_DEVICE_PROPERTIES_2_EXTENSION_NAME is only
	// required for Vulkan version 1.0.
	// https://vulkan.lunarg.com/doc/sdk/1.3.268.1/mac/getting_started.html
	properties2_ext_enabled :=
		api_version < vk.API_VERSION_1_1 &&
		check_extension_supported(
			&self.info.available_extensions,
			vk.KHR_GET_PHYSICAL_DEVICE_PROPERTIES_2_EXTENSION_NAME,
		)

	if (properties2_ext_enabled) {
		log.infof(
			"Enforcing required extension [%s] for Vulkan 1.0",
			vk.KHR_GET_PHYSICAL_DEVICE_PROPERTIES_2_EXTENSION_NAME,
		)
		append(&extensions, vk.KHR_GET_PHYSICAL_DEVICE_PROPERTIES_2_EXTENSION_NAME)
	}

	when ODIN_OS == .Darwin || #config(VK_KHR_portability_enumeration, false) {
		portability_enumeration_support := check_extension_supported(
			&self.info.available_extensions,
			vk.KHR_PORTABILITY_ENUMERATION_EXTENSION_NAME,
		)

		if (portability_enumeration_support) {
			log.infof("Extension [%s] enabled", vk.KHR_PORTABILITY_ENUMERATION_EXTENSION_NAME)
			extensions[vk.KHR_PORTABILITY_ENUMERATION_EXTENSION_NAME] = true
		}
	}

	// Add surface extensions
	if !self.headless_context {
		check_add_window_ext :: proc(
			extension_name: cstring,
			required_extensions: ^[dynamic]cstring,
			available_extensions: ^[]vk.ExtensionProperties,
		) -> bool {
			if check_extension_supported(available_extensions, extension_name) {
				append(required_extensions, extension_name)
				return true
			}

			log.warnf("Surface extension [%s] is not available", extension_name)

			return false
		}

		if !check_add_window_ext(
			   vk.KHR_SURFACE_EXTENSION_NAME,
			   &extensions,
			   &self.info.available_extensions,
		   ) {
			log.fatalf(
				"Required base windowing extension [%s] not present!",
				vk.KHR_SURFACE_EXTENSION_NAME,
			)
			return nil, .Windowing_Extensions_Not_Present
		}

		when ODIN_OS == .Windows {
			added_window_exts := check_add_window_ext(
				vk.KHR_WIN32_SURFACE_EXTENSION_NAME,
				&extensions,
				&self.info.available_extensions,
			)
		} else when ODIN_OS == .Linux {
			added_window_exts := check_add_window_ext(
				"VK_KHR_xcb_surface",
				&extensions,
				&self.info.available_extensions,
			)

			added_window_exts =
				check_add_window_ext(
					"VK_KHR_xlib_surface",
					&extensions,
					&self.info.available_extensions,
				) ||
				added_window_exts

			added_window_exts =
				check_add_window_ext(
					vk.KHR_WAYLAND_SURFACE_EXTENSION_NAME,
					&extensions,
					&self.info.available_extensions,
				) ||
				added_window_exts
		} else when ODIN_OS == .Darwin {
			added_window_exts := check_add_window_ext(
				vk.EXT_METAL_SURFACE_EXTENSION_NAME,
				&extensions,
				&self.info.available_extensions,
			)
		} else {
			return nil, .Windowing_Extensions_Not_Present
		}

		if !added_window_exts {
			log.fatalf("Required windowing extensions not present!")
			return nil, .Windowing_Extensions_Not_Present
		}
	}

	required_extensions_supported := check_extensions_supported(
		&self.info.available_extensions,
		&extensions,
	)

	if !required_extensions_supported {
		return nil, .Requested_Extensions_Not_Present
	}

	layers := make([dynamic]cstring, context.temp_allocator) or_return
	append(&layers, ..self.layers[:])

	if (self.enable_validation_layers ||
		   (self.request_validation_layers && self.info.validation_layers_available)) {
		log.infof("Layer [%s] enabled", VALIDATION_LAYER_NAME)
		append(&layers, VALIDATION_LAYER_NAME)
	}

	required_layers_supported := check_layers_supported(&self.info.available_layers, &layers)

	if !required_layers_supported {
		return nil, .Requested_Layers_Not_Present
	}

	p_next_chain := make([dynamic]^vk.BaseOutStructure, context.temp_allocator) or_return

	messenger_create_info := vk.DebugUtilsMessengerCreateInfoEXT{}
	if self.use_debug_messenger {
		messenger_create_info.sType = .DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT
		messenger_create_info.pNext = nil
		messenger_create_info.messageSeverity = self.debug_message_severity
		messenger_create_info.messageType = self.debug_message_type
		messenger_create_info.pfnUserCallback = self.debug_callback
		messenger_create_info.pUserData = self.debug_user_data_pointer
		append(&p_next_chain, cast(^vk.BaseOutStructure)&messenger_create_info)
	}

	features := vk.ValidationFeaturesEXT{}
	if (len(self.enabled_validation_features) != 0 || len(self.disabled_validation_features) > 0) {
		features.sType = .VALIDATION_FEATURES_EXT
		features.pNext = nil
		features.enabledValidationFeatureCount = u32(len(self.enabled_validation_features))
		features.pEnabledValidationFeatures = raw_data(self.enabled_validation_features[:])
		features.disabledValidationFeatureCount = u32(len(self.disabled_validation_features))
		features.pDisabledValidationFeatures = raw_data(self.disabled_validation_features[:])
		append(&p_next_chain, cast(^vk.BaseOutStructure)&features)
	}

	checks := vk.ValidationFlagsEXT{}
	if (len(self.disabled_validation_checks) != 0) {
		checks.sType = .VALIDATION_FLAGS_EXT
		checks.pNext = nil
		checks.disabledValidationCheckCount = u32(len(self.disabled_validation_checks))
		checks.pDisabledValidationChecks = raw_data(self.disabled_validation_checks[:])
		append(&p_next_chain, cast(^vk.BaseOutStructure)&checks)
	}

	instance_create_info := vk.InstanceCreateInfo{}
	instance_create_info.sType = .INSTANCE_CREATE_INFO
	setup_p_next_chain(&instance_create_info, &p_next_chain)
	instance_create_info.flags = self.flags
	instance_create_info.pApplicationInfo = &app_info
	instance_create_info.enabledExtensionCount = u32(len(extensions))
	instance_create_info.ppEnabledExtensionNames = raw_data(extensions)
	instance_create_info.enabledLayerCount = u32(len(layers))
	instance_create_info.ppEnabledLayerNames = raw_data(layers)

	when ODIN_OS == .Darwin || #config(VK_KHR_portability_enumeration, false) {
		if portability_enumeration_support {
			instance_create_info.flags += {.ENUMERATE_PORTABILITY_KHR}
		}
	}

	alloc_err: mem.Allocator_Error
	instance, alloc_err = new(Instance)
	if alloc_err != nil {
		log.errorf("Failed to allocate an instance object: [%v]", alloc_err)
		return nil, alloc_err
	}
	defer if err != nil {
		free(instance);instance = nil
	}

	if res := vk.CreateInstance(&instance_create_info, self.allocation_callbacks, &instance.ptr);
	   res != .SUCCESS {
		log.fatalf("Failed to create vulkan instance: %v", res)
		return instance, .Failed_Create_Instance
	}

	// Load the rest of the functions with our instance
	vk.load_proc_addresses(instance.ptr)

	if self.use_debug_messenger {
		debug_utils_create_info := vk.DebugUtilsMessengerCreateInfoEXT {
			sType           = .DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT,
			pNext           = nil,
			messageSeverity = self.debug_message_severity,
			messageType     = self.debug_message_type,
			pfnUserCallback = self.debug_callback,
			pUserData       = self.debug_user_data_pointer,
		}

		if res := vk.CreateDebugUtilsMessengerEXT(
			instance.ptr,
			&debug_utils_create_info,
			self.allocation_callbacks,
			&instance.debug_messenger,
		); res != .SUCCESS {
			log.fatalf("Failed to create debug messenger: %v", res)
			return instance, .Failed_Create_Debug_Messenger
		}
	}

	instance.headless = self.headless_context
	instance.properties2_ext_enabled = properties2_ext_enabled
	instance.allocation_callbacks = self.allocation_callbacks
	instance.instance_version = instance_version
	instance.api_version = api_version

	return
}

// Sets the name of the application. Defaults to "" if none is provided.
instance_set_app_name :: proc(self: ^Instance_Builder, app_name: string = "") {
	self.app_name = app_name
}

// Sets the name of the engine. Defaults to "" if none is provided.
instance_set_engine_name :: proc(self: ^Instance_Builder, engine_name: string = "") {
	self.engine_name = engine_name
}

// Sets the version of the application.
// Should be constructed with `vk.MAKE_VERSION`.
instance_set_app_version :: proc(self: ^Instance_Builder, app_version: u32) {
	self.application_version = app_version
}

// Sets the (`major`, `minor`, `patch`) version of the application.
instance_set_app_versioned :: proc(self: ^Instance_Builder, major, minor, patch: u32) {
	self.application_version = vk.MAKE_VERSION(major, minor, patch)
}

// Sets the version of the engine.
// Should be constructed with `vk.MAKE_VERSION`.
instance_set_engine_version :: proc(self: ^Instance_Builder, engine_version: u32) {
	self.engine_version = engine_version
}

// Sets the (`major`, `minor`, `patch`) version of the engine.
instance_set_engine_versioned :: proc(self: ^Instance_Builder, major, minor, patch: u32) {
	self.engine_version = vk.MAKE_VERSION(major, minor, patch)
}

// Require a vulkan API version. Will fail to create if this version isn't available.
// Should be constructed with `vk.MAKE_VERSION`.
instance_require_api_version :: proc(self: ^Instance_Builder, required_api_version: u32) {
	self.required_api_version = required_api_version
}

// Sets the (`major`, `minor`, `patch`) of the required api version.
instance_require_api_versioned :: proc(self: ^Instance_Builder, major, minor, patch: u32) {
	self.required_api_version = vk.MAKE_VERSION(major, minor, patch)
}

// Overrides required API version for instance creation.
// Will fail to create if this version isn't available.
// Should be constructed with `vk.MAKE_VERSION` or `vk.API_VERSION_X_X`.
instance_set_minimum_version :: proc(self: ^Instance_Builder, minimum_instance_version: u32) {
	self.minimum_instance_version = minimum_instance_version
}

// Sets the (`major`, `minor`, `patch`) of the minimum instance version.
instance_set_minimum_versioned :: proc(self: ^Instance_Builder, major, minor, patch: u32) {
	self.minimum_instance_version = vk.MAKE_VERSION(major, minor, patch)
}

// Adds a layer to be enabled.
// Will fail to create an instance if the layer isn't available.
instance_enable_layer :: proc(self: ^Instance_Builder, layer_name: cstring) {
	if layer_name == nil do return
	log.infof("Layer [%s] enabled", layer_name)
	append(&self.layers, layer_name)
}

// Adds an extension to be enabled.
// Will fail to create an instance if the extension isn't available.
instance_enable_extension :: proc(self: ^Instance_Builder, extension_name: cstring) {
	if extension_name == nil do return
	log.infof("Extension [%s] enabled", extension_name)
	append(&self.extensions, extension_name)
}

// Adds the extensions to be enabled.
// Will fail to create an instance if the extension isn't available.
instance_enable_extensions :: proc(self: ^Instance_Builder, extensions: []cstring) {
	append(&self.extensions, ..extensions)
}

// Adds the extensions to be enabled.
// Will fail to create an instance if the extension isn't available.
instance_enable_extensions_count :: proc(
	self: ^Instance_Builder,
	count: uint,
	extensions: []cstring,
) {
	if count == 0 || count > len(extensions) do return
	for i: uint = 0; i < count; i += 1 {
		append(&self.extensions, extensions[i])
	}
}

// Enables the validation layers.
// Will fail to create an instance if the validation layers aren't available.
instance_enable_validation_layers :: proc(
	self: ^Instance_Builder,
	require_validation: bool = true,
) {
	self.enable_validation_layers = require_validation
}

// Checks if the validation layers are available and loads them if they are.
instance_request_validation_layers :: proc(
	self: ^Instance_Builder,
	request_validation: bool = true,
) {
	self.request_validation_layers = request_validation
}

// Use a default debug callback that prints to standard out.
instance_use_default_debug_messenger :: proc(self: ^Instance_Builder) {
	self.use_debug_messenger = true
	self.debug_callback = default_debug_callback
}

// Provide a user defined debug callback.
instance_set_debug_callback :: proc(
	self: ^Instance_Builder,
	callback: vk.ProcDebugUtilsMessengerCallbackEXT,
) {
	self.use_debug_messenger = true
	self.debug_callback = callback
}

// Sets the void* to use in the debug messenger - only useful with a custom callback
instance_set_debug_callback_user_data_pointer :: proc(
	self: ^Instance_Builder,
	user_data_pointer: rawptr,
) {
	self.debug_user_data_pointer = user_data_pointer
}

// Set what message severity is needed to trigger the callback.
instance_set_debug_messenger_severity :: proc(
	self: ^Instance_Builder,
	severity: vk.DebugUtilsMessageSeverityFlagsEXT,
) {
	self.debug_message_severity = severity
}

// Add a message severity to the list that triggers the callback.
instance_add_debug_messenger_severity :: proc(
	self: ^Instance_Builder,
	severity: vk.DebugUtilsMessageSeverityFlagsEXT,
) {
	self.debug_message_severity += severity
}

// Set what message type triggers the callback.
instance_set_debug_messenger_type :: proc(
	self: ^Instance_Builder,
	type: vk.DebugUtilsMessageTypeFlagsEXT,
) {
	self.debug_message_type = type
}

// Add a message type to the list of that triggers the callback.
instance_add_debug_messenger_type :: proc(
	self: ^Instance_Builder,
	type: vk.DebugUtilsMessageTypeFlagsEXT,
) {
	self.debug_message_type += type
}

// Headless mode does not load the required extensions for presentation. Defaults to true.
instance_set_headless :: proc(self: ^Instance_Builder, headless: bool = true) {
	self.headless_context = headless
}

// Disable some validation checks.
instance_add_validation_disable :: proc(self: ^Instance_Builder, check: vk.ValidationCheckEXT) {
	append(&self.disabled_validation_checks, check)
}

// Enables optional parts of the validation layers.
instance_add_validation_feature_enable :: proc(
	self: ^Instance_Builder,
	enable: vk.ValidationFeatureEnableEXT,
) {
	append(&self.enabled_validation_features, enable)
}

// Disables sections of the validation layers.
instance_add_validation_feature_disable :: proc(
	self: ^Instance_Builder,
	disable: vk.ValidationFeatureDisableEXT,
) {
	append(&self.disabled_validation_features, disable)
}

// Provide custom allocation callbacks.
instance_set_allocation_callbacks :: proc(
	self: ^Instance_Builder,
	callbacks: ^vk.AllocationCallbacks,
) {
	self.allocation_callbacks = callbacks
}

// Default debug messenger.
// Feel free to copy-paste it into your own code, change it as needed, then call
//  `instance_set_debug_callback()` to use that instead.
default_debug_callback :: proc "system" (
	message_severity: vk.DebugUtilsMessageSeverityFlagsEXT,
	message_types: vk.DebugUtilsMessageTypeFlagsEXT,
	p_callback_data: ^vk.DebugUtilsMessengerCallbackDataEXT,
	p_user_data: rawptr,
) -> b32 {
	context = runtime.default_context()
	context.logger = _logger

	if message_severity == {.WARNING} {
		log.warnf("[%v]\n%s\n", message_types, p_callback_data.pMessage)
	} else if message_severity == {.ERROR} {
		log.errorf("[%v]\n%s\n", message_types, p_callback_data.pMessage)
	} else {
		log.infof("[%v]\n%s\n", message_types, p_callback_data.pMessage)
	}

	return false // Applications must return false here
}
