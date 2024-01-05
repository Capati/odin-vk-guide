package main

// Core
import "core:log"
import "core:os"
import "core:runtime"

// Vendor
import vk "vendor:vulkan"

// Libs
import "libs:vkb"

load_shader_module :: proc(
	file_path: string,
	device: ^vkb.Device,
) -> (
	out: vk.ShaderModule,
	err: Error,
) {
	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()

	code, code_ok := os.read_entire_file(file_path, context.temp_allocator)

	if !code_ok {
		log.errorf("Failed to load shader file: [%s]", file_path)
		return 0, .Read_File_Failed
	}

	// Create a new shader module, using the code we loaded
	create_info := vk.ShaderModuleCreateInfo {
		sType    = .SHADER_MODULE_CREATE_INFO,
		codeSize = len(code),
		pCode    = cast(^u32)raw_data(code),
	}

	if res := vk.CreateShaderModule(_ctx.device.ptr, &create_info, nil, &out); res != .SUCCESS {
		log.errorf("failed to create shader module: [%v]", res)
		return 0, res
	}

	return
}
