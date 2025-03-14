---
sidebar_position: 5
sidebar_label: "Blending"
---

# Blending

When we created the pipeline builder, we completely skipped over the blending logic, setting it
as no blending. Blending is used for transparent objects and some graphical effects, so its
important to have it. for that reason, we will make the monkey we rendered last article
semi-transparent.

## Blending in the pipeline

We cant really control blending from shaders, thats property of the pipeline. The gpu hardware
itself does the blending mathematics for us, and has a bunch of options. We will be adding 2
new blending modes into the pipeline builder, one will be additive blending, where it just adds
the colors, and the other alpha-blend, where it would mix the colors.

Lets add these 2 functions into the pipeline builder.

```odin title="pipelines.odin"
pipeline_builder_enable_blending_additive :: proc(self: ^Pipeline_Builder) {
    self.color_blend_attachment.colorWriteMask = {.R, .G, .B, .A}
    self.color_blend_attachment.blendEnable = true
    self.color_blend_attachment.srcColorBlendFactor = .SRC_ALPHA
    self.color_blend_attachment.dstColorBlendFactor = .ONE
    self.color_blend_attachment.colorBlendOp = .ADD
    self.color_blend_attachment.srcAlphaBlendFactor = .ONE
    self.color_blend_attachment.dstAlphaBlendFactor = .ZERO
    self.color_blend_attachment.alphaBlendOp = .ADD
}

pipeline_builder_enable_blending_alphablend :: proc(self: ^Pipeline_Builder) {
    self.color_blend_attachment.colorWriteMask = {.R, .G, .B, .A}
    self.color_blend_attachment.blendEnable = true
    self.color_blend_attachment.srcColorBlendFactor = .SRC_ALPHA
    self.color_blend_attachment.dstColorBlendFactor = .ONE_MINUS_SRC_ALPHA
    self.color_blend_attachment.colorBlendOp = .ADD
    self.color_blend_attachment.srcAlphaBlendFactor = .ONE
    self.color_blend_attachment.dstAlphaBlendFactor = .ZERO
    self.color_blend_attachment.alphaBlendOp = .ADD
}
```

When setting blending options in vulkan, we need to fill the formula on both color and alpha.
The parameters work the same on both color and alpha. The formula works like this.

```c
outColor = srcColor * srcColorBlendFactor <op> dstColor * dstColorBlendFactor;
```

There are a few possible operators, but for the most part we will be doing `ADD`, as its the
most basic and guaranteed to work. There are many other much more advanced operators, but those
come with extensions and we wont use them. Source (from srcColor and blend factor) refers to
the color we are processing on our pipeline, and Destination (dstColor and blend factor) is the
current value of the image we are rendering into.

With the formula above, lets explain what the addition blending does.

- `ONE` sets the blend factor to just 1.0, so no multiplying.
- `SRC_ALPHA` on the other hand multiplies it by the alpha of the source.

Our blending ends up as this formula:

```c
outColor = srcColor.rgb * srcColor.a + dstColor.rgb * 1.0
```

The alpha-blend one will look like this instead.

```c
outColor = srcColor.rgb * srcColor.a + dstColor.rgb * (1.0 - srcColor.a)
```

Essentially making it into a lerp controlled by srcColor alpha, which will be from our shader.

Lets try to use it to see what it does. We dont have alpha set in our shaders, so lets just try
the additive one. Change the blending on the `engine_init_mesh_pipeline()` function.

```odin
// pipeline_builder_disable_blending(&builder)
pipeline_builder_enable_blending_additive(&builder)
```

You should now see the monkey mesh as semi-transparent, letting the color below it show.Play
around with the blending modes to see what effects they result on.

Before we move to chapter 4, lets implement window resizing.
