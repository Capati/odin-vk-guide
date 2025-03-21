package vk_guide

// Core
import "core:log"

// Vendor
import "vendor:glfw"
import vk "vendor:vulkan"

TITLE :: "0. Project Setup"
DEFAULT_WINDOW_EXTENT :: vk.Extent2D{1280, 678} // Default window size in pixels

Engine :: struct {
	// Platform
	window:         glfw.WindowHandle,
	window_extent:  vk.Extent2D,
	is_initialized: bool,
	stop_rendering: bool,
}

@(private)
g_logger: log.Logger

// Initializes everything in the engine.
@(require_results)
engine_init :: proc(self: ^Engine) -> (ok: bool) {
	ensure(self != nil, "Invalid 'Engine' object")

	// Store the current logger for later use inside callbacks
	g_logger = context.logger

	self.window_extent = DEFAULT_WINDOW_EXTENT

	// Create a window using GLFW
	self.window = create_window(
		TITLE,
		self.window_extent.width,
		self.window_extent.height,
	) or_return
	defer if !ok {
		destroy_window(self.window)
	}

	// Set the window user pointer so we can get the engine from callbacks
	glfw.SetWindowUserPointer(self.window, self)

	// Set window callbacks
	glfw.SetFramebufferSizeCallback(self.window, callback_framebuffer_size)
	glfw.SetWindowIconifyCallback(self.window, callback_window_minimize)

	// Everything went fine
	self.is_initialized = true

	return true
}

// Shuts down the engine.
engine_cleanup :: proc(self: ^Engine) {
	if !self.is_initialized {
		return
	}

	destroy_window(self.window)
}

// Draw loop.
@(require_results)
engine_draw :: proc(self: ^Engine) -> (ok: bool) {
	// Nothing yet
	return true
}

// Run main loop.
@(require_results)
engine_run :: proc(self: ^Engine) -> (ok: bool) {
	log.info("Entering main loop...")

	loop: for !glfw.WindowShouldClose(self.window) {
		glfw.PollEvents()

		// Do not draw if we are minimized
		if self.stop_rendering {
			glfw.WaitEvents() // Wait to avoid endless spinning
			continue
		}

		engine_draw(self) or_return
	}

	log.info("Exiting...")

	return true
}
