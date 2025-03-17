package vk_guide

// Core
import "core:mem"

// Vendor
import vk "vendor:vulkan"

// Libraries
import "libs:vma"

Resource :: union {
	// Higher-level custom resources
	Allocated_Image,

	// Cleanup procedures
	proc "c" (),

	// Pipeline objects
	vk.Pipeline,
	vk.PipelineLayout,

	// Descriptor-related objects
	vk.DescriptorPool,
	vk.DescriptorSetLayout,

	// Resource views and samplers
	vk.ImageView,
	vk.Sampler,

	// Command-related objects
	vk.CommandPool,

	// Synchronization primitives
	vk.Fence,
	vk.Semaphore,

	// Core memory resources
	vk.Buffer,
	vk.DeviceMemory,

	// Memory allocator
	vma.Allocator,
}

Deletion_Queue :: struct {
	device:    vk.Device,
	resources: [dynamic]Resource,
	allocator: mem.Allocator,
}

deletion_queue_init :: proc(
	self: ^Deletion_Queue,
	device: vk.Device,
	allocator := context.allocator,
) {
	assert(self != nil, "Invalid 'Deletion_Queue'")
	assert(device != nil, "Invalid 'Device'")

	self.allocator = allocator
	self.device = device
	self.resources = make([dynamic]Resource, self.allocator)
}

deletion_queue_destroy :: proc(self: ^Deletion_Queue) {
	assert(self != nil)

	context.allocator = self.allocator

	// Flush any remaining resources
	deletion_queue_flush(self)

	// Free dynamic array
	delete(self.resources)
}

deletion_queue_push :: proc(self: ^Deletion_Queue, resource: Resource) {
	append(&self.resources, resource)
}

// LIFO (Last-In, First-Out) deletion.
deletion_queue_flush :: proc(self: ^Deletion_Queue) {
	assert(self != nil)

	if len(self.resources) == 0 {
		return
	}

	// Process resources in reverse order (LIFO)
	#reverse for &resource in self.resources {
		switch &res in resource {
		// Higher-level custom resources
		case Allocated_Image:
			destroy_image(res)

		// Cleanup procedures
		case proc "c" ():
			res()

		// Pipeline objects
		case vk.Pipeline:
			vk.DestroyPipeline(self.device, res, nil)
		case vk.PipelineLayout:
			vk.DestroyPipelineLayout(self.device, res, nil)

		// Descriptor-related objects
		case vk.DescriptorPool:
			vk.DestroyDescriptorPool(self.device, res, nil)
		case vk.DescriptorSetLayout:
			vk.DestroyDescriptorSetLayout(self.device, res, nil)

		// Resource views and samplers
		case vk.ImageView:
			vk.DestroyImageView(self.device, res, nil)
		case vk.Sampler:
			vk.DestroySampler(self.device, res, nil)

		// Command-related objects
		case vk.CommandPool:
			vk.DestroyCommandPool(self.device, res, nil)

		// Synchronization primitives
		case vk.Fence:
			vk.DestroyFence(self.device, res, nil)
		case vk.Semaphore:
			vk.DestroySemaphore(self.device, res, nil)

		// Core memory resources
		case vk.Buffer:
			vk.DestroyBuffer(self.device, res, nil)
		case vk.DeviceMemory:
			vk.FreeMemory(self.device, res, nil)

		// Memory allocator
		case vma.Allocator:
			vma.destroy_allocator(res)
		}
	}

	// Clear the array after processing all resources
	clear(&self.resources)
}
