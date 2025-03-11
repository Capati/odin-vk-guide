package vk_guide

// Core
import "base:runtime"
import "core:mem"

// Vendor
import vk "vendor:vulkan"

// Libraries
import "libs:vma"

Image_Resource :: struct {
	image:      vk.Image,
	allocator:  vma.Allocator,
	allocation: vma.Allocation,
}

Allocated_Buffer_Resource :: struct {
	buffer:     vk.Buffer,
	allocator:  vma.Allocator,
	allocation: vma.Allocation,
}

Deletion_ProcC :: #type proc "c" ()

Resource :: union {
	vk.Buffer,
	vk.Semaphore,
	vk.Fence,
	Image_Resource,
	Allocated_Buffer_Resource,
	vk.ImageView,
	vk.DeviceMemory,
	vk.Sampler,
	vk.Pipeline,
	vk.PipelineLayout,
	vk.DescriptorSetLayout,
	vk.DescriptorPool,
	vk.Framebuffer,
	vk.RenderPass,
	vk.CommandPool,
	vma.Allocator,
	Deletion_ProcC,
}

Deletion_Queue :: struct {
	device:    vk.Device,
	resources: [dynamic]Resource,
	allocator: mem.Allocator,
}

create_deletion_queue :: proc(device: vk.Device) -> (queue: ^Deletion_Queue) {
	assert(device != nil, "Invalid 'Device'")

	default_allocator := runtime.default_allocator()

	queue = new_clone(
		Deletion_Queue{device = device, allocator = default_allocator},
		default_allocator,
	)
	ensure(queue != nil, "Failed to allocate 'Deletion_Queue'")

	// Initialize dynamic array
	queue.resources = make([dynamic]Resource, default_allocator)

	return
}

deletion_queue_destroy :: proc(queue: ^Deletion_Queue) {
	assert(queue != nil)

	context.allocator = queue.allocator

	// Flush any remaining resources
	deletion_queue_flush(queue)

	// Free dynamic array
	delete(queue.resources)

	free(queue)
}

deletion_queue_push :: proc(queue: ^Deletion_Queue, resource: Resource) {
	append(&queue.resources, resource)
}

// LIFO (Last-In, First-Out) deletion
deletion_queue_flush :: proc(queue: ^Deletion_Queue) {
	assert(queue != nil)

	if len(queue.resources) == 0 {
		return
	}

	// Process resources in reverse order (LIFO)
	#reverse for &resource in queue.resources {
		switch res in resource {
		case Deletion_ProcC:
			res()
		case vk.CommandPool:
			vk.DestroyCommandPool(queue.device, res, nil)
		case vk.Framebuffer:
			vk.DestroyFramebuffer(queue.device, res, nil)
		case vk.Pipeline:
			vk.DestroyPipeline(queue.device, res, nil)
		case vk.PipelineLayout:
			vk.DestroyPipelineLayout(queue.device, res, nil)
		case vk.DescriptorPool:
			vk.DestroyDescriptorPool(queue.device, res, nil)
		case vk.DescriptorSetLayout:
			vk.DestroyDescriptorSetLayout(queue.device, res, nil)
		case vk.RenderPass:
			vk.DestroyRenderPass(queue.device, res, nil)
		case vk.ImageView:
			vk.DestroyImageView(queue.device, res, nil)
		case vk.Sampler:
			vk.DestroySampler(queue.device, res, nil)
		case Image_Resource:
			vma.destroy_image(res.allocator, res.image, res.allocation)
		case Allocated_Buffer_Resource:
			vma.destroy_buffer(res.allocator, res.buffer, res.allocation)
		case vk.Fence:
			vk.DestroyFence(queue.device, res, nil)
		case vk.Semaphore:
			vk.DestroySemaphore(queue.device, res, nil)
		case vk.Buffer:
			vk.DestroyBuffer(queue.device, res, nil)
		case vk.DeviceMemory:
			vk.FreeMemory(queue.device, res, nil)
		case vma.Allocator:
			vma.destroy_allocator(res)
		}
	}

	// Clear the array after processing all resources
	clear(&queue.resources)
}
