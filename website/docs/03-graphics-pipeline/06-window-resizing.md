---
sidebar_position: 6
sidebar_label: "Window Resizing"
---

# Window Resizing

In vulkan, we have to handle window resizing ourselves. As part of chapter 0 we already had the
code for minimization, but resizing the window is a lot more involved.

When the window resizes, the swapchain becomes invalid, and the vulkan operations with the
swapchain like `vk..AcquireNextImageKHR` and `vk..QueuePresentKHR` can fail with a
`ERROR_OUT_OF_DATE_KHR` error. We must handle those correctly, and make sure that we can
re-create the swapchain with a new size.

For efficiency, we will not be reallocating the draw image. Right now we only have one draw
image and depth image, but on a more developed engine it could be significantly more, and
re-creating all that can be a considerable hassle. Instead, we create the draw and depth image
at startup with a preset size, and then draw into a section of it if the window is small, or
scale it up if the window is bigger. As we arent reallocating but just rendering into a corner,
we can also use this same logic to perform dynamic resolution, which is a useful way of scaling
performance, and can be handy for debugging. We are copying the rendering from the draw image
into the swapchain with `vk..CmdBlit`, and that one performs scaling so it will work well here.
This sort of scaling is not the highest quality, as normally you would want to perform some
more complicated logic for the upscaling like applying some sharpening, or doing fake
antialiasing as part of that scaling. The Imgui UI will still render into the swapchain image
directly, so it will always render at native resolution.

Lets begin by enabling the resizable flag when creating the window. Then we can see what
happens if we try to resize.

GLFW by default allows us to resize the window, handling the OS part of resizing. Run the
engine and try to resize the window.

It should give an error on the `vk_check` procedure we have on either `vk.AcquireNextImageKHR`
or `vk.QueuePresentKHR`. The error will be `ERROR_OUT_OF_DATE_KHR`. So to handle the resize, we
need to stop the rendering if we see that error, and rebuild the swapchain when that happens.

On the `engine_draw()` procedure, replace the call to `vk.AcquireNextImageKHR` to check the
error code.

```odin
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
```

If .`ERROR_OUT_OF_DATE_KHR` is returned, we call `engine_resize_swapchain` to recreate the
swapchain with updated window dimensions. This ensures the rendering system remains in sync
with the current display configuration.

Also replace the call to `vk.QueuePresentKHR` at the end in the same way.

```odin
if result := vk.QueuePresentKHR(self.graphics_queue, &present_info);
    result == .ERROR_OUT_OF_DATE_KHR {
    engine_resize_swapchain(self) or_return
}
```

Lets add a `engine_resize_swapchain()` procedure to re-create the swapchain.

```odin
engine_resize_swapchain :: proc(self: ^Engine) -> (ok: bool) {
    vk_check(vk.DeviceWaitIdle(self.vk_device)) or_return

    width, height := glfw.GetFramebufferSize(self.window)
    self.window_extent = {u32(width), u32(height)}

    engine_create_swapchain(self, self.window_extent.width, self.window_extent.height) or_return

    return true
}
```

To resize the swapchain, we first begin by waiting until the GPU has finished all rendering
commands. We dont want to change the images and views while the gpu is still handling them.
Then we query the window size from GLFW and create it again.

Lets also change `engine_create_swapchain` to set the old swapchain before create a new one.
When recreating a swapchain in Vulkan and setting the `oldSwapchain` parameter, you're telling
the system to handle the transition from the old to the new swapchain more efficiently. This is
especially helpful when the window is resized or the surface properties change.

```odin
engine_create_swapchain :: proc(self: ^Engine, width, height: u32) -> (ok: bool) {
    vkb.swapchain_builder_add_image_usage_flags(&builder, {.TRANSFER_DST})

    // Other code above ---

    // If an existing swapchain is present,link it as the old swapchain
    if self.vkb.swapchain != nil {
        vkb.swapchain_builder_set_old_swapchain(&builder, self.vkb.swapchain)
    }

    // Build the new swapchain using the configured builder
    swapchain := vkb.build_swapchain(&builder) or_return

    // If there was an old swapchain, destroy it after the new one is created
    if self.vkb.swapchain != nil {
        engine_destroy_swapchain(self)
    }

    // Update engine state with new swapchain
    self.vkb.swapchain = swapchain
    self.vk_swapchain = swapchain.handle
    self.swapchain_extent = swapchain.extent

    // Retrieve and store the swapchain’s images and image views
    self.swapchain_images = vkb.swapchain_get_images(self.vkb.swapchain) or_return
    self.swapchain_image_views = vkb.swapchain_get_image_views(self.vkb.swapchain) or_return

    return true
}
```

Since we are using `vkb`, the `oldSwapchain` parameter is set by calling
`vkb.swapchain_builder_set_old_swapchain`.

Now we have the resizing implemented so try it. You should be able to resize the image down
without running into errors. But if you make the window bigger, it will fail. We are going past
the size of our draw-image and its try to render out of bounds. We can fix that by implementing
a _drawExtent variable and making sure that it gets maxed at the size of the draw image.

Add `render_scale` float to `Engine` structure that we will use for dynamic resolution.

```odin
draw_extent:  vk.Extent2D,
// Other code above ---
render_scale: f32,
```

Set the `render_scale` default value to `1.0` in the `engine_init` procedure.

```odin
engine_init :: proc(self: ^Engine) -> (ok: bool) {
    ensure(self != nil, "Invalid 'Engine' object")

    // Store the current logger for later use inside callbacks
    g_logger = context.logger

    self.window_extent = DEFAULT_WINDOW_EXTENT
    self.render_scale = 1.0 // < here

    // Other code ---
}
```

Back to the `engine_draw()` procedure, we calculate the draw extent at the start of it, instead
of using the draw image extent for it.

```odin
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
```

Now we are going to add a slider to imgui to control this draw scale parameter.

In the `engine_run()` procedure, inside the imgui window that calculates background parameters,
add this to the top

```odin
if im.begin("Background", nil, {.Always_Auto_Resize}) {
    im.slider_float("Render scale", &self.render_scale, 0.3, 1.0)

    // Other code bellow ---
}
```

This will give us a render scale editable slider, that will go from `0.3` to `1.0`. We dont
want to go past `1` because it will break the resolution.

Run it, and try to resize the window and play with the render scale. You will see that now you
can maximize or move around the window and change its resolution dynamically.

We are setting up the draw image a bit small, but if you want, try to increase the size of the
draw image from the place its created in `engine_init_swapchain()`. Set the `drawImageExtent`
to your monitor resolution instead of the `window_extent`, which is hardcoded to a small size.

```odin
engine_init_swapchain :: proc(self: ^Engine) -> (ok: bool) {
    engine_create_swapchain(self, self.window_extent.width, self.window_extent.height) or_return

    monitor := glfw.GetPrimaryMonitor()
    mode := glfw.GetVideoMode(monitor)

    // Draw image size will match the monitor resolution
    draw_image_extent := vk.Extent3D {
        width  = u32(mode.width),
        height = u32(mode.height),
        depth  = 1,
    }

    // Other code ---

    return true
}
```

With this we have chapter 3 done, and can move forward to the next chapter.
