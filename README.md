# Odin vk-bootstrap

Inspired by [vk-bootstrap](https://github.com/charles-lunarg/vk-bootstrap/tree/main) for C++, this is a utility library in [Odin Language](https://odin-lang.org/) that jump starts initialization of Vulkan.

Read the [Getting Started](./docs/getting_started.md) guide for a quick start on using `odin-vk-bootstrap`

## Basic Usage

Copy the `vkb` folder to your project or to `shared` directory.

```odin
import "vkb"
import vk "vendor:vulkan"

main :: proc() {
    // Start by creating a new instance builder
    instance_builder, instance_builder_err := vkb.init_instance_builder()
    if instance_builder_err != nil do return
    defer vkb.destroy_instance_builder(&instance_builder)

    // Require the minimum Vulkan api version 1.1
    vkb.instance_set_minimum_version(&instance_builder, vk.API_VERSION_1_1)

    when ODIN_DEBUG {
        // Enable `VK_LAYER_KHRONOS_validation` layer
        vkb.instance_request_validation_layers(&instance_builder)

        // Enable debug reporting with a default messenger callback
        vkb.instance_use_default_debug_messenger(&instance_builder)
    }

    instance, instance_err := vkb.build_instance(&instance_builder)
    if instance_err != nil do return
    defer vkb.destroy_instance(instance)

    // Create a new physical device selector
    selector, selector_err := vkb.init_physical_device_selector(instance)
    if selector_err != nil do return
    defer vkb.destroy_selection_criteria(&selector)

    // We want a GPU that can render to current Window surface
    vkb.selector_set_surface(&selector, /* from user created window*/)

    // Require a vulkan 1.1 capable device
    vkb.selector_set_minimum_version(&selector, vk.API_VERSION_1_1)

    // Try to select a suitable device
    physical_device, physical_device_err := vkb.select_physical_device(&selector)
    if physical_device_err != nil do return

    // In Vulkan you don't need to destroy a physical device, but here you need
    // to free some resources when the physical device was created.
    defer vkb.destroy_physical_device(physical_device)

    // Create a device builder
    device_builder, device_builder_err := vkb.init_device_builder(physical_device)
    if device_builder_err != nil do return
    defer vkb.destroy_device_builder(&device_builder)

    // Automatically propagate needed data from instance & physical device
    device, device_err := vkb.build_device(&device_builder)
    if device_err != nil do return
    defer vkb.destroy_device(device)

    // Get the graphics queue with a helper function
    graphics_queue, graphics_queue_err := vkb.device_get_queue(device, .Graphics)
    if graphics_queue_err != nil do return
}
```

See [Triangle Example](./examples//triangle//triangle.odin) for an example that renders a triangle to the screen.
