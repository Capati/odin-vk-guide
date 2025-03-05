package vk_guide

// Core
import "base:runtime"
import "core:log"
import "core:strings"

// Vendor
import "vendor:glfw"

@(private = "file")
g_logger: log.Logger

glfw_error_callback :: proc "c" (error: i32, description: cstring) {
	context = runtime.default_context()
	context.logger = g_logger
	log.errorf("GLFW [%d]: %s", error, description)
}

create_window :: proc(title: string, width, height: u32) -> (window: glfw.WindowHandle, ok: bool) {
	// Save current logger for use outside of Odin context
	g_logger = context.logger

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
	ensure(window != nil, "Failed to create a Window")

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
	engine := cast(^Engine)glfw.GetWindowUserPointer(window)
	engine.stop_rendering = bool(iconified) // Flag to not draw if we are minimized
}
