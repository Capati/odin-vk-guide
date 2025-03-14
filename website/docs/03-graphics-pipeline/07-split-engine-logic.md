---
sidebar_position: 7
sidebar_label: "Split Engine Logic"
---

# Split Engine Logic

Before we proceed, we need to make a crucial decision: should we keep our `engine.odin` file as
it is, or should we split the codebase into more manageable pieces? While some developers
appreciate the simplicity of a single, large file, we should take advantage of one of Odin’s
best features: everything within a folder belongs to the same package and is seamlessly visible
to each other. This allows us to break our engine into smaller, cohesive modules without losing
integration.

Let's start with the initialization procedures. There are quite a few of them, and typically
do not require frequent changes.

1. Move the following procedures to a new file called `init.odin`:

    - `engine_init`
    - `engine_cleanup`
    - `engine_init_vulkan`
    - `default_debug_callback`
    - `engine_create_swapchain`
    - `engine_resize_swapchain`
    - `engine_destroy_swapchain`
    - `engine_init_swapchain`
    - `engine_init_commands`
    - `engine_init_sync_structures`
    - `engine_init_descriptors`
    - `engine_init_background_pipeline`
    - `engine_init_mesh_pipeline`
    - `engine_init_pipelines`
    - `engine_init_imgui`
    - `engine_init_default_data`

2. Create a file called `drawing.odin` and move the draw procedures:

    - `engine_get_current_frame`
    - `engine_draw`
    - `engine_draw_background`
    - `engine_ui_definition`
    - `engine_draw_imgui`
    - `engine_draw_geometry`

3. Move `engine_immediate_submit` to `core.odin`.

Now, our `engine.odin` file contains only the `Engine` related structures and the
`engine_begin` procedure. Although the changes are minimal, this reorganization can help keep
our project more manageable. Make sure to review the final codebase to see how the project is
structured before continue.
