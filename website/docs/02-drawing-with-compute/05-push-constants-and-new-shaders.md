---
sidebar_position: 5
sidebar_label: "Push Constants and new shaders"
description: TODO.
---

# Push Constants and new shaders

We have a way to run compute shaders to display, and a way to add debug-UI to the engine. Lets
use that to send data to the shaders through the UI, and have an interactive thing.

We will be using PushConstants to send data to the shader. PushConstants are a feature unique
to vulkan that allows for some small amount of data to be sent to the GPU. Keeping this data
small is important, as most drivers will have a fast-path if the data is below some bytes
(consult gpu vendor documentation). Its main use case is to send some per-object indexes or a
couple matrices that change for every object. If you have data that is bigger than a handful of
floats or ints, you should be using other systems that we will show next chapter.

Push constants are configured when you create a pipeline layout. To keep things simple and not
have to change too much code, we are going to default our pushconstants for compute effects to
4 vec4 vectors. 16 floats will be enough for playing around with the shaders.

In the project shader folder, there are multiple compute shaders you will be able to swap
around. We will focus on a simple color gradient one, but you can try the other demo shaders
the project comes with.

As all of our compute shaders will share the same layout, we are going to also add a drop-down
to the UI to select which pipeline to use. This way we can flip between the different compute
shaders at runtime to test them.

The shader we are going to use to demonstrate pushconstants is this. It will blend between 2
colors by Y coordinate, making a vertical gradient.

Its found in `shaders/source/gradient_color.comp.hlsl`.

```hlsl
[[vk::push_constant]]
struct PushConstantsBlock
{
    float4 data1;
    float4 data2;
    float4 data3;
    float4 data4;
} PushConstants;

RWTexture2D<float4> image : register(u0, space0);

[numthreads(16, 16, 1)]
void main(uint3 GlobalInvocationID : SV_DispatchThreadID)
{
    int2 texelCoord = int2(GlobalInvocationID.xy);

    // Get image dimensions
    uint width, height;
    image.GetDimensions(width, height);
    int2 size = int2(width, height);

    float4 topColor = PushConstants.data1;
    float4 bottomColor = PushConstants.data2;

    if (texelCoord.x < size.x && texelCoord.y < size.y)
    {
        float blend = (float)texelCoord.y / (float)(size.y);

        // HLSL lerp is equivalent to GLSL mix
        image[texelCoord] = lerp(topColor, bottomColor, blend);
    }
}
```

Its mostly the same as the gradient shader we had from last article. The
`[[vk::push_constant]]` is a Vulkan-specific attribute in HLSL that identifies a struct as
containing push constant data, we added 4 `float4`, and we are loading top and bottom color
from it. `data3` and `data4` are not used, but we have them in there to avoid the validation
layers complaining that we have a push-constants range larger than we have in the shader.

We now need to change the pipeline layout creation to configure the pushconstants range. Lets
first create a structure that mirrors those pushconstants directly into `engine.odin`.

```odin
Compute_Push_Constants :: struct {
    data1: [4]f32,
    data2: [4]f32,
    data3: [4]f32,
    data4: [4]f32,
}
```

To set the push constant ranges, we need to change the code that creates the pipeline layout at
the start of `engine_init_pipelines`. the new version looks like this.

```odin
push_constant := vk.PushConstantRange {
    offset     = 0,
    size       = size_of(Compute_Push_Constants),
    stageFlags = {.COMPUTE},
}

compute_layout := vk.PipelineLayoutCreateInfo {
    sType                  = .PIPELINE_LAYOUT_CREATE_INFO,
    pSetLayouts            = &self.draw_image_descriptor_layout,
    setLayoutCount         = 1,
    pPushConstantRanges    = &push_constant,
    pushConstantRangeCount = 1,
}

vk_check(
    vk.CreatePipelineLayout(
        self.vk_device,
        &compute_layout,
        nil,
        &self.gradient_pipeline_layout,
    ),
) or_return
```

We need to add a `vk.PushConstantRange` to the pipeline layout info. A `vk.PushConstantRange`
holds an offset, which we will keep at 0, and then a size plus the stage flags. For size we
will use our cpp version of the structure, as that matches. And for stage flags its going to be
compute because its the only stage we have right now.

