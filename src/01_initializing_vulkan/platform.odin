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

destroy_window :: proc(window: glfw.WindowHandle) {
	glfw.DestroyWindow(window)
	glfw.Terminate()
}
