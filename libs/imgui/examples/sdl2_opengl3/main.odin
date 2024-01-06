package imgui_example_sdl2_opengl3

// This is an example of using the bindings with SDL2 and OpenGL 3.
// For a more complete example with comments, see:
// https://github.com/ocornut/imgui/blob/docking/examples/example_sdl2_opengl3/main.cpp

import imgui "../.."
import "../../imgui_impl_sdl2"
import "../../imgui_impl_opengl3"

import sdl "vendor:sdl2"
import gl "vendor:OpenGL"

main :: proc() {
	assert(sdl.Init(sdl.INIT_EVERYTHING) == 0)
	defer sdl.Quit()

	sdl.GL_SetAttribute(.CONTEXT_FLAGS, i32(sdl.GLcontextFlag.FORWARD_COMPATIBLE_FLAG))
	sdl.GL_SetAttribute(.CONTEXT_PROFILE_MASK, i32(sdl.GLprofile.CORE))
	sdl.GL_SetAttribute(.CONTEXT_MAJOR_VERSION, 3)
	sdl.GL_SetAttribute(.CONTEXT_MINOR_VERSION, 2)

	window := sdl.CreateWindow(
		"Dear ImGui SDL2+OpenGl3 example",
		sdl.WINDOWPOS_CENTERED,
		sdl.WINDOWPOS_CENTERED,
		1280, 720,
		{.OPENGL, .RESIZABLE, .ALLOW_HIGHDPI})
	assert(window != nil)
	defer sdl.DestroyWindow(window)

	gl_ctx := sdl.GL_CreateContext(window)
	defer sdl.GL_DeleteContext(gl_ctx)

	sdl.GL_MakeCurrent(window, gl_ctx)
	sdl.GL_SetSwapInterval(1) // vsync

	gl.load_up_to(3, 2, proc(p: rawptr, name: cstring) {
		(cast(^rawptr)p)^ = sdl.GL_GetProcAddress(name)
	})

	imgui.CHECKVERSION()
	imgui.CreateContext(nil)
	defer imgui.DestroyContext(nil)
	io := imgui.GetIO()
	io.ConfigFlags += {.NavEnableKeyboard, .NavEnableGamepad}
	when imgui.IMGUI_BRANCH == "docking" {
		io.ConfigFlags += {.DockingEnable}
		io.ConfigFlags += {.ViewportsEnable}

		style := imgui.GetStyle()
		style.WindowRounding = 0
		style.Colors[imgui.Col.WindowBg].w =1
	}

	imgui.StyleColorsDark(nil)

	imgui_impl_sdl2.InitForOpenGL(window, gl_ctx)
	defer imgui_impl_sdl2.Shutdown()
	imgui_impl_opengl3.Init(nil)
	defer imgui_impl_opengl3.Shutdown()

	running := true
	for running {
		e: sdl.Event
		for sdl.PollEvent(&e) {
			imgui_impl_sdl2.ProcessEvent(&e)

			#partial switch e.type {
			case .QUIT: running = false
			}
		}

		imgui_impl_opengl3.NewFrame()
		imgui_impl_sdl2.NewFrame()
		imgui.NewFrame()

		imgui.ShowDemoWindow(nil)

		if imgui.Begin("Window containing a quit button", nil, {}) {
			if imgui.Button("The quit button in question") {
				running = false
			}
		}
		imgui.End()

		imgui.Render()
		gl.Viewport(0, 0, i32(io.DisplaySize.x), i32(io.DisplaySize.y))
		gl.ClearColor(0, 0, 0, 1)
		gl.Clear(gl.COLOR_BUFFER_BIT)
		imgui_impl_opengl3.RenderDrawData(imgui.GetDrawData())

		when imgui.IMGUI_BRANCH == "docking" {
			backup_current_window := sdl.GL_GetCurrentWindow()
			backup_current_context := sdl.GL_GetCurrentContext()
			imgui.UpdatePlatformWindows()
			imgui.RenderPlatformWindowsDefault()
			sdl.GL_MakeCurrent(backup_current_window, backup_current_context);
		}

		sdl.GL_SwapWindow(window)
	}
}
