package vk_guide

// Core
import "core:math"

import la "core:math/linalg"

// Vendor
import vk "vendor:vulkan"

// Local packages
import im "libs:imgui"
import im_vk "libs:imgui/backends/vulkan"

engine_get_current_frame :: #force_inline proc(self: ^Engine) -> ^Frame_Data #no_bounds_check {
    return &self.frames[self.frame_number % FRAME_OVERLAP]
}

// Draw background.
@(require_results)
engine_draw_background :: proc(self: ^Engine, cmd: vk.CommandBuffer) -> (ok: bool) {
    effect := &self.background_effects[self.current_background_effect]

    // Bind the compute pipeline
    vk.CmdBindPipeline(cmd, .COMPUTE, effect.pipeline)

    // Bind the descriptor set containing the draw image
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

    // Push constants
    vk.CmdPushConstants(
        cmd,
        self.gradient_pipeline_layout,
        {.COMPUTE},
        0,
        size_of(Compute_Push_Constants),
        &effect.data,
    )

    // Dispatch the compute shader
    vk.CmdDispatch(
        cmd,
        u32(math.ceil_f32(f32(self.draw_extent.width) / 16.0)),
        u32(math.ceil_f32(f32(self.draw_extent.height) / 16.0)),
        1,
    )

    return true
}

engine_draw_imgui :: proc(
    self: ^Engine,
    cmd: vk.CommandBuffer,
    target_view: vk.ImageView,
) -> (
    ok: bool,
) {
    color_attachment := attachment_info(target_view, nil, .COLOR_ATTACHMENT_OPTIMAL)
    render_info := rendering_info(self.swapchain_extent, &color_attachment, nil)

    vk.CmdBeginRendering(cmd, &render_info)

    im_vk.RenderDrawData(im.GetDrawData(), cmd)

    vk.CmdEndRendering(cmd)

    return
}

