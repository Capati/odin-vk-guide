package vk_bootstrap

// Vendor
import vk "vendor:vulkan"

setup_p_next_chain :: proc(structure: ^$T, structs: ^[dynamic]^vk.BaseOutStructure) {
	structure.pNext = nil
	if len(structs) <= 0 do return
	for i: uint = 0; i < len(structs) - 1; i += 1 {
		structs[i].pNext = structs[i + 1]
	}
	structure.pNext = structs[0]
}

VK_VERSION_MAJOR :: proc(version: u32) -> u32 {
	return (version >> 22) & 0x7F
}

VK_VERSION_MINOR :: proc(version: u32) -> u32 {
	return (version >> 12) & 0x3FF
}

VK_VERSION_PATCH :: proc(version: u32) -> u32 {
	return version & 0xFFF
}

convert_vulkan_to_vma_version :: proc(vulkan_version: u32) -> (vma_version: u32) {
	vma_major := VK_VERSION_MAJOR(vulkan_version) * 1000000
	vma_minor := VK_VERSION_MINOR(vulkan_version) * 1000
	vma_patch := VK_VERSION_PATCH(vulkan_version)

	vma_version = vma_major + vma_minor + vma_patch

	return
}
