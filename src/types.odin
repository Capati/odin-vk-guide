package main

// Core
import glm "core:math/linalg/glsl"

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

Compute_Push_Constants :: struct {
	data1: glm.vec4,
	data2: glm.vec4,
	data3: glm.vec4,
	data4: glm.vec4,
}

Compute_Effect :: struct {
	name:     cstring,
	pipeline: vk.Pipeline,
	layout:   vk.PipelineLayout,
	data:     Compute_Push_Constants,
}
