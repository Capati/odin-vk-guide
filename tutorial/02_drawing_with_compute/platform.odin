package vk_guide

// Core
import "base:runtime"
import "core:log"
import "core:strings"

// Vendor
import "vendor:glfw"

@(private = "file")
g_logger: log.Logger

glfw_error :: proc "c" (error: i32, description: cstring) {
	context = runtime.default_context()
	context.logger = g_logger
	log.errorf("GLFW Error [%d]: %s", error, description)
}

create_window :: proc(title: string, width, height: u32) -> (window: glfw.WindowHandle, ok: bool) {
	// Save current logger for use outside of Odin context
	g_logger = context.logger

	glfw.SetErrorCallback(glfw_error)

	if !glfw.Init() {
		log.error("Failed to initialize GLFW")
		return
	}

	glfw.WindowHint(glfw.CLIENT_API, glfw.NO_API)

	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
	c_title := strings.clone_to_cstring(title, context.temp_allocator)

	window = glfw.CreateWindow(i32(width), i32(height), c_title, nil, nil)
	if window == nil {
		log.error("Failed to create a Window")
		return
	}

	return window, true
}

size_callback :: proc "c" (window: glfw.WindowHandle, width, height: i32) {
}

iconify_callback :: proc "c" (window: glfw.WindowHandle, iconified: i32) {
	engine := cast(^Engine)glfw.GetWindowUserPointer(window)
	engine.stop_rendering = bool(iconified)
}

get_framebuffer_size :: proc(window: glfw.WindowHandle) -> (u32, u32) {
	width, height := glfw.GetFramebufferSize(window)
	return u32(width), u32(height)
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

destroy_window :: proc(window: glfw.WindowHandle) {
	glfw.DestroyWindow(window)
	glfw.Terminate()
}
