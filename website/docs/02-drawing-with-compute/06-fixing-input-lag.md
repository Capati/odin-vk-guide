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

```odin
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

```odin
vkb.swapchain_builder_set_present_mode(&builder, .FIFO)
vkb.swapchain_builder_set_present_mode(&builder, .IMMEDIATE)
vkb.swapchain_builder_set_present_mode(&builder, .MAILBOX)
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

FRAME_TIMES_NUMBER :: 60

// Timing and FPS calculation with a rolling average.
Timer :: struct {
    frame_time_target: f64, // Target frame time in seconds (e.g., 1/60 = 0.0166667)
    sleep_window:      f64, // Slack time for sleep (e.g., 15% of frame time)
    previous_time:     time.Tick, // Time of the last frame (in seconds)
    delta_time:        f64,

    // FPS rolling average
    frame_times:       [FRAME_TIMES_NUMBER]f64, // Array of recent frame times
    frame_idx:         u32, // Current index in frame_times
    frame_count:       u32, // Number of valid frames (up to 60)
    frame_time_accum:  f64, // Running sum of frame times

    // Periodic update tracking
    update_interval:   f64, // Interval for FPS updates (e.g., 1.0 s)
    update_timer:      f64, // Time since last update
    last_fps:          f64, // Most recent FPS value
    fps_updated:       bool, // Flag indicating if FPS should be updated
}

// Initializes a `Timer` with a target refresh rate and update interval.
//
// Inputs:
// - `refresh_rate` - Target monitor refresh rate in Hz (e.g., 60 or 120).
// - `update_interval` - How often to update FPS (in seconds, e.g., 1.0).
timer_init :: proc(t: ^Timer, refresh_rate: u32, update_interval: f64 = 1.0) {
    t.frame_time_target = 1.0 / f64(refresh_rate)
    t.sleep_window = t.frame_time_target * 0.15
    t.previous_time = time.tick_now()
    t.update_interval = update_interval
    t.delta_time = 0
    t.frame_idx = 0
    t.frame_count = 0
    t.frame_time_accum = 0.0
    t.update_timer = 0.0
    t.last_fps = 0.0
    t.fps_updated = false
}

// Advances the timer, enforcing the target frame time and updating frame times. Sets the
// update flag and calculates FPS when the update interval is reached.
timer_tick :: proc(t: ^Timer) #no_bounds_check {
    // Get the current timestamp using a high-precision timer
    current_time := time.tick_now()

    // Calculate time elapsed since last frame
    t.delta_time = time.duration_seconds(time.tick_since(t.previous_time))

    // Frame rate control: Ensures we don't run faster than target frame time
    // This helps maintain consistent frame rates across different hardware
    if t.delta_time < t.frame_time_target {
        // Calculate how much time we need to wait to hit target frame rate
        remaining_time := t.frame_time_target - t.delta_time

        // Only sleep if remaining time exceeds sleep window threshold
        // Sleep window prevents sleeping for tiny durations which can be inaccurate
        if remaining_time > t.sleep_window {
            // Calculate actual sleep time, leaving a small buffer (sleep_window)
            sleep_time := remaining_time - t.sleep_window
            // Convert to nanoseconds (multiply by 1 billion) and sleep
            time.sleep(time.Duration(sleep_time * 1e9))
            // Update current time after sleeping
            current_time = time.tick_now()
            // Recalculate delta time after sleep
            t.delta_time = time.duration_seconds(time.tick_since(t.previous_time))
        }

        // We use a busy-wait loop to precisely hit our target frame time
        // This is more CPU intensive but gives better timing precision
        for time.duration_seconds(time.tick_since(t.previous_time)) < t.frame_time_target {
            current_time = time.tick_now()
        }
    }

    // Calculate the actual time this frame took (including any waiting we did)
    actual_frame_time := time.duration_seconds(time.tick_since(t.previous_time))

    // FPS calculation using a rolling average, maintains an array of recent frame times
    if t.frame_count > 0 {
        // Subtract oldest frame time before overwriting it
        t.frame_time_accum -= t.frame_times[t.frame_idx]
    }

    // Store new frame time in circular buffer
    t.frame_times[t.frame_idx] = actual_frame_time
    // Add new frame time to our accumulator
    t.frame_time_accum += actual_frame_time
    // Move to next index, wrapping around when reaching end
    t.frame_idx = (t.frame_idx + 1) % FRAME_TIMES_NUMBER
    // Track number of frames recorded, up to maximum buffer size
    t.frame_count = min(t.frame_count + 1, FRAME_TIMES_NUMBER)

    // Track time since last FPS update
    t.update_timer += actual_frame_time
    // Check if it's time to update FPS calculation
    t.fps_updated = t.update_timer >= t.update_interval
    if t.fps_updated {
        // Calculate the current FPS based on the average frame time
        // If frame_time_accum is 0 (shouldn't happen), we avoid division by zero
        t.last_fps = t.frame_time_accum > 0 ? 1.0 / (t.frame_time_accum / f64(t.frame_count)) : 0.0
        // Subtract update interval, preserving any excess time
        t.update_timer -= t.update_interval
    }

    // Store current time as previous time for next frame
    t.previous_time = current_time
}

// Returns the delta time in seconds since the last tick.
timer_get_delta_time :: proc(t: Timer) -> f64 {
    return t.delta_time
}

// Returns whether it’s time to use the updated FPS value. Does not modify state—reflects the
// update flag set by tick.
timer_check_fps_updated :: proc(t: Timer) -> bool {
    return t.fps_updated
}

