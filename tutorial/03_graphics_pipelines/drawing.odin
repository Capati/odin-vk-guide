package vk_guide

// Core
import "core:math"
import la "core:math/linalg"

// Vendor
import vk "vendor:vulkan"

// Libraries
import im "libs:imgui"
import im_glfw "libs:imgui/imgui_impl_glfw"
import im_vk "libs:imgui/imgui_impl_vulkan"

engine_get_current_frame :: #force_inline proc(self: ^Engine) -> ^Frame_Data #no_bounds_check {
	return &self.frames[self.frame_number % FRAME_OVERLAP]
}

engine_acquire_next_image :: proc(self: ^Engine) -> (ok: bool) {
	frame := engine_get_current_frame(self)

	// Wait until the gpu has finished rendering the last frame. Timeout of 1 second
	vk_check(vk.WaitForFences(self.vk_device, 1, &frame.render_fence, true, 1e9)) or_return

	deletion_queue_flush(&frame.deletion_queue)

	vk_check(vk.ResetFences(self.vk_device, 1, &frame.render_fence)) or_return

	// Request image from the swapchain
	if result := vk.AcquireNextImageKHR(
		self.vk_device,
		self.vk_swapchain,
		max(u64),
		frame.swapchain_semaphore,
		0,
		&frame.swapchain_image_index,
	); result == .ERROR_OUT_OF_DATE_KHR {
		engine_resize_swapchain(self) or_return
	}

	return true
}

// Draw loop.
engine_draw :: proc(self: ^Engine) -> (ok: bool) {
	frame := engine_get_current_frame(self)

	// The the current command buffer, naming it cmd for shorter writing
	cmd := engine_get_current_frame(self).main_command_buffer

	// Now that we are sure that the commands finished executing, we can safely
	// reset the command buffer to begin recording again.
	vk_check(vk.ResetCommandBuffer(cmd, {})) or_return

	// Begin the command buffer recording. We will use this command buffer exactly
	// once, so we want to let vulkan know that
	cmd_begin_info := command_buffer_begin_info({.ONE_TIME_SUBMIT})

	self.draw_extent = {
		width  = u32(
			f32(min(self.swapchain_extent.width, self.draw_image.image_extent.width)) *
			self.render_scale,
		),
		height = u32(
			f32(min(self.swapchain_extent.height, self.draw_image.image_extent.height)) *
			self.render_scale,
		),
	}

	// Start the command buffer recording
	vk_check(vk.BeginCommandBuffer(cmd, &cmd_begin_info)) or_return

	// Transition our main draw image into general layout so we can write into it
	// we will overwrite it all so we dont care about what was the older layout
	transition_image(cmd, self.draw_image.image, .UNDEFINED, .GENERAL)

	// Clear the image
	engine_draw_background(self, cmd) or_return

	transition_image(cmd, self.draw_image.image, .GENERAL, .COLOR_ATTACHMENT_OPTIMAL)
	transition_image(cmd, self.depth_image.image, .UNDEFINED, .DEPTH_ATTACHMENT_OPTIMAL)

	// Draw the triangle
	engine_draw_geometry(self, cmd) or_return

	// Transition the draw image and the swapchain image into their correct transfer layouts
	transition_image(cmd, self.draw_image.image, .COLOR_ATTACHMENT_OPTIMAL, .TRANSFER_SRC_OPTIMAL)
	transition_image(
		cmd,
		self.swapchain_images[frame.swapchain_image_index],
		.UNDEFINED,
		.TRANSFER_DST_OPTIMAL,
	)

	copy_image_to_image(
		cmd,
		self.draw_image.image,
		self.swapchain_images[frame.swapchain_image_index],
		self.draw_extent,
		self.swapchain_extent,
	)

	// Set swapchain image layout to Attachment Optimal so we can draw it
	transition_image(
		cmd,
		self.swapchain_images[frame.swapchain_image_index],
		.TRANSFER_DST_OPTIMAL,
		.COLOR_ATTACHMENT_OPTIMAL,
	)

	// Draw imgui into the swapchain image
	engine_draw_imgui(self, cmd, self.swapchain_image_views[frame.swapchain_image_index])

	// Set swapchain image layout to Present so we can show it on the screen
	transition_image(
		cmd,
		self.swapchain_images[frame.swapchain_image_index],
		.COLOR_ATTACHMENT_OPTIMAL,
		.PRESENT_SRC_KHR,
	)

	// Finalize the command buffer (we can no longer add commands, but it can now be executed)
	vk_check(vk.EndCommandBuffer(cmd)) or_return

	// Prepare the submission to the queue. we want to wait on the
	// `swapchain_semaphore`, as that semaphore is signaled when the swapchain is
	// ready we will signal the `render_semaphore`, to signal that rendering has
	// finished

	cmd_info := command_buffer_submit_info(cmd)
	signal_info := semaphore_submit_info({.ALL_GRAPHICS}, frame.render_semaphore)
	wait_info := semaphore_submit_info({.COLOR_ATTACHMENT_OUTPUT_KHR}, frame.swapchain_semaphore)

	submit := submit_info(&cmd_info, &signal_info, &wait_info)

	// Submit command buffer to the queue and execute it. _renderFence will now
	// block until the graphic commands finish execution
	vk_check(vk.QueueSubmit2(self.graphics_queue, 1, &submit, frame.render_fence)) or_return

	// Prepare present
	//
	// this will put the image we just rendered to into the visible window. we
	// want to wait on the `render_semaphore` for that, as its necessary that
	// drawing commands have finished before the image is displayed to the user
	present_info := vk.PresentInfoKHR {
		sType              = .PRESENT_INFO_KHR,
		pSwapchains        = &self.vk_swapchain,
		swapchainCount     = 1,
		pWaitSemaphores    = &frame.render_semaphore,
		waitSemaphoreCount = 1,
		pImageIndices      = &frame.swapchain_image_index,
	}

	if result := vk.QueuePresentKHR(self.graphics_queue, &present_info);
	   result == .ERROR_OUT_OF_DATE_KHR {
		engine_resize_swapchain(self) or_return
	}

	// Increase the number of frames drawn
	self.frame_number += 1

	return true
}

