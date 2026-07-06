package vk_guide

// Core
import "core:math"
import la "core:math/linalg"

matrix4_perspective_reverse_z_f32 :: proc "contextless" (
    fovy, aspect, near: f32,
    flip_y_axis := true,
) -> (
    m: la.Matrix4f32,
) #no_bounds_check {
    epsilon :: 0.00000095367431640625 // 2^-20 or about 10^-6
    fov_scale := 1 / math.tan(fovy * 0.5)

    m[0, 0] = fov_scale / aspect
    m[1, 1] = fov_scale

    // Set up reverse-Z configuration
    m[2, 2] = epsilon
    m[2, 3] = near * (1 - epsilon)
    m[3, 2] = -1

    // Handle Vulkan Y-flip if needed
    if flip_y_axis {
        m[1, 1] = -m[1, 1]
    }

    return
}

pack_unorm_4x8 :: proc "contextless" (v: la.Vector4f32) -> u32 {
    // Round and clamp each component to [0,255] range as u8
    r := u8(math.round_f32(clamp(v.x, 0.0, 1.0) * 255.0))
    g := u8(math.round_f32(clamp(v.y, 0.0, 1.0) * 255.0))
    b := u8(math.round_f32(clamp(v.z, 0.0, 1.0) * 255.0))
    a := u8(math.round_f32(clamp(v.w, 0.0, 1.0) * 255.0))

    // Pack into u32 (using RGBA layout)
    return u32(r) | (u32(g) << 8) | (u32(b) << 16) | (u32(a) << 24)
}
