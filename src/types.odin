package main

// Vendor
import vk "vendor:vulkan"

// Libs
import "libs:vma"

Allocated_Image :: struct {
	image:        vk.Image,
	image_view:   vk.ImageView,
	allocation:   vma.Allocation,
	image_extent: vk.Extent3D,
	image_format: vk.Format,
}
