---
sidebar_position: 6
sidebar_label: "Fixing Input Lag"
---

# Fixing Input Lag

If you’ve integrated ImGui into our engine and noticed significant input lag when dragging an
ImGui window, you might assume `FIFO` is the sole culprit. The cursor lags behind the window’s
movement, even at a stable 60 FPS, making interactions feel sluggish. While `FIFO` contributes,
the real issue is uncontrolled frame timing. This section shows how pacing the render loop with
a Timer resolves the lag, with optional present mode tweaks for further improvement.

In our rendering loop, the sequence look like this:

```odin title="engine.odin"
engine_run() {
    // 1. Poll input events (e.g., glfw.PollEvents)
    // 2. Update and render ImGui
    // 3. Call engine_draw()
}

engine_draw() {
    // 1. Wait for the GPU to finish the previous frame (fence)
    //  - vk.AcquireNextImageKHR (waits for VSync with FIFO)
    // 2. Submit rendering commands with input data collected earlier
    // 3. Present the frame
}
```

With `FIFO`, `vk.AcquireNextImageKHR` waits for the monitor’s refresh cycle (e.g., 16.67 ms at
60 Hz) after input polling. Without frame pacing, the loop might finish early (e.g., 5 ms),
leaving a long wait (11.67 ms) before rendering, using stale input from the start of the frame.
This delay causes the lag when interacting with the application.

## Switch from FIFO

To minimize this lag, we will replace `FIFO` with `MAILBOX` or `IMMEDIATE` present mode. These
modes reduce or eliminate the VSync wait, minimizing latency.

### Choosing the Right Present Mode

* `MAILBOX`: Updates the swapchain image immediately and queues it for the next refresh. It
  avoids tearing while reducing latency compared to `FIFO`. This is often the best choice for
  smooth, responsive applications.

* `IMMEDIATE`: Presents frames as soon as they’re ready, potentially causing tearing but
  offering the lowest latency. Use this if tearing isn’t an issue for your use case.

Lets go back to `engine_create_swapchain` and add the other desired present modes:

```odin title="engine.odin"
vkb.swapchain_builder_set_desired_present_mode(&builder, .FIFO)
vkb.swapchain_builder_set_desired_present_mode(&builder, .IMMEDIATE)
vkb.swapchain_builder_set_desired_present_mode(&builder, .MAILBOX)
```

The last present mode set, in this case `MAILBOX`, will be selected if supported. If `MAILBOX`
is not available, it will fall back to `IMMEDIATE`, and if neither `MAILBOX` nor `IMMEDIATE`
are supported, it will use `FIFO`.

## Pace the Loop with a Timer

Our solution will pace the loop even on `FIFO`, but when moving away from `FIFO`, which
naturally caps your frame rate to the monitor’s refresh rate via VSync, you lose that automatic
synchronization. Without it, your application might render frames as fast as the GPU
allows—potentially hundreds or thousands of FPS—leading to unnecessary resource consumption and
heat generation. To maintain control, we implement manual FPS limiting using a custom `Timer`
struct in the loop.

This is the `timer.odin` implementation:

```odin
package vk_guide

// Core
import "core:time"

// Timing and simple FPS tracking for a paced render loop.
Timer :: struct {
    frame_time_target: f64,      // Target frame time in seconds (e.g. 1/60)
    previous_time:     time.Tick,
    delta_time:        f64,

    // FPS tracking: frames counted since the last update, over update_interval seconds.
    update_interval:   f64,
    update_timer:      f64,
    frame_counter:     u32,
    last_fps:          f64,
    fps_updated:       bool,
}

// Initializes a `Timer` with a target refresh rate and update interval.
//
// Inputs:
// 
// - `refresh_rate`    - Target monitor refresh rate in Hz (e.g. 60 or 120).
// - `update_interval` - How often to update FPS (in seconds, e.g. 1.0).
timer_init :: proc(t: ^Timer, refresh_rate: u32, update_interval: f64 = 1.0) {
    t^ = Timer{}
    t.frame_time_target = 1.0 / f64(refresh_rate)
    t.previous_time     = time.tick_now()
    t.update_interval    = update_interval
}

// Advances the timer, sleeping/spinning as needed to hit `frame_time_target`.
// Sets `fps_updated` and recomputes `last_fps` once per `update_interval`.
timer_tick :: proc(t: ^Timer) {
    t.delta_time = time.duration_seconds(time.tick_since(t.previous_time))

    if t.delta_time < t.frame_time_target {
        remaining := t.frame_time_target - t.delta_time

        // Sleep for most of the remaining time; sleeping is imprecise (OS scheduler
        // granularity), so leave ~1ms for the busy-wait below to correct for it.
        sleep_buffer :: 1e-3 // 1ms
        if remaining > sleep_buffer {
            time.sleep(time.Duration((remaining - sleep_buffer) * 1e9))
        }

        // Busy-wait to precisely hit the target frame time.
        for time.duration_seconds(time.tick_since(t.previous_time)) < t.frame_time_target {}

        t.delta_time = time.duration_seconds(time.tick_since(t.previous_time))
    }

    t.frame_counter  += 1
    t.update_timer   += t.delta_time
    t.fps_updated     = t.update_timer >= t.update_interval

    if t.fps_updated {
        t.last_fps      = f64(t.frame_counter) / t.update_timer
        t.frame_counter  = 0
        t.update_timer  -= t.update_interval // preserve excess, avoids long-term drift
    }

    t.previous_time = time.tick_now()
}

timer_get_delta_time :: proc(t: Timer) -> f64 {
    return t.delta_time
}

timer_check_fps_updated :: proc(t: Timer) -> bool {
    return t.fps_updated
}

timer_get_fps :: proc(t: Timer) -> f64 {
    return t.last_fps
}

timer_get_frame_time_target :: proc(t: Timer) -> f64 {
    return t.frame_time_target
}
```

