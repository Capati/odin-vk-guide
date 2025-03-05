package vk_guide

// Core
import "base:runtime"
import "core:mem"

// Vendor
import vk "vendor:vulkan"

// Libraries
import "libs:vma"

Deletion_Queue :: struct {
	device:             vk.Device,
	vma_allocator:      vma.Allocator,

	// Dynamic arrays for different Vulkan handle types
	buffers:            [dynamic]vk.Buffer,
	semaphores:         [dynamic]vk.Semaphore,
	fences:             [dynamic]vk.Fence,
	images:             [dynamic]vk.Image,
	image_allocations:  [dynamic]vma.Allocation,
	image_views:        [dynamic]vk.ImageView,
	device_memory:      [dynamic]vk.DeviceMemory,
	samplers:           [dynamic]vk.Sampler,
	pipelines:          [dynamic]vk.Pipeline,
	pipeline_layouts:   [dynamic]vk.PipelineLayout,
	descriptor_layouts: [dynamic]vk.DescriptorSetLayout,
	descriptor_pools:   [dynamic]vk.DescriptorPool,
	framebuffers:       [dynamic]vk.Framebuffer,
	render_passes:      [dynamic]vk.RenderPass,
	command_pools:      [dynamic]vk.CommandPool,

	// Other types
	c_procedures:       [dynamic]proc "c" (),

	// Internal
	allocator:          mem.Allocator,
}

create_deletion_queue :: proc(
	device: vk.Device,
	vma_allocator: vma.Allocator,
) -> (
	queue: ^Deletion_Queue,
) {
	assert(device != nil, "Invalid 'Device'")
	assert(vma_allocator != nil, "Invalid 'Allocator'")

	default_allocator := runtime.default_allocator()

	queue = new_clone(
		Deletion_Queue {
			device = device,
			vma_allocator = vma_allocator,
			allocator = default_allocator,
		},
		default_allocator,
	)
	ensure(queue != nil, "Failed to allocate 'Deletion_Queue'")

	// Initialize dynamic arrays
	queue.buffers = make([dynamic]vk.Buffer, default_allocator)
	queue.semaphores = make([dynamic]vk.Semaphore, default_allocator)
	queue.fences = make([dynamic]vk.Fence, default_allocator)
	queue.images = make([dynamic]vk.Image, default_allocator)
	queue.image_allocations = make([dynamic]vma.Allocation, default_allocator)
	queue.image_views = make([dynamic]vk.ImageView, default_allocator)
	queue.device_memory = make([dynamic]vk.DeviceMemory, default_allocator)
	queue.samplers = make([dynamic]vk.Sampler, default_allocator)
	queue.pipelines = make([dynamic]vk.Pipeline, default_allocator)
	queue.pipeline_layouts = make([dynamic]vk.PipelineLayout, default_allocator)
	queue.descriptor_layouts = make([dynamic]vk.DescriptorSetLayout, default_allocator)
	queue.descriptor_pools = make([dynamic]vk.DescriptorPool, default_allocator)
	queue.framebuffers = make([dynamic]vk.Framebuffer, default_allocator)
	queue.render_passes = make([dynamic]vk.RenderPass, default_allocator)
	queue.command_pools = make([dynamic]vk.CommandPool, default_allocator)
	queue.c_procedures = make([dynamic]proc "c" (), default_allocator)

	return
}

deletion_queue_destroy :: proc(queue: ^Deletion_Queue) {
	assert(queue != nil)

	context.allocator = queue.allocator

	// Flush any remaining resources
	deletion_queue_flush(queue)

	// Free dynamic arrays
	delete(queue.buffers)
	delete(queue.semaphores)
	delete(queue.fences)
	delete(queue.images)
	delete(queue.image_allocations)
	delete(queue.image_views)
	delete(queue.device_memory)
	delete(queue.samplers)
	delete(queue.pipelines)
	delete(queue.pipeline_layouts)
	delete(queue.descriptor_layouts)
	delete(queue.descriptor_pools)
	delete(queue.framebuffers)
	delete(queue.render_passes)
	delete(queue.command_pools)
	delete(queue.c_procedures)

	free(queue)
}

deletion_queue_push_buffer :: #force_inline proc(queue: ^Deletion_Queue, buffer: vk.Buffer) {
	append(&queue.buffers, buffer)
}

deletion_queue_push_semaphore :: #force_inline proc(
	queue: ^Deletion_Queue,
	semaphore: vk.Semaphore,
) {
	append(&queue.semaphores, semaphore)
}

deletion_queue_push_fence :: #force_inline proc(queue: ^Deletion_Queue, fence: vk.Fence) {
	append(&queue.fences, fence)
}

deletion_queue_push_image :: #force_inline proc(
	queue: ^Deletion_Queue,
	image: vk.Image,
	allocation: vma.Allocation,
) {
	append(&queue.images, image)
	append(&queue.image_allocations, allocation)
}

deletion_queue_push_image_view :: #force_inline proc(queue: ^Deletion_Queue, view: vk.ImageView) {
	append(&queue.image_views, view)
}

deletion_queue_push_device_memory :: #force_inline proc(
	queue: ^Deletion_Queue,
	memory: vk.DeviceMemory,
) {
	append(&queue.device_memory, memory)
}

