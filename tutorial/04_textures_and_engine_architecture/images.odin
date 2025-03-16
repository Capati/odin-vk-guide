package vk_guide

// Core
import intr "base:intrinsics"
import "core:math"

// Vendor
import vk "vendor:vulkan"

// Libraries
import "libs:vma"

transition_image :: proc(
	cmd: vk.CommandBuffer,
	image: vk.Image,
	current_layout: vk.ImageLayout,
	new_layout: vk.ImageLayout,
) {
	image_barrier := vk.ImageMemoryBarrier2 {
		sType = .IMAGE_MEMORY_BARRIER_2,
	}

	image_barrier.srcStageMask = {.ALL_COMMANDS}
	image_barrier.srcAccessMask = {.MEMORY_WRITE}
	image_barrier.dstStageMask = {.ALL_COMMANDS}
	image_barrier.dstAccessMask = {.MEMORY_WRITE, .MEMORY_READ}

	image_barrier.oldLayout = current_layout
	image_barrier.newLayout = new_layout

	aspect_mask: vk.ImageAspectFlags =
		{.DEPTH} if new_layout == .DEPTH_ATTACHMENT_OPTIMAL else {.COLOR}

	image_barrier.subresourceRange = image_subresource_range(aspect_mask)
	image_barrier.image = image

	dep_info := vk.DependencyInfo {
		sType                   = .DEPENDENCY_INFO,
		imageMemoryBarrierCount = 1,
		pImageMemoryBarriers    = &image_barrier,
	}

	vk.CmdPipelineBarrier2(cmd, &dep_info)
}

copy_image_to_image :: proc(
	cmd: vk.CommandBuffer,
	source: vk.Image,
	destination: vk.Image,
	src_size: vk.Extent2D,
	dst_size: vk.Extent2D,
) {
	blit_region := vk.ImageBlit2 {
		sType = .IMAGE_BLIT_2,
		pNext = nil,
		srcOffsets = [2]vk.Offset3D {
			{0, 0, 0},
			{x = i32(src_size.width), y = i32(src_size.height), z = 1},
		},
		dstOffsets = [2]vk.Offset3D {
			{0, 0, 0},
			{x = i32(dst_size.width), y = i32(dst_size.height), z = 1},
		},
		srcSubresource = {aspectMask = {.COLOR}, mipLevel = 0, baseArrayLayer = 0, layerCount = 1},
		dstSubresource = {aspectMask = {.COLOR}, mipLevel = 0, baseArrayLayer = 0, layerCount = 1},
	}

	blit_info := vk.BlitImageInfo2 {
		sType          = .BLIT_IMAGE_INFO_2,
		srcImage       = source,
		srcImageLayout = .TRANSFER_SRC_OPTIMAL,
		dstImage       = destination,
		dstImageLayout = .TRANSFER_DST_OPTIMAL,
		filter         = .LINEAR,
		regionCount    = 1,
		pRegions       = &blit_region,
	}

	vk.CmdBlitImage2(cmd, &blit_info)
}

Allocated_Image :: struct {
	device:       vk.Device,
	image:        vk.Image,
	image_view:   vk.ImageView,
	image_extent: vk.Extent3D,
	image_format: vk.Format,
	allocator:    vma.Allocator,
	allocation:   vma.Allocation,
}

@(require_results)
create_image_default :: proc(
	self: ^Engine,
	size: vk.Extent3D,
	format: vk.Format,
	usage: vk.ImageUsageFlags,
	mipmapped := false,
) -> (
	new_image: Allocated_Image,
	ok: bool,
) {
	new_image.allocator = self.vma_allocator
	new_image.device = self.vk_device
	new_image.image_format = format
	new_image.image_extent = size

	img_info := image_create_info(format, usage, size)
	if mipmapped {
		img_info.mipLevels = u32(math.floor(math.log2(max(f32(size.width), f32(size.height))))) + 1
	}

	// Always allocate images on dedicated GPU memory
	alloc_info := vma.Allocation_Create_Info {
		usage          = .Gpu_Only,
		required_flags = {.DEVICE_LOCAL},
	}

	// Allocate and create the image
	vk_check(
		vma.create_image(
			self.vma_allocator,
			img_info,
			alloc_info,
			&new_image.image,
			&new_image.allocation,
			nil,
		),
	) or_return
	defer if !ok {
		vma.destroy_image(self.vma_allocator, new_image.image, nil)
	}

	// If the format is a depth format, we will need to have it use the correct aspect flag
	aspect_flag := vk.ImageAspectFlags{.COLOR}
	if format == .D32_SFLOAT {
		aspect_flag = vk.ImageAspectFlags{.DEPTH}
	}

	// Build a image-view for the draw image to use for rendering
	view_info := imageview_create_info(new_image.image_format, new_image.image, {.COLOR})

	vk_check(vk.CreateImageView(self.vk_device, &view_info, nil, &new_image.image_view)) or_return
	defer if !ok {
		vk.DestroyImageView(self.vk_device, new_image.image_view, nil)
	}

	return new_image, true
}

@(require_results)
create_image_from_data :: proc(
	self: ^Engine,
	data: rawptr,
	size: vk.Extent3D,
	format: vk.Format,
	usage: vk.ImageUsageFlags,
	mipmapped := false,
) -> (
	new_image: Allocated_Image,
	ok: bool,
) {
	data_size := vk.DeviceSize(size.depth * size.width * size.height * 4)
	upload_buffer := create_buffer(self, data_size, {.TRANSFER_SRC}, .Cpu_To_Gpu) or_return
	defer destroy_buffer(upload_buffer)

	intr.mem_copy(upload_buffer.info.mapped_data, data, data_size)

	usage := usage
	usage += {.TRANSFER_DST, .TRANSFER_SRC}
	new_image = create_image_default(self, size, format, usage, mipmapped) or_return
	defer if !ok {
		destroy_image(new_image)
	}

	Copy_Image_Data :: struct {
		upload_buffer: vk.Buffer,
		new_image:     vk.Image,
		size:          vk.Extent3D,
	}

	copy_data := Copy_Image_Data {
		upload_buffer = upload_buffer.buffer,
		new_image     = new_image.image,
		size          = size,
	}

	engine_immediate_submit(
		self,
		copy_data,
		proc(engine: ^Engine, cmd: vk.CommandBuffer, data: Copy_Image_Data) {
			// Transition image to transfer destination layout
			transition_image(cmd, data.new_image, .UNDEFINED, .TRANSFER_DST_OPTIMAL)

			// Setup the copy region
			copy_region := vk.BufferImageCopy {
				imageSubresource = {aspectMask = {.COLOR}, layerCount = 1},
				imageExtent = data.size,
			}

			// Copy the buffer into the image
			vk.CmdCopyBufferToImage(
				cmd,
				data.upload_buffer,
				data.new_image,
				.TRANSFER_DST_OPTIMAL,
				1,
				&copy_region,
			)

			// Transition image to shader read layout
			transition_image(cmd, data.new_image, .TRANSFER_DST_OPTIMAL, .SHADER_READ_ONLY_OPTIMAL)
		},
	) or_return

	return new_image, true
}

create_image :: proc {
	create_image_default,
	create_image_from_data,
}

destroy_image :: proc(self: Allocated_Image) {
	vk.DestroyImageView(self.device, self.image_view, nil)
	vma.destroy_image(self.allocator, self.image, self.allocation)
}