engine_draw_background :: proc(self: ^Engine, cmd: vk.CommandBuffer) -> (ok: bool) {
	effect := &self.background_effects[self.current_background_effect]

	// Bind the gradient drawing compute pipeline
	vk.CmdBindPipeline(cmd, .COMPUTE, effect.pipeline)

	// Bind the descriptor set containing the draw image for the compute pipeline
	vk.CmdBindDescriptorSets(
		cmd,
		.COMPUTE,
		self.gradient_pipeline_layout,
		0,
		1,
		&self.draw_image_descriptors,
		0,
		nil,
	)

	vk.CmdPushConstants(
		cmd,
		self.gradient_pipeline_layout,
		{.COMPUTE},
		0,
		size_of(Compute_Push_Constants),
		&effect.data,
	)

	// Execute the compute pipeline dispatch. We are using 16x16 workgroup size so
	// we need to divide by it
	vk.CmdDispatch(
		cmd,
		u32(math.ceil_f32(f32(self.draw_extent.width) / 16.0)),
		u32(math.ceil_f32(f32(self.draw_extent.height) / 16.0)),
		1,
	)

	return true
}

engine_ui_definition :: proc(self: ^Engine) {
	// imgui new frame
	im_glfw.new_frame()
	im_vk.new_frame()
	im.new_frame()

	if im.begin("Background", nil, {.Always_Auto_Resize}) {
		im.slider_float("Render scale", &self.render_scale, 0.3, 1.0)

		selected := &self.background_effects[self.current_background_effect]

		im.text("Selected effect: %s", selected.name)

		@(static) current_background_effect: i32
		current_background_effect = i32(self.current_background_effect)

		// If the combo is opened and an item is selected, update the current effect
		if im.begin_combo("Effect", selected.name) {
			for effect, i in self.background_effects {
				is_selected := i32(i) == current_background_effect
				if im.selectable(effect.name, is_selected) {
					current_background_effect = i32(i)
					self.current_background_effect = Compute_Effect_Kind(current_background_effect)
				}

				// Set initial focus when the currently selected item becomes visible
				if is_selected {
					im.set_item_default_focus()
				}
			}
			im.end_combo()
		}

		im.input_float4("data1", &selected.data.data1)
		im.input_float4("data2", &selected.data.data2)
		im.input_float4("data3", &selected.data.data3)
		im.input_float4("data4", &selected.data.data4)

	}
	im.end()

	//make imgui calculate internal draw structures
	im.render()
}

