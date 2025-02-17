package vk_guide

// Core
import "base:runtime"
import "core:log"

// Vendor
import vk "vendor:vulkan"

// Libraries
import "libs:vma"

log_caller_location_error :: #force_no_inline proc(loc: runtime.Source_Code_Location) {
	when ODIN_ERROR_POS_STYLE == .Default {
		if loc.column != 0 {
			log.errorf("%s(%d:%d)", loc.file_path, loc.line, loc.column)
		} else {
			log.errorf("%s(%d)", loc.file_path, loc.line)
		}
	} else when ODIN_ERROR_POS_STYLE == .Unix {
		if loc.column != 0 {
			log.errorf("%s:%d:%d:", loc.file_path, loc.line, loc.column)
		} else {
			log.errorf("%s:%d:", loc.file_path, loc.line)
		}
	} else {
		#panic("unhandled ODIN_ERROR_POS_STYLE")
	}
}

@(require_results)
vk_check :: #force_inline proc(
	res: vk.Result,
	message := "Detected Vulkan error",
	loc := #caller_location,
) -> (
	ok: bool,
) {
	ok = res == .SUCCESS
	if !ok {
		log.errorf("%s: \x1b[31m%v\x1b[0m", message, res)
		log_caller_location_error(loc)
	}
	return
}

Allocated_Image :: struct {
	image:        vk.Image,
	image_view:   vk.ImageView,
	allocation:   vma.Allocation,
	image_extent: vk.Extent3D,
	image_format: vk.Format,
}
