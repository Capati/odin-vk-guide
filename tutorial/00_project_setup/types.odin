package vk_guide

// Core
import "base:runtime"
import "core:log"

// Vendor
import vk "vendor:vulkan"

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
		runtime.print_caller_location(loc)
	}
	return
}
