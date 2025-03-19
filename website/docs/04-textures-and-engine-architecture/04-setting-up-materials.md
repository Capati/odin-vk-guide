---
sidebar_position: 4
sidebar_label: "Setting Up Materials"
---

# Setting Up Materials

Lets begin with setting up the structures we need to build `Material_Instance` and the GLTF
shaders we use.

Create a new file called `materials.odin` and add these structures.

```odin
package vk_guide

// Core
import la "core:math/linalg"

// Vendor
import vk "vendor:vulkan"

Material_Pass :: enum u8 {
    Main_Color,
    Transparent,
    Other,
}

Material_Pipeline :: struct {
    pipeline: vk.Pipeline,
    layout:   vk.PipelineLayout,
}

Material_Instance :: struct {
    pipeline:     ^Material_Pipeline,
    material_set: vk.DescriptorSet,
    pass_type:    Material_Pass,
}
```

This is the structs we need for the material data. `Material_Instance` will hold a raw pointer
(non owning) into its `Material_Pipeline` which contains the real pipeline. It holds a descriptor
set too.

For creating those objects, we are going to wrap the logic into a struct, as `Engine` is
getting too big, and we will want to have multiple materials later.

```odin
Metallic_Roughness_Constants :: struct {
    color_factors:       la.Vector4f32,
    metal_rough_factors: la.Vector4f32,
    // Padding, we need it anyway for uniform buffers
    extra:               [14]la.Vector4f32,
}

Metallic_Roughness_Resources :: struct {
    color_image:         Allocated_Image,
    color_sampler:       vk.Sampler,
    metal_rough_image:   Allocated_Image,
    metal_rough_sampler: vk.Sampler,
    data_buffer:         vk.Buffer,
    data_buffer_offset:  u32,
}

Metallic_Roughness :: struct {
    device:               vk.Device,
    opaque_pipeline:      Material_Pipeline,
    transparent_pipeline: Material_Pipeline,
    material_layout:      vk.DescriptorSetLayout,
    constants:            Metallic_Roughness_Constants,
    resources:            Metallic_Roughness_Resources,
    writer:               Descriptor_Writer,
}

metallic_roughness_build_pipelines :: proc(
    self: ^Metallic_Roughness,
    engine: ^Engine,
) -> (
    ok: bool,
) {
    return true
}

metallic_roughness_clear_resources :: proc(self: Metallic_Roughness) {
    vk.DestroyDescriptorSetLayout(self.device, self.material_layout, nil)
    vk.DestroyPipelineLayout(self.device, self.transparent_pipeline.layout, nil)

    vk.DestroyPipeline(self.device, self.transparent_pipeline.pipeline, nil)
    vk.DestroyPipeline(self.device, self.opaque_pipeline.pipeline, nil)
}

metallic_roughness_write :: proc(
    self: ^Metallic_Roughness,
    device: vk.Device,
    pass: Material_Pass,
    resources: ^Metallic_Roughness_Resources,
    descriptor_allocator: ^Descriptor_Allocator,
) -> (
    material: Material_Instance,
    ok: bool,
) {
    return material, true
}
```

We will hold the 2 pipelines we will be using for now, one for transparent draws, and other for
opaque (and alpha-masked). And the descriptor set layout for the material.

We have a struct for the material constants, which will be written into uniform buffers later.
The parameters we want for now are the `color_factors`, which are used to multiply the color
texture, and the `metal_rough_factors`, which have metallic and roughness parameters on `r` and
`b` components, plus two more that are used in other places.

We have also a bunch of `Vector4f32` for padding. In vulkan, when you want to bind a uniform
buffer, it needs to meet a minimum requirement for its alignment. **256 bytes** is a good
default alignment for this which all the gpus we target meet, so we are adding those
`Vector4f32` to pad the structure to **256 bytes**.

When we create the descriptor set, there are some textures we want to bind, and the uniform
buffer with the color factors and other properties. We will hold those in the `Material_Resources`
struct, so that its easy to send them to the `write_material` procedure.

The `build_pipelines` procedure will compile the pipelines, `clear_resources` will delete
everything, and `write_material` is where we will create the descriptor set and return a fully
built `Material_Instance` struct we can then use when rendering.

Lets look at the implementation of those procedures.

