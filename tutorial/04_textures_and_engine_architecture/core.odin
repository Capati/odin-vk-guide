package vk_guide

// Core
import intr "base:intrinsics"
import "base:runtime"
import "core:log"
import la "core:math/linalg"

// Vendor
import vk "vendor:vulkan"

// Local libraries
import vma "libs:vma"

@(require_results)
vk_check :: #force_inline proc(
	res: vk.Result,
	message := "Detected Vulkan error",
	loc := #caller_location,
) -> bool {
	if intr.expect(res, vk.Result.SUCCESS) == .SUCCESS {
		return true
	}
	log.errorf("[Vulkan Error] %s: %v", message, res)
	runtime.print_caller_location(loc)
	return false
}

engine_immediate_submit :: proc(
	self: ^Engine,
	data: $T,
	fn: proc(engine: ^Engine, cmd: vk.CommandBuffer, data: T),
) -> (
	ok: bool,
) {
	vk_check(vk.ResetFences(self.vk_device, 1, &self.imm_fence)) or_return
	vk_check(vk.ResetCommandBuffer(self.imm_command_buffer, {})) or_return

	cmd := self.imm_command_buffer

	cmd_begin_info := command_buffer_begin_info({.ONE_TIME_SUBMIT})

	vk_check(vk.BeginCommandBuffer(cmd, &cmd_begin_info)) or_return

	fn(self, cmd, data)

	vk_check(vk.EndCommandBuffer(cmd)) or_return

	cmd_info := command_buffer_submit_info(cmd)
	submit_info := submit_info(&cmd_info, nil, nil)

	// Submit command buffer to the queue and execute it.
	//  `render_fence` will now block until the graphic commands finish execution
	vk_check(vk.QueueSubmit2(self.graphics_queue, 1, &submit_info, self.imm_fence)) or_return

	vk_check(vk.WaitForFences(self.vk_device, 1, &self.imm_fence, true, 9999999999)) or_return

	return true
}

Allocated_Buffer :: struct {
	buffer:     vk.Buffer,
	info:       vma.Allocation_Info,
	allocation: vma.Allocation,
	allocator:  vma.Allocator,
}

create_buffer :: proc(
	self: ^Engine,
	alloc_size: vk.DeviceSize,
	usage: vk.BufferUsageFlags,
	memory_usage: vma.Memory_Usage,
) -> (
	new_buffer: Allocated_Buffer,
	ok: bool,
) {
	// allocate buffer
	buffer_info := vk.BufferCreateInfo {
		sType = .BUFFER_CREATE_INFO,
		size  = alloc_size,
		usage = usage,
	}

	vma_alloc_info := vma.Allocation_Create_Info {
		usage = memory_usage,
		flags = {.Mapped},
	}

	new_buffer.allocator = self.vma_allocator

	// allocate the buffer
	vk_check(
		vma.create_buffer(
			self.vma_allocator,
			buffer_info,
			vma_alloc_info,
			&new_buffer.buffer,
			&new_buffer.allocation,
			&new_buffer.info,
		),
	) or_return

	return new_buffer, true
}

destroy_buffer :: proc(self: Allocated_Buffer) {
	vma.destroy_buffer(self.allocator, self.buffer, self.allocation)
}

Vertex :: struct {
	position: la.Vector3f32,
	uv_x:     f32,
	normal:   la.Vector3f32,
	uv_y:     f32,
	color:    la.Vector4f32,
}

// Holds the resources needed for a mesh
GPU_Mesh_Buffers :: struct {
	index_buffer:          Allocated_Buffer,
	vertex_buffer:         Allocated_Buffer,
	vertex_buffer_address: vk.DeviceAddress,
}

// Push constants for our mesh object draws
GPU_Draw_Push_Constants :: struct {
	world_matrix:  la.Matrix4f32,
	vertex_buffer: vk.DeviceAddress,
}

upload_mesh :: proc(
	self: ^Engine,
	indices: []u32,
	vertices: []Vertex,
) -> (
	new_surface: GPU_Mesh_Buffers,
	ok: bool,
) {
	vertex_buffer_size := vk.DeviceSize(len(vertices) * size_of(Vertex))
	index_buffer_size := vk.DeviceSize(len(indices) * size_of(u32))

	// Create vertex buffer
	new_surface.vertex_buffer = create_buffer(
		self,
		vertex_buffer_size,
		{.STORAGE_BUFFER, .TRANSFER_DST, .SHADER_DEVICE_ADDRESS},
		.Gpu_Only,
	) or_return
	defer if !ok {
		destroy_buffer(new_surface.vertex_buffer)
	}

	// Find the address of the vertex buffer
	device_address_info := vk.BufferDeviceAddressInfo {
		sType  = .BUFFER_DEVICE_ADDRESS_INFO,
		buffer = new_surface.vertex_buffer.buffer,
	}
	new_surface.vertex_buffer_address = vk.GetBufferDeviceAddress(
		self.vk_device,
		&device_address_info,
	)

	// Create index buffer
	new_surface.index_buffer = create_buffer(
		self,
		index_buffer_size,
		{.INDEX_BUFFER, .TRANSFER_DST},
		.Gpu_Only,
	) or_return
	defer if !ok {
		destroy_buffer(new_surface.index_buffer)
	}

	staging := create_buffer(
		self,
		vertex_buffer_size + index_buffer_size,
		{.TRANSFER_SRC},
		.Cpu_Only,
	) or_return
	defer destroy_buffer(staging)

	data := staging.info.mapped_data
	// Copy vertex buffer
	intr.mem_copy(data, raw_data(vertices), vertex_buffer_size)
	// Copy index buffer
	intr.mem_copy(
		rawptr(uintptr(data) + uintptr(vertex_buffer_size)),
		raw_data(indices),
		index_buffer_size,
	)

	// Create a struct to hold all the copy parameters
	Copy_Data :: struct {
		staging_buffer:     vk.Buffer,
		vertex_buffer:      vk.Buffer,
		index_buffer:       vk.Buffer,
		vertex_buffer_size: vk.DeviceSize,
		index_buffer_size:  vk.DeviceSize,
	}

	// Prepare the data structure
	copy_data := Copy_Data {
		staging_buffer     = staging.buffer,
		vertex_buffer      = new_surface.vertex_buffer.buffer,
		index_buffer       = new_surface.index_buffer.buffer,
		vertex_buffer_size = vertex_buffer_size,
		index_buffer_size  = index_buffer_size,
	}

	// Call the immediate submit with our data and procedure
	engine_immediate_submit(
		self,
		copy_data,
		proc(engine: ^Engine, cmd: vk.CommandBuffer, data: Copy_Data) {
			// Setup vertex buffer copy
			vertex_copy := vk.BufferCopy {
				srcOffset = 0,
				dstOffset = 0,
				size      = data.vertex_buffer_size,
			}

			// Copy vertex data from staging to the new surface vertex buffer
			vk.CmdCopyBuffer(cmd, data.staging_buffer, data.vertex_buffer, 1, &vertex_copy)

			// Setup index buffer copy
			index_copy := vk.BufferCopy {
				srcOffset = data.vertex_buffer_size,
				dstOffset = 0,
				size      = data.index_buffer_size,
			}

			// Copy index data from staging to the new surface index buffer
			vk.CmdCopyBuffer(cmd, data.staging_buffer, data.index_buffer, 1, &index_copy)
		},
	)

	return new_surface, true
}
