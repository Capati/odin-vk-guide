package imgui_example_null

// This is a copy of the "null" example from ImGui
// https://github.com/ocornut/imgui/blob/docking/examples/example_null/main.cpp

import imgui "../.."

import "core:fmt"

main :: proc() {
	imgui.CHECKVERSION()
	imgui.CreateContext(nil)
	defer {
		fmt.println("DestroyContext()")
		imgui.DestroyContext(nil)
	}
	io := imgui.GetIO()

	// Build atlas
	tex_pixels: ^u8
	tex_w, tex_h: i32
	imgui.FontAtlas_GetTexDataAsRGBA32(io.Fonts, &tex_pixels, &tex_w, &tex_h, nil)

	for i in 0..<20 {
		fmt.printf("NewFrame() {}\n", i)
		io.DisplaySize = {1920, 1080}
		io.DeltaTime = 1.0 / 60.0
		imgui.NewFrame()

		@(static) f: f32
		imgui.Text("Hello, world!")
		imgui.SliderFloat("float", &f, 0, 1)
		imgui.Text("Application average %.3f ms/frame (%.1f FPS)", 1000.0 / io.Framerate, io.Framerate)
		imgui.ShowDemoWindow(nil)

		imgui.Render()
	}
}