```odin
metallic_roughness_build_pipelines :: proc(
    self: ^Metallic_Roughness,
    engine: ^Engine,
) -> (
    ok: bool,
) {
    mesh_frag_shader := create_shader_module(
        engine.vk_device,
        #load("./../../shaders/compiled/mesh.frag.spv"),
    ) or_return
    defer vk.DestroyShaderModule(engine.vk_device, mesh_frag_shader, nil)

    mesh_vert_shader := create_shader_module(
        engine.vk_device,
        #load("./../../shaders/compiled/mesh.vert.spv"),
    ) or_return
    defer vk.DestroyShaderModule(engine.vk_device, mesh_vert_shader, nil)

    self.device = engine.vk_device

    layout_builder: Descriptor_Layout_Builder
    descriptor_layout_builder_init(&layout_builder, engine.vk_device)
    descriptor_layout_builder_add_binding(&layout_builder, 0, .UNIFORM_BUFFER)
    descriptor_layout_builder_add_binding(&layout_builder, 1, .COMBINED_IMAGE_SAMPLER)
    descriptor_layout_builder_add_binding(&layout_builder, 2, .COMBINED_IMAGE_SAMPLER)
    self.material_layout = descriptor_layout_builder_build(
        &layout_builder,
        {.VERTEX, .FRAGMENT},
    ) or_return

    layouts := [2]vk.DescriptorSetLayout {
        engine.gpu_scene_data_descriptor_layout,
        self.material_layout,
    }

    matrix_range := vk.PushConstantRange {
        offset     = 0,
        size       = size_of(GPU_Draw_Push_Constants),
        stageFlags = {.VERTEX},
    }

    pipeline_layout_info := pipeline_layout_create_info()
    pipeline_layout_info.setLayoutCount = 2
    pipeline_layout_info.pSetLayouts = raw_data(layouts[:])
    pipeline_layout_info.pPushConstantRanges = &matrix_range
    pipeline_layout_info.pushConstantRangeCount = 1

    new_layout: vk.PipelineLayout
    vk_check(
        vk.CreatePipelineLayout(engine.vk_device, &pipeline_layout_info, nil, &new_layout),
    ) or_return
    defer if !ok {
        vk.DestroyPipelineLayout(engine.vk_device, new_layout, nil)
    }

    self.opaque_pipeline.layout = new_layout
    self.transparent_pipeline.layout = new_layout

    // Build the stage-create-info for both vertex and fragment stages. This lets
    // the pipeline know the shader modules per stage
    pipeline_builder := pipeline_builder_create_default()
    pipeline_builder_set_shaders(&pipeline_builder, mesh_vert_shader, mesh_frag_shader)
    pipeline_builder_set_input_topology(&pipeline_builder, .TRIANGLE_LIST)
    pipeline_builder_set_polygon_mode(&pipeline_builder, .FILL)
    pipeline_builder_set_cull_mode(&pipeline_builder, vk.CullModeFlags_NONE, .CLOCKWISE)
    pipeline_builder_set_multisampling_none(&pipeline_builder)
    pipeline_builder_disable_blending(&pipeline_builder)
    pipeline_builder_enable_depth_test(&pipeline_builder, true, .GREATER_OR_EQUAL)

    // Render format
    pipeline_builder_set_color_attachment_format(&pipeline_builder, engine.draw_image.image_format)
    pipeline_builder_set_depth_attachment_format(
        &pipeline_builder,
        engine.depth_image.image_format,
    )

    // Use the mesh layout we created
    pipeline_builder.pipeline_layout = new_layout

    // Finally build the pipeline
    self.opaque_pipeline.pipeline = pipeline_builder_build(
        &pipeline_builder,
        engine.vk_device,
    ) or_return
    defer if !ok {
        vk.DestroyPipeline(engine.vk_device, self.opaque_pipeline.pipeline, nil)
    }

    // Create the transparent variant
    pipeline_builder_enable_blending_additive(&pipeline_builder)
    pipeline_builder_enable_depth_test(&pipeline_builder, false, .GREATER_OR_EQUAL)

    self.transparent_pipeline.pipeline = pipeline_builder_build(
        &pipeline_builder,
        engine.vk_device,
    ) or_return
    defer if !ok {
        vk.DestroyPipeline(engine.vk_device, self.transparent_pipeline.pipeline, nil)
    }

    return true
}
```

`build_pipelines` is similar to the `init_pipeline`'s procedures we already had. We load
the fragment and vertex shader and compile the pipelines. We are creating the pipeline layout
in here too, and we are also creating 2 pipelines with the same pipeline builder. First we
create the opaque pipeline, and then we enable blending and create the transparent pipeline.

