package vk_guide

// Core
import "base:runtime"
import "core:log"
import "core:strings"

// Vendor
import "vendor:glfw"

glfw_error_callback :: proc "c" (error: i32, description: cstring) {
	context = runtime.default_context()
	context.logger = g_logger
	log.errorf("GLFW [%d]: %s", error, description)
}

@(require_results)
create_window :: proc(title: string, width, height: u32) -> (window: glfw.WindowHandle, ok: bool) {
	// We initialize GLFW and create a window with it.
	ensure(bool(glfw.Init()), "Failed to initialize GLFW")

	glfw.SetErrorCallback(glfw_error_callback)

	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
	c_title := strings.clone_to_cstring(title, context.temp_allocator)

	// We specify that the window created by GLFW should not be associated with any specific
	// client API, such as OpenGL or OpenGL ES. This is particularly important when targeting
	// Vulkan.
	glfw.WindowHint(glfw.CLIENT_API, glfw.NO_API)

	window = glfw.CreateWindow(i32(width), i32(height), c_title, nil, nil)
	if window == nil {
		log.error("Failed to create a Window")
		return
	}

	return window, true
}

destroy_window :: proc(window: glfw.WindowHandle) {
	glfw.DestroyWindow(window)
	glfw.Terminate()
}

// -----------------------------------------------------------------------------
// Callbacks
// -----------------------------------------------------------------------------

callback_framebuffer_size :: proc "c" (window: glfw.WindowHandle, width, height: i32) {
	// TODO: Implement later
}

callback_window_minimize :: proc "c" (window: glfw.WindowHandle, iconified: i32) {
	// Get the engine from the window user pointer
	engine := cast(^Engine)glfw.GetWindowUserPointer(window)
	engine.stop_rendering = bool(iconified) // Flag to not draw if we are minimized
}

Monitor_Info :: struct {
	refresh_rate:      i32,
	frame_time_target: f64, // in seconds
}

get_primary_monitor_info :: proc() -> Monitor_Info {
	monitor := glfw.GetPrimaryMonitor()
	mode := glfw.GetVideoMode(monitor)

	info := Monitor_Info {
		refresh_rate      = mode.refresh_rate,
		frame_time_target = 1.0 / f64(mode.refresh_rate),
	}
	return info
}
