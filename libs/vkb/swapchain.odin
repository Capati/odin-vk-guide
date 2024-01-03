package vk_bootstrap

// Core
import "core:log"

// Vendor
import vk "vendor:vulkan"

Swapchain :: struct {
	ptr:                       vk.SwapchainKHR,
	device:                    ^Device,
	image_count:               u32,
	queue_indices:             [Queue_Family_Indices]u32,
	// The image format actually used when creating the swapchain.
	image_format:              vk.Format,
	// The color space actually used when creating the swapchain.
	color_space:               vk.ColorSpaceKHR,
	image_usage_flags:         vk.ImageUsageFlags,
	extent:                    vk.Extent2D,
	// The value of `minImageCount` actually used when creating the swapchain; note that the
	// presentation engine is always free to create more images than that.
	requested_min_image_count: u32,
	// The present mode actually used when creating the swapchain.
	present_mode:              vk.PresentModeKHR,
	instance_version:          u32,
	allocation_callbacks:      ^vk.AllocationCallbacks,
}

Queue_Family_Indices :: enum {
	Graphics,
	Present,
}

destroy_swapchain :: proc(self: ^Swapchain) {
	if self == nil do return
	defer free(self)
	if self.device != nil && self.ptr != 0 {
		vk.DestroySwapchainKHR(self.device.ptr, self.ptr, self.allocation_callbacks)
	}
}

// Returns a slice of `vk.Image` handles to the swapchain.
swapchain_get_images :: proc(
	self: ^Swapchain,
	allocator := context.allocator,
) -> (
	images: []vk.Image,
	err: Error,
) {
	image_count: u32 = 0
	if res := vk.GetSwapchainImagesKHR(self.device.ptr, self.ptr, &image_count, nil);
	   res != .SUCCESS {
		log.fatalf("Failed to get swapchain images count: [%v]", res)
		return {}, .Failed_Get_Swapchain_Images
	}

	if image_count == 0 {
		log.errorf("No swapchain images available!")
		return {}, .Failed_Get_Swapchain_Images
	}

	images = make([]vk.Image, image_count, allocator) or_return

	if res := vk.GetSwapchainImagesKHR(self.device.ptr, self.ptr, &image_count, raw_data(images));
	   res != .SUCCESS {
		log.fatalf("Failed to get swapchain images: [%v]", res)
		return {}, .Failed_Get_Swapchain_Images
	}

	return
}

// Returns a slice of vk.ImageView's to the `vk.Image`'s of the swapchain.
swapchain_get_image_views :: proc(
	self: ^Swapchain,
	p_next: rawptr = nil,
) -> (
	views: []vk.ImageView,
	err: Error,
) {
	images := swapchain_get_images(self) or_return
	defer delete(images)

	already_contains_image_view_usage := false
	p_next := p_next

	for p_next != nil {
		if (cast(^vk.BaseInStructure)p_next).sType == .IMAGE_VIEW_CREATE_INFO {
			already_contains_image_view_usage = true
			break
		}
		p_next = (cast(^vk.BaseInStructure)p_next).pNext
	}

	desired_flags := vk.ImageViewUsageCreateInfo {
		sType = .IMAGE_VIEW_USAGE_CREATE_INFO,
		pNext = p_next,
		usage = self.image_usage_flags,
	}

	// Total of images to create views
	images_len := len(images)

	// Create image views for each image
	views = make([]vk.ImageView, images_len) or_return
	defer if err != nil {
		swapchain_destroy_image_views(self, &views)
	}

	for i in 0 ..< images_len {
		create_info := vk.ImageViewCreateInfo {
			sType = .IMAGE_VIEW_CREATE_INFO,
		}

		if self.instance_version >= vk.API_VERSION_1_1 && !already_contains_image_view_usage {
			create_info.pNext = &desired_flags
		} else {
			create_info.pNext = p_next
		}

		create_info.image = images[i]
		create_info.viewType = .D2
		create_info.format = self.image_format
		create_info.components = {
			r = .IDENTITY,
			g = .IDENTITY,
			b = .IDENTITY,
			a = .IDENTITY,
		}
		create_info.subresourceRange.aspectMask = {.COLOR}
		create_info.subresourceRange.baseMipLevel = 0
		create_info.subresourceRange.levelCount = 1
		create_info.subresourceRange.baseArrayLayer = 0
		create_info.subresourceRange.layerCount = 1

		if res := vk.CreateImageView(
			self.device.ptr,
			&create_info,
			self.allocation_callbacks,
			&views[i],
		); res != .SUCCESS {
			log.fatalf("Failed to create swapchain image view: [%v] ", res)
			return views, .Failed_Create_Swapchain_Image_Views
		}
	}

	return
}

swapchain_destroy_image_views :: proc(self: ^Swapchain, views: ^[]vk.ImageView) {
	for view, i in views {
		if view == 0 {
			log.warnf("Trying to destroy an invalid image view at [%d], ignoring...", i)
		}
		vk.DestroyImageView(self.device.ptr, view, self.allocation_callbacks)
	}
}