// Returns the most recent FPS value calculated by the timer.
timer_get_fps :: proc(t: Timer) -> f64 {
    return t.last_fps
}

// Returns the last actual frame time (for debugging or logging).
timer_get_frame_time :: proc(t: Timer) -> f64 #no_bounds_check {
    return t.frame_times[(t.frame_idx - 1 + FRAME_TIMES_NUMBER) % FRAME_TIMES_NUMBER]
}

// Returns the target frame time (for debugging or logging).
timer_get_frame_time_target :: proc(t: Timer) -> f64 {
    return t.frame_time_target
}

// Returns the number of frames in the rolling average.
timer_get_frame_count :: proc(t: Timer) -> u32 {
    return t.frame_count
}

// Returns the accumulated frame time in the rolling average.
timer_get_frame_time_accum :: proc(t: Timer) -> f64 {
    return t.frame_time_accum
}
```

The `Timer` tracks a target frame rate (e.g., 60 Hz) via `frame_time_target` and enforces it by
calculating the time elapsed between frames (`delta_time`) using high-precision timestamps from
`time.tick_now()`. The `timer_tick` procedure advances the timer, ensuring the frame rate
doesn’t exceed the target by introducing a sleep (for coarse adjustment) and a busy-wait loop
(for fine precision) when the frame finishes too quickly. It also maintains a rolling average
of the last 60 frame times (`frame_times`) to compute a stable FPS value (`last_fps`), updated
periodically (e.g., every `1` second) based on `update_interval`.

Before we can use the `Timer` in our engine, we need to get some information about the primary
monitor, we need to know the refresh rate and frame time target. Go bac to `platform.odin` and
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

We also need a way to update the title bar with the current FPS:

```odin title="platform.odin"
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
```

Now we can refactor `engine_run` to use the `Timer`:

```odin title="engine.odin"
engine_ui_definition :: proc(self: ^Engine) {
    im_glfw.new_frame()
    im_vk.new_frame()
    im.new_frame()

    // Other code ---

    im.render()
}

@(require_results)
engine_run :: proc(self: ^Engine) -> (ok: bool) {
    monitor_info := get_primary_monitor_info()

    t: Timer
    timer_init(&t, monitor_info.refresh_rate)

    log.info("Entering main loop...")

    for !glfw.WindowShouldClose(self.window) {
        glfw.PollEvents()

        if self.stop_rendering {
            glfw.WaitEvents()
            timer_init(&t, monitor_info.refresh_rate) // Reset timer after wait
            continue
        }

        // Advance timer and set for FPS update
        timer_tick(&t)

        engine_ui_definition(self)

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

## Acquire Image Earlier

In the current setup, input is polled before acquiring the next image. If the loop’s work
(e.g., polling and other logic) takes less time than the monitor’s refresh cycle—say, 5 ms—then
`vk.AcquireNextImageKHR` might still block for the remaining time (e.g., 11.67 ms at 60 Hz).

During this wait:

* The input data collected at the start of the frame becomes "stale."
* Any new input (e.g., a mouse movement) that occurs during the wait won’t be processed until
  the next loop iteration.
* This delay between input polling and rendering creates noticeable lag, making the application
  feel unresponsive.

Now, let’s improve this by moving image acquire code to the beginning of the loop. First,
create a new procedure called `engine_acquire_next_image` and move the relevant code from
`engine_draw` to this new procedure:

```odin title="drawing.odin"
engine_acquire_next_image :: proc(self: ^Engine) -> (ok: bool) {
    frame := engine_get_current_frame(self)

    // Wait until the gpu has finished rendering the last frame. Timeout of 1 second
    vk_check(vk.WaitForFences(self.vk_device, 1, &frame.render_fence, true, 1e9)) or_return

    deletion_queue_flush(&frame.deletion_queue)
    descriptor_growable_clear_pools(&frame.frame_descriptors)

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
```

Now, call `engine_acquire_next_image` at the beginning of the loop:

```odin title="engine.odin"
for !glfw.WindowShouldClose(self.window) {
    // highlight-next-line
    engine_acquire_next_image(self) or_return

    glfw.PollEvents()

    if self.stop_rendering {
        glfw.WaitEvents()
        timer_init(&t, monitor_info.refresh_rate) // Reset timer after wait
        continue
    }

    // Advance timer and set for FPS update
    timer_tick(&t)
```

By flipping the order, the blocking wait from `vk.AcquireNextImageKHR` (e.g., 11.67 ms) happens
before polling input. This ensures that `glfw.PollEvents()` captures the latest input state
right before rendering, rather than at the start of the frame.

## Conclusion

We refactored `engine_run` to fix input lag by pacing the loop with a `Timer`, reducing
reliance on present mode changes. Previously, unpaced timing with `FIFO` let the loop finish
early, leaving a long VSync wait with stale input. Now, by  acquiring the next image before
polling, we ensure input is captured closer to rendering time, `glfw.PollEvents()` grabs fresh
input, `timer_tick(&t)` paces the frame to match the refresh rate (e.g., 16.67 ms), and
`engine_ui_definition` uses this input before `engine_draw`. This minimizes the gap between
polling and rendering. The `Timer` is initialized with the monitor’s refresh rate, reset on
pause, and supports debug FPS updates. Optionally, switching to `MAILBOX` or `IMMEDIATE` can
further reduce latency.
