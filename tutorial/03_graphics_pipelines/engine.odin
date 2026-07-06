package vk_guide

// Core
import "core:log"

// Vendor
import "vendor:glfw"
import vk "vendor:vulkan"

// Local packages
import "libs:vkb"
import "libs:vma"
import im "libs:imgui"
import im_glfw "libs:imgui/backends/glfw"
import im_vk "libs:imgui/backends/vulkan"

TITLE :: "0. Project Setup"
DEFAULT_WINDOW_EXTENT :: vk.Extent2D{1280, 678} // Default window size in pixels

Frame_Data :: struct {
    command_pool:        vk.CommandPool,
    main_command_buffer: vk.CommandBuffer,
    swapchain_semaphore: vk.Semaphore,
    render_fence:        vk.Fence,
    deletion_queue:      Deletion_Queue,
}

FRAME_OVERLAP :: 2

Compute_Push_Constants :: struct {
    data1: [4]f32,
    data2: [4]f32,
    data3: [4]f32,
    data4: [4]f32,
}

Compute_Effect_Kind :: enum {
    Gradient,
    Sky,
}

Compute_Effect :: struct {
    name:     cstring,
    pipeline: vk.Pipeline,
    layout:   vk.PipelineLayout,
    data:     Compute_Push_Constants,
}

Engine :: struct {
    // Platform
    window:                       glfw.WindowHandle,
    window_extent:                vk.Extent2D,
    is_initialized:               bool,
    stop_rendering:               bool,

    // GPU Context
    vk_instance:                  vk.Instance,
    vk_physical_device:           vk.PhysicalDevice,
    vk_surface:                   vk.SurfaceKHR,
    vk_device:                    vk.Device,

    // vk-bootstrap
    vkb:                          struct {
        instance:        vkb.Instance,
        physical_device: vkb.Physical_Device,
        device:          vkb.Device,
        swapchain:       vkb.Swapchain,
    },

    // Swapchain
    vk_swapchain:                 vk.SwapchainKHR,
    swapchain_format:             vk.Format,
    swapchain_extent:             vk.Extent2D,
    swapchain_images:             []vk.Image,
    swapchain_image_views:        []vk.ImageView,
    swapchain_image_semaphores:   []vk.Semaphore,

    // Frame resources
    frames:                       [FRAME_OVERLAP]Frame_Data,
    frame_number:                 int,
    graphics_queue:               vk.Queue,
    graphics_queue_family:        u32,

    // Memory management
    vma_allocator:                vma.Allocator,
    main_deletion_queue:          Deletion_Queue,

    // Rendering resources
    draw_image:                   Allocated_Image,
    depth_image:                  Allocated_Image,
    draw_extent:                  vk.Extent2D,
    render_scale:                 f32,
    gradient_pipeline_layout:     vk.PipelineLayout,
    background_effects:           [Compute_Effect_Kind]Compute_Effect,
    current_background_effect:    Compute_Effect_Kind,
    mesh_pipeline_layout:         vk.PipelineLayout,
    mesh_pipeline:                vk.Pipeline,
    test_meshes:                  Mesh_Asset_List,

    // Descriptor management
    global_descriptor_allocator:  Descriptor_Allocator,
    draw_image_descriptors:       vk.DescriptorSet,
    draw_image_descriptor_layout: vk.DescriptorSetLayout,

    // Immediate submit
    imm_fence:                    vk.Fence,
    imm_command_buffer:           vk.CommandBuffer,
    imm_command_pool:             vk.CommandPool,
}

@(private)
g_logger: log.Logger

engine_ui_definition :: proc(self: ^Engine) {
    // ImGUi new frame
    im_glfw.NewFrame()
    im_vk.NewFrame()
    im.NewFrame()

    if im.Begin("Background", nil, {.AlwaysAutoResize}) {
        im.SliderFloat("Render scale", &self.render_scale, 0.3, 1.0)

        selected := &self.background_effects[self.current_background_effect]

        im.Text("Selected effect: %s", selected.name)

        @(static) current_background_effect: i32
        current_background_effect = i32(self.current_background_effect)

        // If the combo is opened and an item is selected, update the current effect
        if im.BeginCombo("Effect", selected.name) {
            for effect, i in self.background_effects {
                is_selected := i32(i) == current_background_effect
                if im.Selectable(effect.name, is_selected) {
                    current_background_effect = i32(i)
                    self.current_background_effect = Compute_Effect_Kind(
                        current_background_effect,
                    )
                }

                // Set initial focus when the currently selected item becomes visible
                if is_selected {
                    im.SetItemDefaultFocus()
                }
            }
            im.EndCombo()
        }

        im.InputFloat4("data1", &selected.data.data1)
        im.InputFloat4("data2", &selected.data.data2)
        im.InputFloat4("data3", &selected.data.data3)
        im.InputFloat4("data4", &selected.data.data4)

    }
    im.End()

    im.Render()
}

// Run main loop.
@(require_results)
engine_run :: proc(self: ^Engine) -> (ok: bool) {
    monitor_info := get_primary_monitor_info()

    t: Timer
    timer_init(&t, monitor_info.refresh_rate)

    log.info("Entering main loop...")

    for !glfw.WindowShouldClose(self.window) {
        glfw.PollEvents()

        if self.stop_rendering {
            glfw.WaitEvents()
            timer_init(&t, monitor_info.refresh_rate)
            continue
        }

        timer_tick(&t)
        engine_ui_definition(self)
        engine_draw(self) or_return

        when ODIN_DEBUG {
            if timer_check_fps_updated(t) {
                window_update_title_with_fps(self.window, TITLE, timer_get_fps(t))
            }
        }
    }

    log.info("Exiting...")

    return true
}