After that, just change the shader to be compiled to be the new one.

```odin
GRADIENT_COLOR_SPV :: #load("./../../shaders/compiled/gradient_color.comp.spv")
gradient_color_shader := create_shader_module(self.vk_device, GRADIENT_COLOR_SPV) or_return
defer vk.DestroyShaderModule(self.vk_device, gradient_color_shader, nil)

stage_info := vk.PipelineShaderStageCreateInfo {
    sType  = .PIPELINE_SHADER_STAGE_CREATE_INFO,
    stage  = {.COMPUTE},
    module = gradient_color_shader,
    pName  = "main",
}
```

This is all we need to add pushconstants to a shader. lets now use them from the render loop.

```odin title="engine_draw_background"
pc := Compute_Push_Constants {
    {1, 0, 0, 1}, // data1
    {0, 0, 1, 1}, // data2
}

// Push constants
vk.CmdPushConstants(
    cmd,
    self.gradient_pipeline_layout,
    {.COMPUTE},
    0,
    size_of(Compute_Push_Constants),
    &pc,
)

// Dispatch the compute shader
vk.CmdDispatch(
    cmd,
    u32(math.ceil_f32(f32(self.draw_extent.width) / 16.0)),
    u32(math.ceil_f32(f32(self.draw_extent.height) / 16.0)),
    1,
)
```

To update pushconstants, we call `vk.CmdPushConstants`. it requires the pipeline layout, an
offset for the data to be written to (we use just offset 0), and the size of the data + the
pointer to copy. It also requires the shader stage flags as one can update pushconstants for
different stages on different commands.

This is all. If you run the program at this moment, you will see a gradient of red to blue.

## IMGUI Editable Parameters

We are hardcoding the colors right now, but we can do better than that by adding a small window
using imgui with those as editable colors.

We want to store an array of compute pipelines we will be drawing, alongside one of those
`Compute_Push_Constant` structs for their value. This way we will be able to switch between
different compute shaders.

Lets add a struct to `engine.odin` with that.

```odin
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
```

Now lets add an array of them to the `Engine` structure.

```odin
background_effects:        [Compute_Effect_Kind]Compute_Effect,
current_background_effect: Compute_Effect_Kind,
```

Lets change the code on init_pipelines to create 2 of these effects. One will be the gradient
we just did, the other is a pretty star-night sky shader.

The sky shader is too complicated to explain here, but feel free to check the code on
`sky.comp.hlsl`. Its taken from shadertoy and adapted slightly to run as a compute shader in
here. data1 of the pushconstant will contain sky color x/y/z, and then w can be used to control
the amount of stars.

With 2 shaders, we need to create 2 different `vk.ShaderModule`.

```odin
gradient_color_shader := create_shader_module(
    self.vk_device,
    #load("./../../shaders/compiled/gradient_color.comp.spv"),
) or_return
defer vk.DestroyShaderModule(self.vk_device, gradient_color_shader, nil)

sky_shader := create_shader_module(
    self.vk_device,
    #load("./../../shaders/compiled/sky.comp.spv"),
) or_return
defer vk.DestroyShaderModule(self.vk_device, sky_shader, nil)

stage_info := vk.PipelineShaderStageCreateInfo {
    sType  = .PIPELINE_SHADER_STAGE_CREATE_INFO,
    stage  = {.COMPUTE},
    module = gradient_color_shader,
    pName  = "main",
}

compute_pipeline_create_info := vk.ComputePipelineCreateInfo {
    sType  = .COMPUTE_PIPELINE_CREATE_INFO,
    layout = self.gradient_pipeline_layout,
    stage  = stage_info,
}

gradient_color := Compute_Effect {
    layout = self.gradient_pipeline_layout,
    name = "Gradient Color",
    data = {data1 = {1, 0, 0, 1}, data2 = {0, 0, 1, 1}},
}

vk_check(
    vk.CreateComputePipelines(
        self.vk_device,
        0,
        1,
        &compute_pipeline_create_info,
        nil,
        &gradient_color.pipeline,
    ),
) or_return

// Change the shader module only to create the sky shader
compute_pipeline_create_info.stage.module = sky_shader

sky := Compute_Effect {
    layout = self.gradient_pipeline_layout,
    name = "Sky",
    data = {data1 = {0.1, 0.2, 0.4, 0.97}},
}

vk_check(
    vk.CreateComputePipelines(
        self.vk_device,
        0,
        1,
        &compute_pipeline_create_info,
        nil,
        &sky.pipeline,
    ),
) or_return

// Set the 2 background effects
self.background_effects[.Gradient] = gradient_color
self.background_effects[.Sky] = sky

deletion_queue_push(self.main_deletion_queue, self.gradient_pipeline_layout)
deletion_queue_push(self.main_deletion_queue, gradient_color.pipeline)
deletion_queue_push(self.main_deletion_queue, sky.pipeline)
```