deletion_queue_push_sampler :: #force_inline proc(queue: ^Deletion_Queue, sampler: vk.Sampler) {
	append(&queue.samplers, sampler)
}

deletion_queue_push_pipeline :: #force_inline proc(queue: ^Deletion_Queue, pipeline: vk.Pipeline) {
	append(&queue.pipelines, pipeline)
}

deletion_queue_push_pipeline_layout :: #force_inline proc(
	queue: ^Deletion_Queue,
	layout: vk.PipelineLayout,
) {
	append(&queue.pipeline_layouts, layout)
}

deletion_queue_push_descriptor_layout :: #force_inline proc(
	queue: ^Deletion_Queue,
	layout: vk.DescriptorSetLayout,
) {
	append(&queue.descriptor_layouts, layout)
}

deletion_queue_push_descriptor_pool :: #force_inline proc(
	queue: ^Deletion_Queue,
	pool: vk.DescriptorPool,
) {
	append(&queue.descriptor_pools, pool)
}

deletion_queue_push_framebuffer :: #force_inline proc(
	queue: ^Deletion_Queue,
	framebuffer: vk.Framebuffer,
) {
	append(&queue.framebuffers, framebuffer)
}

deletion_queue_push_render_pass :: #force_inline proc(
	queue: ^Deletion_Queue,
	render_pass: vk.RenderPass,
) {
	append(&queue.render_passes, render_pass)
}

deletion_queue_push_command_pool :: #force_inline proc(
	queue: ^Deletion_Queue,
	command_pool: vk.CommandPool,
) {
	append(&queue.command_pools, command_pool)
}

deletion_queue_push_c_procedure :: #force_inline proc(
	queue: ^Deletion_Queue,
	procedure: proc "c" (),
) {
	append(&queue.c_procedures, procedure)
}

deletion_queue_push :: proc {
	deletion_queue_push_buffer,
	deletion_queue_push_semaphore,
	deletion_queue_push_fence,
	deletion_queue_push_image,
	deletion_queue_push_image_view,
	deletion_queue_push_device_memory,
	deletion_queue_push_sampler,
	deletion_queue_push_pipeline,
	deletion_queue_push_pipeline_layout,
	deletion_queue_push_descriptor_layout,
	deletion_queue_push_descriptor_pool,
	deletion_queue_push_framebuffer,
	deletion_queue_push_render_pass,
	deletion_queue_push_command_pool,
	deletion_queue_push_c_procedure,
}

deletion_queue_flush :: proc(queue: ^Deletion_Queue) {
	assert(queue != nil)

	for c_procedure in queue.c_procedures {
		c_procedure()
	}
	clear(&queue.c_procedures)

	// Delete in reverse order of typical Vulkan resource creation

	// Command pools should be destroyed last
	for pool in queue.command_pools {
		vk.DestroyCommandPool(queue.device, pool, nil)
	}
	clear(&queue.command_pools)

	// Framebuffers depend on image views
	for fb in queue.framebuffers {
		vk.DestroyFramebuffer(queue.device, fb, nil)
	}
	clear(&queue.framebuffers)

	// Pipelines depend on pipeline layouts
	for pipeline in queue.pipelines {
		vk.DestroyPipeline(queue.device, pipeline, nil)
	}
	clear(&queue.pipelines)

	// Pipeline layouts depend on descriptor set layouts
	for layout in queue.pipeline_layouts {
		vk.DestroyPipelineLayout(queue.device, layout, nil)
	}
	clear(&queue.pipeline_layouts)

	// Descriptor pools and layouts
	for pool in queue.descriptor_pools {
		vk.DestroyDescriptorPool(queue.device, pool, nil)
	}
	clear(&queue.descriptor_pools)

	for layout in queue.descriptor_layouts {
		vk.DestroyDescriptorSetLayout(queue.device, layout, nil)
	}
	clear(&queue.descriptor_layouts)

	// Render passes
	for render_pass in queue.render_passes {
		vk.DestroyRenderPass(queue.device, render_pass, nil)
	}
	clear(&queue.render_passes)

	// Image views depend on images
	for view in queue.image_views {
		vk.DestroyImageView(queue.device, view, nil)
	}
	clear(&queue.image_views)

	// Samplers can be destroyed independently
	for sampler in queue.samplers {
		vk.DestroySampler(queue.device, sampler, nil)
	}
	clear(&queue.samplers)

	// Images and buffers should be destroyed before their memory
	for image, i in queue.images {
		allocation := queue.image_allocations[i]
		vma.destroy_image(queue.vma_allocator, image, allocation)
	}
	clear(&queue.images)
	clear(&queue.image_allocations)

	for fence in queue.fences {
		vk.DestroyFence(queue.device, fence, nil)
	}
	clear(&queue.fences)

	for semaphore in queue.semaphores {
		vk.DestroySemaphore(queue.device, semaphore, nil)
	}
	clear(&queue.semaphores)

	for buffer in queue.buffers {
		vk.DestroyBuffer(queue.device, buffer, nil)
	}
	clear(&queue.buffers)

	// Device memory should be freed last
	for memory in queue.device_memory {
		vk.FreeMemory(queue.device, memory, nil)
	}
	clear(&queue.device_memory)
}