engine_draw_geometry :: proc(self: ^Engine, cmd: vk.CommandBuffer) -> (ok: bool) {
    // Begin a render pass connected to our draw image
    color_attachment := attachment_info(
        self.draw_image.image_view, nil, .COLOR_ATTACHMENT_OPTIMAL)

    depth_attachment := depth_attachment_info(
        self.depth_image.image_view,
        .DEPTH_ATTACHMENT_OPTIMAL,
    )

    render_info := rendering_info(self.draw_extent, &color_attachment, &depth_attachment)
    vk.CmdBeginRendering(cmd, &render_info)

    // Draw rectangle
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

    // Create view matrix - place camera at positive Z looking at origin
    view := la.matrix4_translate_f32({0, 0, -3})

    // Create infinite perspective projection matrix with REVERSED depth
    projection := matrix4_perspective_reverse_z_f32(
        f32(la.to_radians(70.0)),
        f32(self.draw_extent.width) / f32(self.draw_extent.height),
        0.1,
        true, // Invert the Y direction to match OpenGL and glTF axis conventions
    )

    // Draw monkey (using the same mesh pipeline already bound)
    push_constants := GPU_Draw_Push_Constants {
        // world_matrix  = la.MATRIX4F32_IDENTITY,
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
    vk.CmdBindIndexBuffer(
        cmd, self.test_meshes[2].mesh_buffers.index_buffer.buffer, 0, .UINT32)

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

// Draw loop.
@(require_results)
engine_draw :: proc(self: ^Engine) -> (ok: bool) {
    // Steps:
    //
    // 1. Waits for the GPU to finish the previous frame
    // 2. Acquires the next swapchain image
    // 3. Records rendering commands into a command buffer
    // 4. Submits the command buffer to the GPU for execution
    // 5. Presents the rendered image to the screen

    frame := engine_get_current_frame(self)

    // Wait until the gpu has finished rendering the last frame. Timeout of 1 second
    vk_check(vk.WaitForFences(self.vk_device, 1, &frame.render_fence, true, 1e9)) or_return
    vk_check(vk.ResetFences(self.vk_device, 1, &frame.render_fence)) or_return

    deletion_queue_flush(&frame.deletion_queue)

    // Request image from the swapchain
    swapchain_image_index: u32 = ---
    result := vk.AcquireNextImageKHR(
        self.vk_device,
        self.vk_swapchain,
        1e9,
        frame.swapchain_semaphore,
        0,
        &swapchain_image_index,
    )

    // Just ignore these errors.
    if result != .ERROR_OUT_OF_DATE_KHR && result != .SUBOPTIMAL_KHR {
        vk_check(result) or_return
    }

    // The the current command buffer, naming it cmd for shorter writing
    cmd := frame.main_command_buffer

    // Now that we are sure that the commands finished executing, we can safely
    // reset the command buffer to begin recording again.
    vk_check(vk.ResetCommandBuffer(cmd, {})) or_return

    // Begin the command buffer recording. We will use this command buffer exactly
    // once, so we want to let vulkan know that
    cmd_begin_info := command_buffer_begin_info({.ONE_TIME_SUBMIT})

    self.draw_extent = {
        width  = u32(
            f32(min(self.swapchain_extent.width,
                self.draw_image.image_extent.width)) * self.render_scale,
        ),
        height = u32(
            f32(min(self.swapchain_extent.height,
                self.draw_image.image_extent.height)) * self.render_scale,
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
    transition_image(
        cmd,
        self.draw_image.image,
        .COLOR_ATTACHMENT_OPTIMAL,
        .TRANSFER_SRC_OPTIMAL)
    transition_image(
        cmd,
        self.swapchain_images[swapchain_image_index],
        .UNDEFINED,
        .TRANSFER_DST_OPTIMAL,
    )

    // ExecEte a copy from the draw image into the swapchain
    copy_image_to_image(
        cmd,
        self.draw_image.image,
        self.swapchain_images[swapchain_image_index],
        self.draw_extent,
        self.swapchain_extent,
    )

    // Set swapchain image layout to Attachment Optimal so we can draw it
    transition_image(
        cmd,
        self.swapchain_images[swapchain_image_index],
        .TRANSFER_DST_OPTIMAL,
        .COLOR_ATTACHMENT_OPTIMAL,
    )

    // Draw imgui into the swapchain image
    engine_draw_imgui(self, cmd, self.swapchain_image_views[swapchain_image_index])

    // Set swapchain image layout to Present so we can show it on the screen
    transition_image(
        cmd,
        self.swapchain_images[swapchain_image_index],
        .COLOR_ATTACHMENT_OPTIMAL,
        .PRESENT_SRC_KHR,
    )

    // Finalize the command buffer (we can no longer add commands, but it can now be executed)
    vk_check(vk.EndCommandBuffer(cmd)) or_return

    // Prepare the submission to the queue. we want to wait on the
    // `swapchain_semaphore`, as that semaphore is signaled when the swapchain is
    // ready. We will signal the `ready_for_present_semaphore`, to signal that
    // rendering has finished.

    ready_for_present_semaphore := self.swapchain_image_semaphores[swapchain_image_index]

    cmd_info := command_buffer_submit_info(cmd)
    signal_info := semaphore_submit_info({.ALL_GRAPHICS}, ready_for_present_semaphore)
    wait_info := semaphore_submit_info({.COLOR_ATTACHMENT_OUTPUT_KHR}, frame.swapchain_semaphore)

    submit := submit_info(&cmd_info, &signal_info, &wait_info)

    // Submit command buffer to the queue and execute it. `render_fence` will now
    // block until the graphic commands finish execution.
    vk_check(vk.QueueSubmit2(self.graphics_queue, 1, &submit, frame.render_fence)) or_return

    // Prepare present
    //
    // This will put the image we just rendered to into the visible window. we want to wait on
    // the `ready_for_present_semaphore` for that, as its necessary that drawing commands
    // have finished before the image is displayed to the user.
    present_info := vk.PresentInfoKHR {
        sType              = .PRESENT_INFO_KHR,
        pSwapchains        = &self.vk_swapchain,
        swapchainCount     = 1,
        pWaitSemaphores    = &ready_for_present_semaphore,
        waitSemaphoreCount = 1,
        pImageIndices      = &swapchain_image_index,
    }

    result = vk.QueuePresentKHR(self.graphics_queue, &present_info)

    if result == .ERROR_OUT_OF_DATE_KHR || result == .SUBOPTIMAL_KHR {
        engine_resize_swapchain(self) or_return
    } else {
        vk_check(result) or_return
    }

    // Increase the number of frames drawn
    self.frame_number += 1

    return true
}