We have changed the pipelines procedure. We keep the pipeline layout from before, but now we
create 2 different pipelines, and store them into the `background_effects` array. We also give
the effects some default data.

Now we can add the imgui debug window for this. This goes on `engine_run()` procedure. We will
replace the demo effect call with the new ui logic

```odin
im.new_frame()

if im.begin("Background", nil, {.Always_Auto_Resize}) {
    selected := &self.background_effects[self.current_background_effect]

    im.text("Selected effect: %s", selected.name)

    @(static) current_background_effect: i32
    current_background_effect = i32(self.current_background_effect)

    // If the combo is opened and an item is selected, update the current effect
    if im.begin_combo("Effect", selected.name) {
        for effect, i in self.background_effects {
            is_selected := i32(i) == current_background_effect
            if im.selectable(effect.name, is_selected) {
                current_background_effect = i32(i)
                self.current_background_effect = Compute_Effect_Kind(
                    current_background_effect,
                )
            }

            // Set initial focus when the currently selected item becomes visible
            if is_selected {
                im.set_item_default_focus()
            }
        }
        im.end_combo()
    }

    im.input_float4("data1", &selected.data.data1)
    im.input_float4("data2", &selected.data.data2)
    im.input_float4("data3", &selected.data.data3)
    im.input_float4("data4", &selected.data.data4)

}
im.end()

im.render()
```

First, the code grabs the selected background effect by indexing into the `background_effects`
array using `current_background_effect`. Then it uses `im.text` to display the effect name.

Next, it declares a static variable `current_background_effect` of type i32 and initializes it
with the current effect index.

Then it creates a combo box (dropdown) using `im.begin_combo` that shows all available effects.
When the user selects a different effect from the dropdown, it updates both the static
`current_background_effect` variable and the `self.current_background_effect` member variable
(converting the index using `Compute_Effect_Kind`).

Finally, it displays four input fields for `float4` vectors (`data1` through `data4`) that
allow editing the properties of the selected effect.

Last we need to do is to change the render loop to select the shader selected with its data.

```odin
engine_draw_background :: proc(self: ^Engine, cmd: vk.CommandBuffer) -> (ok: bool) {
    effect := &self.background_effects[self.current_background_effect]

    // Bind the compute pipeline
    vk.CmdBindPipeline(cmd, .COMPUTE, effect.pipeline)

    // Bind the descriptor set containing the draw image
    vk.CmdBindDescriptorSets(
        cmd,
        .COMPUTE,
        self.gradient_pipeline_layout,
        0,
        1,
        &self.draw_image_descriptors,
        0,
        nil,
    )

    // Push constants
    vk.CmdPushConstants(
        cmd,
        self.gradient_pipeline_layout,
        {.COMPUTE},
        0,
        size_of(Compute_Push_Constants),
        &effect.data,
    )

    // Dispatch the compute shader
    vk.CmdDispatch(
        cmd,
        u32(math.ceil_f32(f32(self.draw_extent.width) / 16.0)),
        u32(math.ceil_f32(f32(self.draw_extent.height) / 16.0)),
        1,
    )

    return true
}
```

Not much of a change, we are just hooking into the compute effect array and uploading the
pushconstants from there.

Try to run the app now, and you will see a debug window where it lets you select the shader,
and edit its parameters.
