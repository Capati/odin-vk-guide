package vk_guide

// Core
import "base:runtime"
import "core:fmt"
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

Monitor_Info :: struct {
	refresh_rate:      u32,
	frame_time_target: f64, // in seconds
}

get_primary_monitor_info :: proc() -> (info: Monitor_Info) {
	mode := glfw.GetVideoMode(glfw.GetPrimaryMonitor())
	info = Monitor_Info {
		refresh_rate      = u32(mode.refresh_rate),
		frame_time_target = 1.0 / f64(mode.refresh_rate),
	}
	return
}

WINDOW_TITLE_BUFFER_LEN :: #config(WINDOW_TITLE_BUFFER_LEN, 256)

window_update_title_with_fps :: proc(window: glfw.WindowHandle, title: string, fps: f64) {
	buffer: [WINDOW_TITLE_BUFFER_LEN]byte
	formatted := fmt.bprintf(buffer[:], "%s - FPS = %.2f", title, fps)
	if len(formatted) >= WINDOW_TITLE_BUFFER_LEN {
		buffer[WINDOW_TITLE_BUFFER_LEN - 1] = 0 // Truncate and null-terminate
		log.warnf(
			"Window title truncated: buffer size (%d) exceeded by '%s'",
			WINDOW_TITLE_BUFFER_LEN,
			formatted,
		)
	} else if len(formatted) == 0 || buffer[len(formatted) - 1] != 0 {
		buffer[len(formatted)] = 0
	}
	glfw.SetWindowTitle(window, cstring(raw_data(buffer[:])))
}

get_monitor_resolution :: proc() -> (u32, u32) {
	mode := glfw.GetVideoMode(glfw.GetPrimaryMonitor())
	ensure(mode != nil)
	return u32(mode.width), u32(mode.height)
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
