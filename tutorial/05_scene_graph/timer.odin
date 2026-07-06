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