You will note we have 2 new shaders, This is the code for them. Now that we will be rendering
materials properly, we need to create completely new shaders for all of this.

We will be using `#include`'s in our shaders this time, as the input will be used on both fragment
and vertex shaders.

`inc_input_structures.slang` looks like this:

```hlsl title="/shaders/source/inc_input_structures.slang"
struct SceneData
{
    float4x4 view;
    float4x4 proj;
    float4x4 view_proj;
    float4 ambient_color;
    float4 sunlight_direction; // w for sun power
    float4 sunlight_color;
};

[[vk::binding(0, 0)]]
ParameterBlock<SceneData> scene_data;

struct GLTFMaterialData
{
    float4 color_factors;
    float4 metal_rough_factors;
};
[[vk::binding(0, 1)]]
ParameterBlock<GLTFMaterialData> material_data;

[[vk::binding(1, 1)]]
Sampler2D color_tex;
[[vk::binding(2, 1)]]
Sampler2D metal_rough_tex;
```

:::info[]

We prefix included shaders with `inc_`, which makes it clear which files are meant to be
included rather than compiled directly.

:::

We have one uniform for scene-data. this will contain the view matrices and a few extras. This
will be the global descriptor set.

Then we have 3 bindings for set 1 for the material. We have the uniform for the material
constants, and 2 textures.

`mesh.vert.slang` looks like this:

```hlsl
#include "inc_input_structures.slang"

struct VSOutput
{
    float4 pos : SV_Position;
    [vk_location(0)]
    float3 outNormal : NORMAL;
    [vk_location(1)]
    float3 outColor : COLOR;
    [vk_location(2)]
    float2 outUV : TEXCOORD0;
};

struct Vertex
{
    float3 position;
    float uv_x;
    float3 normal;
    float uv_y;
    float4 color;
};

struct PushConstants
{
    float4x4 render_matrix;
    Vertex *vertex_buffer;
};

[vk_push_constant]
PushConstants push_constants;

[shader("vertex")]
VSOutput main(uint vertex_index: SV_VertexID)
{
    Vertex v = push_constants.vertex_buffer[vertex_index];

    float4 position = float4(v.position, 1.0);
    VSOutput output;
    output.pos = mul(scene_data.view_proj, mul(push_constants.render_matrix, position));

    output.outNormal = (mul(push_constants.render_matrix, float4(v.normal, 0.0))).xyz;
    output.outColor = v.color.xyz * material_data.color_factors.xyz;
    output.outUV.x = v.uv_x;
    output.outUV.y = v.uv_y;

    return output;
}
```

We have the same vertex logic we had before, but this time we multiply it by the matrices when
calculating the position. We also set the correct vertex color parameters and the UV. For the
normals, we multiply the vertex normal with the render matrix alone, no camera.

`mesh.frag.slang` looks like this:

```hlsl
#include "inc_input_structures.slang"

struct PSInput
{
    [vk_location(0)]
    float3 inNormal : NORMAL;
    [vk_location(1)]
    float3 inColor : COLOR;
    [vk_location(2)]
    float2 inUV : TEXCOORD0;
};

struct PSOutput
{
    [vk_location(0)]
    float4 out_frag_color : SV_Target0;
};

[shader("fragment")]
PSOutput main(PSInput input)
{
    PSOutput output;

    float light_value = max(dot(input.inNormal, scene_data.sunlight_direction.xyz), 0.1);

    float3 color = input.inColor * color_tex.Sample(input.inUV).xyz;
    float3 ambient = color * scene_data.ambient_color.xyz;

    output.out_frag_color =
        float4(color * light_value * scene_data.sunlight_color.w + ambient, 1.0);

    return output;
}
```

We are doing a very basic lighting shader. This will lets us render the meshes in a bit better
way. We calculate the surface color by multiplying the vertex color with the texture, and then
we do a simple light model where we have a single sunlight and an ambient light.

This is the kind of lighting you would see on very old games, simple procedure with 1 hardcoded
light and very basic multiplying for light formula. We will be improving this later, but we
need something that has a small amount of light calculation to display the materials better.

Lets go back to the `Metallic_Roughness_Constants` and fill the `write_material` procedure that
will create the descriptor sets and set the parameters.

