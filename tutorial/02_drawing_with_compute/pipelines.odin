package vk_guide

// Core
import "base:runtime"
import "core:log"
import "core:os"

// Vendor
import vk "vendor:vulkan"

load_shader_module :: proc(
    device: vk.Device,
    file_path: string,
) -> (
    shader: vk.ShaderModule,
    ok: bool,
) #optional_ok {
    runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
    code, code_err := os.read_entire_file(file_path, context.temp_allocator)
    if code_err != nil {
        log.errorf("Failed to load shader file [%s]: %#v", file_path, code_err)
        return
    }
    // Create a new shader module, using the code we loaded
    return create_shader_module(device, code)
}

create_shader_module :: proc(
    device: vk.Device,
    code: []byte,
) -> (
    shader: vk.ShaderModule,
    ok: bool,
) #optional_ok {
    create_info := vk.ShaderModuleCreateInfo {
        sType    = .SHADER_MODULE_CREATE_INFO,
        codeSize = len(code),
        pCode    = cast(^u32)raw_data(code),
    }

    vk_check(
        vk.CreateShaderModule(device, &create_info, nil, &shader),
        "failed to create shader module",
    ) or_return

    return shader, true
}