engine_draw_imgui :: proc(
	self: ^Engine,
	cmd: vk.CommandBuffer,
	target_view: vk.ImageView,
) -> (
	ok: bool,
) {
	if data := im.get_draw_data(); data != nil {
		color_attachment := attachment_info(target_view, nil, .GENERAL)
		render_info := rendering_info(self.swapchain_extent, &color_attachment, nil)

		vk.CmdBeginRendering(cmd, &render_info)

		im_vk.render_draw_data(im.get_draw_data(), cmd)

		vk.CmdEndRendering(cmd)
	}

	return true
}

engine_draw_geometry :: proc(self: ^Engine, cmd: vk.CommandBuffer) -> (ok: bool) {
	// Begin a render pass connected to our draw image
	color_attachment := attachment_info(self.draw_image.image_view, nil, .COLOR_ATTACHMENT_OPTIMAL)
	depth_attachment := depth_attachment_info(
		self.depth_image.image_view,
		.DEPTH_ATTACHMENT_OPTIMAL,
	)

	render_info := rendering_info(self.draw_extent, &color_attachment, &depth_attachment)
	vk.CmdBeginRendering(cmd, &render_info)

	vk.CmdBindPipeline(cmd, .GRAPHICS, self.mesh_pipeline)

	// Set dynamic viewport and scissor
	viewport := vk.Viewport {
		x        = 0,
		y        = 0,
		width    = f32(self.draw_extent.width),
		height   = f32(self.draw_extent.height),
		minDepth = 0.0,
		maxDepth = 1.0,
	}

	vk.CmdSetViewport(cmd, 0, 1, &viewport)

	scissor := vk.Rect2D {
		offset = {x = 0, y = 0},
		extent = {width = self.draw_extent.width, height = self.draw_extent.height},
	}

	vk.CmdSetScissor(cmd, 0, 1, &scissor)

	matrix4_perspective_reverse_z_f32 :: proc "contextless" (
		fovy, aspect, near: f32,
		flip_y_axis := true,
	) -> (
		m: la.Matrix4f32,
	) #no_bounds_check {
		epsilon :: 0.00000095367431640625 // 2^-20 or about 10^-6
		fov_scale := 1 / math.tan(fovy * 0.5)

		m[0, 0] = fov_scale / aspect
		m[1, 1] = fov_scale

		// Set up reverse-Z configuration
		m[2, 2] = epsilon
		m[2, 3] = near * (1 - epsilon)
		m[3, 2] = -1

		// Handle Vulkan Y-flip if needed
		if flip_y_axis {
			m[1, 1] = -m[1, 1]
		}

		return
	}

	// Create view matrix - place camera at positive Z looking at origin
	view := la.matrix4_translate_f32({0, 0, -5})

	// Create infinite perspective projection matrix with REVERSED depth
	projection := matrix4_perspective_reverse_z_f32(
		f32(la.to_radians(70.0)),
		f32(self.draw_extent.width) / f32(self.draw_extent.height),
		0.1,
		true, // Invert the Y direction to match OpenGL and glTF axis conventions
	)

	// Monkey - ensure matrix order matches shader expectations
	push_constants := GPU_Draw_Push_Constants {
		world_matrix  = projection * view,
		vertex_buffer = self.test_meshes[2].mesh_buffers.vertex_buffer_address,
	}

	vk.CmdPushConstants(
		cmd,
		self.mesh_pipeline_layout,
		{.VERTEX},
		0,
		size_of(GPU_Draw_Push_Constants),
		&push_constants,
	)
	vk.CmdBindIndexBuffer(cmd, self.test_meshes[2].mesh_buffers.index_buffer.buffer, 0, .UINT32)

	vk.CmdDrawIndexed(
		cmd,
		self.test_meshes[2].surfaces[0].count,
		1,
		self.test_meshes[2].surfaces[0].start_index,
		0,
		0,
	)

	vk.CmdEndRendering(cmd)

	return true
}