The `Timer` tracks a target frame rate (e.g., 60 Hz) via `frame_time_target` and enforces it by
calculating the time elapsed between frames (`delta_time`) using high-precision timestamps
from `time.tick_now()`. The `timer_tick` procedure advances the timer, sleeping for most of
the remaining time and busy-waiting for the last ~1ms to precisely hit the target frame time.
FPS is computed directly from the number of frames counted since the last update divided by
the elapsed time, and is recalculated once per `update_interval`(e.g., every 1 second).

Before we can use the `Timer` in our engine, we need to get some information about the primary
monitor, we need to know the refresh rate and frame time target. Go back to `platform.odin` and
add `get_primary_monitor_info` procedure:

```odin title="platform.odin"
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
```

:::note[VK_LAYER_LUNARG_monitor]

Earlier, during instance creation, we enabled the `VK_LAYER_LUNARG_monitor` layer, which
displays FPS directly in the window's title bar. Since we're now handling FPS display
ourselves, disable this layer before continuing to avoid conflicts.

:::

We also need a way to update the title bar with the current FPS:

```odin title="platform.odin"
import "core:fmt" // import at the top

WINDOW_TITLE_BUFFER_LEN :: #config(WINDOW_TITLE_BUFFER_LEN, 256)

window_update_title_with_fps :: proc(window: glfw.WindowHandle, title: string, fps: f64) {
    buffer: [WINDOW_TITLE_BUFFER_LEN]byte
    formatted := fmt.bprintf(buffer[:], "%s - FPS = %.2f", title, fps)
    if len(formatted) >= WINDOW_TITLE_BUFFER_LEN {
        buffer[WINDOW_TITLE_BUFFER_LEN - 1] = 0 // Truncate and null-terminate
        log.warnf("Window title truncated: buffer size (%d) exceeded by '%s'",
            WINDOW_TITLE_BUFFER_LEN, formatted)
    } else if len(formatted) == 0 || buffer[len(formatted) - 1] != 0 {
        buffer[len(formatted)] = 0
    }
    glfw.SetWindowTitle(window, cstring(raw_data(buffer[:])))
}
```

Now we can refactor `engine_run` to use the `Timer`:

```odin title="engine.odin"
// diff-add-start
engine_ui_definition :: proc(self: ^Engine) {
    im_glfw.NewFrame()
    im_vk.NewFrame()
    im.NewFrame()

    // Other code ---

    im.Render()
}
// diff-add-end

@(require_results)
engine_run :: proc(self: ^Engine) -> (ok: bool) {
    // diff-add-start
    monitor_info := get_primary_monitor_info()

    t: Timer
    timer_init(&t, monitor_info.refresh_rate)
    // diff-add-end

    log.info("Entering main loop...")

    for !glfw.WindowShouldClose(self.window) {
        glfw.PollEvents()

        if self.stop_rendering {
            glfw.WaitEvents()
            timer_init(&t, monitor_info.refresh_rate) // Reset timer after wait
            continue
        }

        // diff-add-start
        // Advance timer and set for FPS update
        timer_tick(&t)
        engine_ui_definition(self)
        // diff-add-end
        engine_draw(self) or_return

        when ODIN_DEBUG {
            if timer_check_fps_updated(t) {
                window_update_title_with_fps(self.window, TITLE, timer_get_fps(t))
            }
        }
    }

    log.info("Exiting...")

    return true
}
```

First we get the primary monitor's information and initialize the timer with the monitor's
refresh rate. We then advances the timer with `timer_tick` to track elapsed time for consistent
frame updates. To update the FPS, we checks if the FPS value needs updating and simply call
`window_update_title_with_fps` to update the window title with the current FPS.

Note that ImGui logic is now in `engine_ui_definition`, which is called after `timer_tick(&t)`.
This change helps keep the main loop clean and organized.

## Conclusion

We refactored `engine_run` to fix input lag by pacing the loop with a `Timer`, reducing
reliance on present mode changes. Previously, unpaced timing with `FIFO` let the loop finish
early, leaving a long VSync wait with stale input. The `Timer` is initialized with the
monitor’s refresh rate, reset on pause, and supports debug FPS updates. Optionally, switching
to `MAILBOX` or `IMMEDIATE` can further reduce latency or replace the timer pacing.