```odin
metallic_roughness_write :: proc(
    self: ^Metallic_Roughness,
    device: vk.Device,
    pass: Material_Pass,
    resources: ^Metallic_Roughness_Resources,
    descriptor_allocator: ^Descriptor_Allocator,
) -> (
    material: Material_Instance,
    ok: bool,
) {
    material.pass_type = pass

    if pass == .Transparent {
        material.pipeline = &self.transparent_pipeline
    } else {
        material.pipeline = &self.opaque_pipeline
    }

    material.material_set = descriptor_allocator_allocate(
        descriptor_allocator,
        device,
        &self.material_layout,
    ) or_return

    descriptor_writer_init(&self.writer, device)
    descriptor_writer_clear(&self.writer)
    descriptor_writer_write_buffer(
        &self.writer,
        0,
        resources.data_buffer,
        size_of(Metallic_Roughness_Resources),
        vk.DeviceSize(resources.data_buffer_offset),
        .UNIFORM_BUFFER,
    ) or_return
    descriptor_writer_write_image(
        &self.writer,
        1,
        resources.color_image.image_view,
        resources.color_sampler,
        .SHADER_READ_ONLY_OPTIMAL,
        .COMBINED_IMAGE_SAMPLER,
    ) or_return
    descriptor_writer_write_image(
        &self.writer,
        2,
        resources.metal_rough_image.image_view,
        resources.metal_rough_sampler,
        .SHADER_READ_ONLY_OPTIMAL,
        .COMBINED_IMAGE_SAMPLER,
    ) or_return

    descriptor_writer_update_set(&self.writer, material.material_set)

    return material, true
}
```

Depending on what the material pass is, we will select either the opaque or the transparent
pipeline for it, then we allocate the descriptor set, and we write it using the images and
buffer from `Material_Resources`.

Lets create a default material we can use for testing as part of the load sequence of the
engine.

Lets first add the material structure to `Engine`, and a `Material_Instance` struct to use for
default.

```odin
Engine :: struct {
    // Materials
    default_data:         Material_Instance,
    metal_rough_material: Metallic_Roughness,
}
```

At the end of `engine_init_pipelines` we call the `build_pipelines` procedure on the material
structure to compile it.

```odin
engine_init_pipelines :: proc(self: ^Engine) -> (ok: bool) {
    // Rest of initializing procedures

    metallic_roughness_build_pipelines(&self.metal_rough_material, self) or_return
    deletion_queue_push(&self.main_deletion_queue, self.metal_rough_material)

    return true
}
```

Update the deletion queue to handle our mew material:

```odin title="deletion_queue.odin"
Resource :: union {
    // Higher-level custom resources
    Metallic_Roughness,
}

deletion_queue_flush :: proc(self: ^Deletion_Queue) {
    #reverse for &resource in self.resources {
        switch &res in resource {
        // Higher-level custom resources
        case Metallic_Roughness:
            metallic_roughness_clear_resources(res)
        }
    }
}
```

Now, at the end of `engine_init_default_data()`, we create the default `Material_Instance` struct
using the basic textures we just made. Like we did with the temporal buffer for scene data, we
are going to allocate the buffer and then put it into a deletion queue, but its going to be the
global deletion queue. We wont need to access the default material constant buffer at any point
after creating it

```odin
engine_init_default_data :: proc(self: ^Engine) -> (ok: bool) {
    // Other code above ---

    // DDefault the material textures
    material_resources := Metallic_Roughness_Resources {
        color_image         = self.white_image,
        color_sampler       = self.default_sampler_linear,
        metal_rough_image   = self.white_image,
        metal_rough_sampler = self.default_sampler_linear,
    }

    // Set the uniform buffer for the material data
    material_constants := create_buffer(
        self,
        size_of(Metallic_Roughness_Constants),
        {.UNIFORM_BUFFER},
        .Cpu_To_Gpu,
    ) or_return
    deletion_queue_push(&self.main_deletion_queue, material_constants)

    // Write the buffer
    scene_uniform_data := cast(^Metallic_Roughness_Constants)material_constants.info.mapped_data
    scene_uniform_data.color_factors = {1, 1, 1, 1}
    scene_uniform_data.metal_rough_factors = {1, 0.5, 0, 0}

    material_resources.data_buffer = material_constants.buffer
    material_resources.data_buffer_offset = 0

    self.default_data = metallic_roughness_write(
        &self.metal_rough_material,
        self.vk_device,
        .Main_Color,
        &material_resources,
        &self.global_descriptor_allocator,
    ) or_return

    return true
}
```

We are going to fill the parameters of the material on `Material_Resources` with the default white
image. Then we create a buffer to hold the material color, and add it for deletion. Then we
call `write_material` to create the descriptor set and initialize that `default_data` material
properly.
