---
sidebar_position: 3
sidebar_label: "Engine Architecture"
---

# Engine Architecture

We have all the low level mechanics we need to build an engine. We can draw arbitrary meshes,
and send data like buffers and textures to the shaders. What we need now is to make a proper
architecture for drawing objects, and stop going with the hardcoded structures on the
`Engine` structure.

The architecture here is meant to mimic GLTF a bit, as in the next chapter we will be loading
whole scenes dynamically from GLTF files. We will create our base GLTF pipelines following what
GLTF PBR spec gives us, and our first mesh objects.

The architecture will be based around 2 levels of structures. On one side, we will have the
`Render_Object` structure.

```odin
Render_Object :: struct {
    index_count:           u32,
    first_index:           u32,
    index_buffer:          vk.Buffer,
    material:              ^Material_Instance,
    transform:             la.Matrix4f32,
    vertex_buffer_address: vk.DeviceAddress,
}
```

This structure is a completely flattened abstraction of the parameters we need for a single
`vk.CmdDrawIndexed` call. We have the structures needed for the indexing of the mesh, then a
`Material_Instance` pointer, which will point to the `vk.Pipeline` and `vk.DescriptorSet` for a
given material. After that, we have the matrix of the object for 3d rendering, and its vertex
buffer pointer. Those 2 will go into **push-constants** as they are per-object dynamic data.

This structure will be written dynamically every frame, and the renderer logic will go through
an array of these `Render_Object` structures and directly record the draw commands.

The `Material_Instance` struct looks like this.

```odin
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

For the material system, we are going to hardcode into 2 pipelines, GLTF PBR Opaque, and GLTF
PBR Transparent. They all use the same pair of vertex and fragment shader. We will be using 2
descriptor sets only. Slot 0 will be our "global" descriptor set, which gets bound once, and
then used for all draws, and will contain the global data such as camera and environment
information. Later we will also add things like lights into it.  The slot 1 will be a
per-material descriptor set, and it will bind textures and material parameters. We will
directly mirror gltf, and have the textures the PBR GLTF material demands, plus a uniform
buffer with the color constants such as object color. the GLTF PBR material allows textures to
not be set, but in those cases we will be binding the default white or default black texture,
depending on what we need there. The `Material_Instance` struct also has a `Material_Pass` enum
which lets us separate between a opaque render object and a transparent one.

The reason why we have exclusively 2 pipelines is because we want to keep pipeline amount to
the absolute minimum. If we have less pipelines, we can preload them at startup, and it makes
the renderer much faster, specially once we start doing bindless and draw-indirect logic. Our
goal is that we will have a small amount of pipelines for each material type we have, such as
GLTF PBR material. The number of pipelines a engine needs to use directly affects performance.
A engine like the Doom Eternal one has ~200 total pipelines for the game, while unreal engine
projects often end up at 100.000+ pipelines, and compiling that many pipelines causes lots of
stutters, uses lots of space, and prevents advanced render functionality like draw-indirect.

Those `Render_Object` are very low level, so we need a way to write them. We will use a
scene-graph for this. This way we can have a hierarchy where some meshes are children of other
meshes, and we have empty non-mesh scenenodes too. This is typical on engines to be able to
build levels.

The type of scene-graph we will have is a medium/low performance design (we will improve this
later), but with the bonus of being very dynamic and easy to extend. Its also still fast enough
to render tens of thousands of objects.

```odin
Renderable :: struct {
    draw: proc(self: ^Renderable, top_matrix: la.matrix4x4f, ctx: ^Draw_Context),
}
```

We have a `Renderable` "interface" that defines a single `draw()` procedure. This takes a
matrix to use as parent, and a `Draw_Context`. The render context is just an array of render
objects for now. The idea is that when the `draw()` procedure is called, the object will insert
the renderables into the list to be drawn this frame.  This is commonly known as a immediate
design, and the big win it has is that we can draw the same object multiple times per frame
with different matrices to duplicate the object, or decide that one frame we dont draw it by
just skipping calling `draw()` according to some logic. This approach is great for dynamic
objects as resource management and lifetime is simplified a lot, and its also easy to write.
The downside is that we are going through the different objects calling a procedure to draw
things every frame, which adds up at higher object counts.

The `Node` object will derive from `Renderable`, and will have a local transform matrix + an
array of child nodes. When `draw()` is called on it, it calls `draw()` on its children

We then have a `Mesh_Node` object, that derives from `Node`. It holds the draw resources
needed, and when `draw()` is called on it, it builds the `Render_Object` and adds it to the
`Draw_Context` for drawing.

When we add other drawing types, such as lights, it will still work the same. We will hold a
list of lights on the `Draw_Context`, and a `Light_Node` will add its parameters to it if the
light is enabled. Same with other things we might want to draw such as a terrain, particles,
etc.

A trick we will be doing too is that once we add GLTF, we will also have a `Loaded_GLTF` object
as a `Renderable` (not a `Node`). this will hold the entire state and all the resources like
textures and meshes of a given GLTF file, and when `draw()` is called it will draw the contents
of the GLTF. Having a similar structure for OBJ and other formats will be useful.

Loading the GLTF itself will be done next chapter, but we will ready the mechanics of the
`Render_Object`'s and gltf material now.
