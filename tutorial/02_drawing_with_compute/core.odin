package vk_guide

// Core
import intr "base:intrinsics"
import "base:runtime"
import "core:log"

// Vendor
import vk "vendor:vulkan"

// Local packages
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

Allocated_Image :: struct {
    device:       vk.Device,
    image:        vk.Image,
    image_view:   vk.ImageView,
    image_extent: vk.Extent3D,
    image_format: vk.Format,
    allocator:    vma.Allocator,
    allocation:   vma.Allocation,
}

destroy_image :: proc(self: Allocated_Image) {
    vk.DestroyImageView(self.device, self.image_view, nil)
    vma.destroy_image(self.allocator, self.image, self.allocation)
}
