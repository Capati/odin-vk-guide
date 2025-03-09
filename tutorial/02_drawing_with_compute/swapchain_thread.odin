package vk_guide

// // Core
// import "core:log"
// import "core:sync"
// import "core:thread"

// // Vendor
// import vk "vendor:vulkan"

// Swapchain_Thread_Data :: struct {
// 	device:              vk.Device,
// 	swapchain:           vk.SwapchainKHR,
// 	swapchain_semaphore: vk.Semaphore,
// 	image_index:         u32,
// 	is_ready:            bool,
// 	is_running:          bool,
// 	thread:              ^thread.Thread,
// 	mutex:               sync.Mutex,
// 	condition:           sync.Cond,
// }

// // Initialize the swapchain thread data
// engine_init_swapchain_thread :: proc(self: ^Engine) {
// 	self.swapchain_thread = Swapchain_Thread_Data {
// 		device     = self.vk_device,
// 		swapchain  = self.vk_swapchain,
// 		is_ready   = false,
// 		is_running = false,
// 		mutex      = {},
// 		condition  = {},
// 	}
// }

// // Clean up swapchain thread resources
// engine_destroy_swapchain_thread :: proc(self: ^Engine) {
// 	engine_stop_swapchain_thread(self)
// 	// sync.condition_destroy(&self.swapchain_thread.condition)
// 	// sync.mutex_destroy(&self.swapchain_thread.mutex)
// }

// // Thread procedure for swapchain image acquisition
// swapchain_thread_proc :: proc(data: rawptr) {
// 	thread_data := (^Swapchain_Thread_Data)(data)

// 	for {
// 		sync.mutex_lock(&thread_data.mutex)

// 		// Check if we should exit
// 		if !thread_data.is_running {
// 			sync.mutex_unlock(&thread_data.mutex)
// 			break
// 		}

// 		// If the main thread hasn't consumed the previous image yet, wait
// 		if thread_data.is_ready {
// 			sync.cond_wait(&thread_data.condition, &thread_data.mutex)

// 			// Check again if we should exit after waking up
// 			if !thread_data.is_running {
// 				sync.mutex_unlock(&thread_data.mutex)
// 				break
// 			}
// 		}

// 		// Get the current frame's swapchain semaphore
// 		current_semaphore := thread_data.swapchain_semaphore

// 		sync.mutex_unlock(&thread_data.mutex)

// 		// Acquire the next image from the swapchain
// 		image_index: u32 = ---
// 		result := vk.AcquireNextImageKHR(
// 			thread_data.device,
// 			thread_data.swapchain,
// 			max(u64), // Wait indefinitely
// 			current_semaphore,
// 			0, // No fence
// 			&image_index,
// 		)

// 		// If swapchain is out of date, we'll handle it in the main thread
// 		if result != .SUCCESS && result != .SUBOPTIMAL_KHR {
// 			log.error("Failed to acquire next image:", result)
// 			continue
// 		}

// 		// Signal that the image is ready for the main thread
// 		sync.mutex_lock(&thread_data.mutex)
// 		thread_data.image_index = image_index
// 		thread_data.is_ready = true
// 		sync.cond_signal(&thread_data.condition)
// 		sync.mutex_unlock(&thread_data.mutex)
// 	}
// }

// // Start the swapchain acquisition thread
// engine_start_swapchain_thread :: proc(self: ^Engine) {
// 	sync.mutex_lock(&self.swapchain_thread.mutex)

// 	if self.swapchain_thread.is_running {
// 		sync.mutex_unlock(&self.swapchain_thread.mutex)
// 		return
// 	}

// 	// Initialize with the first frame's semaphore before starting the thread
// 	current_frame := &self.frames[self.frame_number % len(self.frames)]
// 	self.swapchain_thread.swapchain_semaphore = current_frame.swapchain_semaphore

// 	self.swapchain_thread.is_running = true
// 	sync.mutex_unlock(&self.swapchain_thread.mutex)

// 	self.swapchain_thread.thread = thread.create_and_start_with_data(
// 		&self.swapchain_thread,
// 		swapchain_thread_proc,
// 	)
// 	// thread.start(self.swapchain_thread.thread)
// }

// // Stop the swapchain acquisition thread
// engine_stop_swapchain_thread :: proc(self: ^Engine) {
// 	sync.mutex_lock(&self.swapchain_thread.mutex)

// 	if !self.swapchain_thread.is_running {
// 		sync.mutex_unlock(&self.swapchain_thread.mutex)
// 		return
// 	}

// 	self.swapchain_thread.is_running = false
// 	sync.cond_signal(&self.swapchain_thread.condition)
// 	sync.mutex_unlock(&self.swapchain_thread.mutex)

// 	if self.swapchain_thread.thread != nil {
// 		thread.join(self.swapchain_thread.thread)
// 		thread.destroy(self.swapchain_thread.thread)
// 		self.swapchain_thread.thread = nil
// 	}
// }

// engine_get_next_swapchain_image :: proc(self: ^Engine) -> (image_index: u32, ok: bool) {
// 	sync.mutex_lock(&self.swapchain_thread.mutex)

// 	// If the swapchain thread isn't running, return an error
// 	if !self.swapchain_thread.is_running {
// 		sync.mutex_unlock(&self.swapchain_thread.mutex)
// 		return 0, false
// 	}

// 	// Wait for the swapchain thread to acquire an image if not ready yet
// 	if !self.swapchain_thread.is_ready {
// 		sync.cond_wait(&self.swapchain_thread.condition, &self.swapchain_thread.mutex)

// 		// Check again if thread is still running after wait
// 		if !self.swapchain_thread.is_running {
// 			sync.mutex_unlock(&self.swapchain_thread.mutex)
// 			return 0, false
// 		}
// 	}

// 	// Get the image index and update the current frame's swapchain semaphore
// 	image_index = self.swapchain_thread.image_index
// 	self.swapchain_thread.is_ready = false

// 	// Setup for next frame
// 	next_frame := &self.frames[self.frame_number % len(self.frames)]

// 	// We need to ensure we're using a fresh, unsignaled semaphore
// 	// Option 1: Create a new semaphore each time (more expensive)
// 	if next_frame.swapchain_semaphore != 0 {
// 		vk.DestroySemaphore(self.vk_device, next_frame.swapchain_semaphore, nil)
// 	}

// 	semaphore_info := vk.SemaphoreCreateInfo {
// 		sType = .SEMAPHORE_CREATE_INFO,
// 	}

// 	result := vk.CreateSemaphore(
// 		self.vk_device,
// 		&semaphore_info,
// 		nil,
// 		&next_frame.swapchain_semaphore,
// 	)

// 	if result != .SUCCESS {
// 		log.error("Failed to create swapchain semaphore")
// 		sync.mutex_unlock(&self.swapchain_thread.mutex)
// 		return 0, false
// 	}

// 	// Assign the newly created semaphore
// 	self.swapchain_thread.swapchain_semaphore = next_frame.swapchain_semaphore

// 	// Signal the swapchain thread to acquire the next image
// 	sync.cond_signal(&self.swapchain_thread.condition)

// 	sync.mutex_unlock(&self.swapchain_thread.mutex)

// 	return image_index, true
// }
