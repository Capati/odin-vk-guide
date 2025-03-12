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
