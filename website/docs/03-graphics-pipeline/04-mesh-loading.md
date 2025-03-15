---
sidebar_position: 4
sidebar_label: "Mesh Loading"
---

# Mesh Loading

We will do proper scene loading later, but until we go there, we need something better than a
rectangle as a mesh. For that, we will begin to load **GLTF** files but in a very simplified
and wrong way, getting only the geometry data and ignoring everything else. To accomplish this,
we are using the `cgltf` library provided through the vendor package, which offers a lightweight
solution for parsing GLTF files.

There is a **glTF** file that came with the starting-point repository, called `basicmesh.glb`.
That one has a cube, a sphere, and a monkey head meshes centered in the origin. Being a file as
simple as that one is, its easy to load it correctly without having to setup up real gltf
loading.

A **GLTF** file will contain a list of meshes, each mesh with multiple primitives on it. This
separation is for meshes that use multiple materials, and thus need multiple draw calls to draw
it. The file also contains a scene-tree of scenenodes, some of them containing meshes. We will
only be loading the meshes now, but later we will have the full scene-tree and materials
loaded.

:::warning[Binaries]

The `cgltf` vendor package currently provides precompiled binaries only for Windows. If you're
using a Unix-based system (e.g., Linux or macOS), you'll need to compile the library yourself.
Fortunately, Odin includes a `Makefile` script to simplify this process, located at
`<path-to-odin>/vendor/cgltf/src`. Run one of the following commands based on your operating
system:

```bash
make linux   # For Linux
make darwin  # For macOS
```

:::

Our loading code will all be on the file `loader.odin`. Lets start by adding a couple of
`import`'s and structures we will need.

```odin title="loader.odin (create the file)"
package vk_guide

// Core
import "base:runtime"
import "core:log"
import "core:strings"

// Vendor
import "vendor:cgltf"

Geo_Surface :: struct {
    start_index: u32,
    count:       u32,
}

Mesh_Asset :: struct {
    name:         string,
    surfaces:     [dynamic]Geo_Surface,
    mesh_buffers: GPU_Mesh_Buffers,
}

Mesh_Asset_List :: [dynamic]^Mesh_Asset

// Override the vertex colors with the vertex normals which is useful for debugging.
OVERRIDE_VERTEX_COLORS :: #config(OVERRIDE_VERTEX_COLORS, true)
```

A given mesh asset will have a name, loaded from the file, and then the mesh buffers. But it
will also have an array of `Geo_Surface` that has the sub-meshes of this specific mesh. When
rendering each submesh will be its own draw. We will use `start_index` and `count` for that
drawcall as we will be appending all the vertex data of each surface into the same buffer.

Now, implement the mesh loading procedure using `cgltf`:

```odin
// Loads 3D mesh data from a glTF file and upload to the GPU.
load_gltf_meshes :: proc(
    engine: ^Engine,
    file_path: string,
    allocator := context.allocator,
) -> (
    meshes: Mesh_Asset_List,
    ok: bool,
) {
    log.debugf("Loading GLTF: %s", file_path)

    // Configure cgltf parsing options
    // Using .invalid type lets cgltf automatically detect if it's .gltf or .glb
    options := cgltf.options {
        type = .invalid,
    }

    ta := context.temp_allocator
    runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()

    c_file_path := strings.clone_to_cstring(file_path, ta)

    // Parse the glTF file using cgltf library
    data, result := cgltf.parse_file(options, c_file_path)
    if result != .success {
        log.errorf("Failed to parse GLTF: %v", result)
        return
    }
    defer cgltf.free(data) // Clean up parsed data when procedure exits

    // Load external buffer data (binary data referenced by glTF)
    buffer_result := cgltf.load_buffers(options, data, c_file_path)
    if buffer_result != .success {
        log.errorf("Failed to load glTF buffers: %v\n", buffer_result)
        return
    }

    // Temporary arrays for indices and vertices
    indices_temp: [dynamic]u32;indices_temp.allocator = ta
    vertices_temp: [dynamic]Vertex;vertices_temp.allocator = ta

    // Initialize the output mesh list
    meshes = make(Mesh_Asset_List, allocator)
    defer if !ok {
        destroy_mesh_assets(&meshes, allocator)
    }

    // Process each mesh in the glTF file
    for &mesh in data.meshes {
        // Allocate new mesh asset
        new_mesh := new(Mesh_Asset, allocator)

        // Set mesh name
        new_mesh.name =
            mesh.name != nil ? strings.clone(string(mesh.name)) : strings.clone("unnamed_mesh")

        // Initialize surfaces array for this mesh
        new_mesh.surfaces = make([dynamic]Geo_Surface, allocator)

        // Clear temporary arrays for this mesh
        clear(&indices_temp)
        clear(&vertices_temp)

        // Process each primitive (surface) in the mesh
        for &prim in mesh.primitives {
            new_surface: Geo_Surface
            // Record where this surface's indices start and how many there are
            new_surface.start_index = u32(len(indices_temp))
            new_surface.count = u32(prim.indices.count)

            // Track starting vertex count for index offsetting
            initial_vtx := len(vertices_temp)

            // Load index data
            {
                index_accessor := prim.indices

                // Pre-allocate space for new indices
                reserve(&indices_temp, len(indices_temp) + int(index_accessor.count))

                // Temporary buffer for unpacking indices
                index_count := index_accessor.count
                index_buffer := make([]u32, index_count, ta)

                // Unpack all indices from the glTF accessor
                if indices_unpacked := cgltf.accessor_unpack_indices(
                    index_accessor,
                    raw_data(index_buffer),
                    uint(size_of(u32)),
                    index_count,
                ); indices_unpacked < uint(index_count) {
                    // Error if we didn't get all expected indices
                    log.errorf(
                        "[%s]: Only unpacked %d indices out of %d expected",
                        new_mesh.name,
                        indices_unpacked,
                        index_count,
                    )
                    return
                }

                // Add indices to temp array with vertex offset
                for i in 0 ..< index_count {
                    append(&indices_temp, index_buffer[i] + u32(initial_vtx))
                }
            }

            // Load vertex position data
            {
                // Find position attribute
                pos_accessor: ^cgltf.accessor
                for &attr in prim.attributes {
                    if attr.type == .position {
                        pos_accessor = attr.data
                        break
                    }
                }

                if pos_accessor == nil {
                    log.warn("Mesh has no position attribute")
                    continue // Skip this primitive
                }

                vertex_count := int(pos_accessor.count)

                // Expand vertices array
                old_len := len(vertices_temp)
                resize(&vertices_temp, old_len + vertex_count)

                // Initialize new vertices with defaults
                for &vtx in vertices_temp {
                    vtx = {
                        normal = {1, 0, 0}, // Default normal points along X
                        color  = {1, 1, 1, 1}, // Default white
                        uv_x   = 0,
                        uv_y   = 0,
                    }
                }

                // Unpack position data
                positions := make([]f32, vertex_count * 3, ta)

                if vertices_unpacked := cgltf.accessor_unpack_floats(
                    pos_accessor,
                    raw_data(positions),
                    uint(vertex_count * 3),
                ); vertices_unpacked < uint(vertex_count) {
                    // Error if we didn't get all expected vertices
                    log.errorf(
                        "[%s]: Only unpacked %v vertices out of %v expected",
                        new_mesh.name,
                        vertices_unpacked,
                        vertex_count,
                    )
                    return
                }

                // Copy positions to vertex array
                for i := 0; i < vertex_count; i += 1 {
                    idx := i * 3
                    vertices_temp[initial_vtx + i].position = {
                        positions[idx],
                        positions[idx + 1],
                        positions[idx + 2],
                    }
                }
            }

            // Load vertex normals (optional)
            {
                normal_accessor: ^cgltf.accessor
                for &attr in prim.attributes {
                    if attr.type == .normal {
                        normal_accessor = attr.data
                        break
                    }
                }

                if normal_accessor != nil {
                    vertex_count := int(normal_accessor.count)
                    normals := make([]f32, vertex_count * 3)
                    defer delete(normals)

                    if normals_unpacked := cgltf.accessor_unpack_floats(
                        normal_accessor,
                        raw_data(normals),
                        uint(vertex_count * 3),
                    ); normals_unpacked < uint(vertex_count) {
                        log.errorf(
                            "[%s]: Only unpacked %v normals out of %v expected",
                            new_mesh.name,
                            normals_unpacked,
                            vertex_count,
                        )
                        return
                    }

                    for i := 0; i < vertex_count; i += 1 {
                        idx := i * 3
                        vertices_temp[initial_vtx + i].normal = {
                            normals[idx],
                            normals[idx + 1],
                            normals[idx + 2],
                        }
                    }
                }
            }

            // Load UV coordinates (optional, first set only)
            {
                uv_accessor: ^cgltf.accessor
                for &attr in prim.attributes {
                    if attr.type == .texcoord && attr.index == 0 {
                        uv_accessor = attr.data
                        break
                    }
                }

                if uv_accessor != nil {
                    vertex_count := int(uv_accessor.count)
                    uvs := make([]f32, vertex_count * 2)
                    defer delete(uvs)

                    if texcoords_unpacked := cgltf.accessor_unpack_floats(
                        uv_accessor,
                        raw_data(uvs),
                        uint(vertex_count * 2),
                    ); texcoords_unpacked < uint(vertex_count) {
                        log.errorf(
                            "]%s]: Only unpacked %v texcoords out of %v expected",
                            new_mesh.name,
                            texcoords_unpacked,
                            vertex_count,
                        )
                        return
                    }

                    for i := 0; i < vertex_count; i += 1 {
                        idx := i * 2
                        vertices_temp[initial_vtx + i].uv_x = uvs[idx]
                        vertices_temp[initial_vtx + i].uv_y = uvs[idx + 1]
                    }
                }
            }

            // Load vertex colors (optional, first set only)
            {
                color_accessor: ^cgltf.accessor
                for &attr in prim.attributes {
                    if attr.type == .color && attr.index == 0 {
                        color_accessor = attr.data
                        break
                    }
                }

                if color_accessor != nil {
                    vertex_count := int(color_accessor.count)
                    colors := make([]f32, vertex_count * 4)
                    defer delete(colors)

                    if colors_unpacked := cgltf.accessor_unpack_floats(
                        color_accessor,
                        raw_data(colors),
                        uint(vertex_count * 4),
                    ); colors_unpacked < uint(vertex_count) {
                        log.warnf(
                            "[%s]: Only unpacked %v colors out of %v expected",
                            new_mesh.name,
                            colors_unpacked,
                            vertex_count,
                        )
                    }

                    for i := 0; i < vertex_count; i += 1 {
                        idx := i * 4
                        vertices_temp[initial_vtx + i].color = {
                            colors[idx],
                            colors[idx + 1],
                            colors[idx + 2],
                            colors[idx + 3],
                        }
                    }
                }
            }

            // Add the completed surface to the mesh
            append(&new_mesh.surfaces, new_surface)
        }

        // Optional: Override vertex colors with normal visualization
        when OVERRIDE_VERTEX_COLORS {
            for &vtx in vertices_temp {
                vtx.color = {vtx.normal.x, vtx.normal.y, vtx.normal.z, 1.0}
            }
        }

        // Upload mesh data to GPU
        new_mesh.mesh_buffers = upload_mesh(engine, indices_temp[:], vertices_temp[:]) or_return

        // Add completed mesh to output list
        append(&meshes, new_mesh)
    }

    if len(meshes) == 0 {
        return
    }

    return meshes, true
}

// Destroys a single `Mesh_Asset` and frees all its resources.
destroy_mesh_asset :: proc(mesh: ^Mesh_Asset, allocator := context.allocator) {
    assert(mesh != nil, "Invalid 'Mesh_Asset'")
    context.allocator = allocator
    delete(mesh.name)
    delete(mesh.surfaces)
    free(mesh)
}

// Destroys all mesh assets in a list.
destroy_mesh_assets :: proc(meshes: ^Mesh_Asset_List, allocator := context.allocator) {
    context.allocator = allocator
    for &mesh in meshes {
        destroy_mesh_asset(mesh)
    }
    delete(meshes^)
}
```

We will only be supporting binary GLTF for this for now. So first we open and parse file with
`cgltf.parse_file`.

Next we will loop each mesh, copy the vertices and indices into temporary dynamic array, and
upload them as a mesh to the engine. We will be building a dynamic array of `Mesh_Asset` from
this.

As we iterate each primitive within a mesh, we loop the attributes to find the vertex data we
want. We also build the index buffer properly while appending the different primitives into the
vertex arrays. At the end, we call `upload_mesh` to create the final buffers, then we return the
mesh list.

With the `OVERRIDE_VERTEX_COLORS` as a compile time config, we override the vertex colors with the
vertex normals which is useful for debugging.

The position array is going to be there always, so we use that to initialize the `Vertex`
structures. For all the other attributes we need to do it checking that the data exists.

Lets draw them.

```odin
test_meshes: Mesh_Asset_List,
```

We begin by adding them to the `Engine` structure. Lets load them from
`engine_init_default_data()`.

```odin
self.test_meshes = load_gltf_meshes(self, "assets/basicmesh.glb") or_return
defer if !ok {
    destroy_mesh_assets(&self.test_meshes)
}
```

In the file provided, index `0` is a **cube**, index `1` is a **sphere**, and index `2` is a
blender **monkeyhead**. we will be drawing that last one, draw it right after drawing the
rectangle from before.

```odin
push_constants = GPU_Draw_Push_Constants {
    world_matrix  = la.MATRIX4F32_IDENTITY,
    vertex_buffer = self.test_meshes[2].mesh_buffers.vertex_buffer_address,
}

vk.CmdPushConstants(
    cmd,
    self.mesh_pipeline_layout,
    {.VERTEX},
    0,
    size_of(GPU_Draw_Push_Constants),
    &push_constants,
)
vk.CmdBindIndexBuffer(cmd, self.test_meshes[2].mesh_buffers.index_buffer.buffer, 0, .UINT32)

vk.CmdDrawIndexed(
    cmd,
    self.test_meshes[2].surfaces[0].count,
    1,
    self.test_meshes[2].surfaces[0].start_index,
    0,
    0,
)
```

You will see that the monkey head has colors. That because we have `OVERRIDE_VERTEX_COLORS` set
to `true`, which will store normal direction as colors. We dont have proper lighting in the
shaders, so if you toggle that off you will see that the monkey head is pure solid white.

Now we have the monkey head and its visible, but its also upside down. Lets fix up that matrix.

In GLTF, the axis are meant to be for **OpenGL**, which has the **Y up**. Vulkan has **Y
down**, so its flipped. We have 2 possibilities here. One would be to use negative viewport
height, which is supported and will flip the entire rendering, this would make it closer to
**DirectX**. On the other side, we can apply a flip that changes the objects as part of our
projection matrix. We will be doing that.

From the render code, lets give it a better matrix for rendering. Add this code right before
the push constants call that draws the mesh on `engine_draw_geometry().`

```odin
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

// Create view matrix - place camera at positive Z looking at origin
view := la.matrix4_translate_f32({0, 0, -5})

// Create infinite perspective projection matrix with REVERSED depth
projection := matrix4_perspective_reverse_z_f32(
    f32(la.to_radians(70.0)),
    f32(self.draw_extent.width) / f32(self.draw_extent.height),
    0.1,
    true, // Invert the Y direction to match OpenGL and glTF axis conventions
)

// Other code bellow ---

// Monkey - ensure matrix order matches shader expectations
push_constants := GPU_Draw_Push_Constants {
    world_matrix  = projection * view,
    vertex_buffer = self.test_meshes[2].mesh_buffers.vertex_buffer_address,
}
```

First we calculate the view matrix, which is from the camera, a translation matrix that moves
backwards will be fine for now.

For the projection matrix, we are doing a trick here. The near plane is set at `0.1`, but
instead of a traditional far plane, we’re crafting an **infinite depth** range with a
**reverse-Z** approach. This flips the usual depth mapping—placing the near plane at depth 1
and letting the far distance stretch toward 0—thanks to a tiny `epsilon` value (around 10⁻⁶)
that ensures precision without a cutoff. This is a technique that greatly increases the quality
of depth testing.

If you run the engine at this point, you will find that the monkey head is drawing a bit
glitched. We havent setup depth testing, so triangles of the back side of the head can render
on top of the front, creating a wrong image. Lets go and implement depth testing.

Begin by adding a new image into the `Engine` structure, by the side of the draw-image as they
will be paired together while rendering.

```odin
draw_image: Allocated_Image,
depth_image: Allocated_Image,
```

Now we will initialize it alongside the `draw_image`, in the `engine_init_swapchain` procedure.

```odin
engine_init_swapchain :: proc(self: ^Engine) -> (ok: bool) {
    // Other code above ---

    self.depth_image.image_format = .D32_SFLOAT
    self.depth_image.image_extent = draw_image_extent
    self.depth_image.allocator = self.vma_allocator
    self.depth_image.device = self.vk_device

    depth_image_usages := vk.ImageUsageFlags{.DEPTH_STENCIL_ATTACHMENT}

    dimg_info := image_create_info(
        self.depth_image.image_format,
        depth_image_usages,
        draw_image_extent,
    )

    // Allocate and create the image
    vk_check(
        vma.create_image(
            self.vma_allocator,
            dimg_info,
            rimg_allocinfo,
            &self.depth_image.image,
            &self.depth_image.allocation,
            nil,
        ),
    ) or_return
    defer if !ok {
        vma.destroy_image(self.vma_allocator, self.depth_image.image, nil)
    }

    // Build a image-view for the draw image to use for rendering
    dview_info := imageview_create_info(
        self.depth_image.image_format,
        self.depth_image.image,
        {.DEPTH},
    )

    vk_check(
        vk.CreateImageView(self.vk_device, &dview_info, nil, &self.depth_image.image_view),
    ) or_return
    defer if !ok {
        vk.DestroyImageView(self.vk_device, self.depth_image.image_view, nil)
    }

    // Add to deletion queues
    deletion_queue_push(&self.main_deletion_queue, &self.depth_image)

    return true
}
```

The depth image is initialized in the same way as the draw image, but we are giving it the
`DEPTH_STENCIL_ATTACHMENT` usage flag, and we are using `D32_SFLOAT` as depth format.

Make sure to also add the depth image into the deletion queue.

From the draw loop, we will transition the depth image from undefined into depth attachment
mode, In the same way we do with the draw image. This goes right before the
`engine_draw_geometry()` call.

```odin
transition_image(cmd, self.draw_image.image, .GENERAL, .COLOR_ATTACHMENT_OPTIMAL)
// Other code above ---
transition_image(cmd, self.depth_image.image, .UNDEFINED, .DEPTH_ATTACHMENT_OPTIMAL) // < here
```

Now we need to change the render pass begin info to use this depth attachment and clear it
correctly. Change this at the top of `engine_draw_geometry()`

```odin
color_attachment := attachment_info(self.draw_image.image_view, nil, .COLOR_ATTACHMENT_OPTIMAL)
// Other code above ---
depth_attachment := depth_attachment_info(
    self.depth_image.image_view,
    .DEPTH_ATTACHMENT_OPTIMAL,
)

render_info := rendering_info(self.draw_extent, &color_attachment, &depth_attachment)
```

We already left space for the depth attachment on the `rendering_info`, but we also do need to
set up the depth clear to its correct value. Lets look at the implementation of the
`depth_attachment_info`.

```odin
depth_attachment_info :: proc(
    view: vk.ImageView,
    layout: vk.ImageLayout = .COLOR_ATTACHMENT_OPTIMAL,
) -> vk.RenderingAttachmentInfo {
    depth_attachment := vk.RenderingAttachmentInfo {
        sType       = .RENDERING_ATTACHMENT_INFO,
        imageView   = view,
        imageLayout = layout,
        loadOp      = .CLEAR,
        storeOp     = .STORE,
    }
    depth_attachment.clearValue.depthStencil.depth = 0.0
    return depth_attachment
}
```

Its similar to what we had for color attachment, but we make the `loadOp` to be clear, and set
the depth value on the clear structure to `0.0f`. As explained above, we are going to use depth
`0` as the "far" value, and depth `1` as the near value.

The last thing is to enable depth testing as part of the pipeline. We made the depth option
when the pipeline builder was made, but left it disabled. Lets fill that now. Add this
procedure to PipelineBuilder.

```odin
pipeline_builder_enable_depth_test :: proc(
    self: ^Pipeline_Builder,
    depth_write_enable: bool,
    op: vk.CompareOp,
) {
    self.depth_stencil.depthTestEnable = true
    self.depth_stencil.depthWriteEnable = b32(depth_write_enable)
    self.depth_stencil.depthCompareOp = op
    self.depth_stencil.depthBoundsTestEnable = false
    self.depth_stencil.stencilTestEnable = false
    self.depth_stencil.front = {}
    self.depth_stencil.back = {}
    self.depth_stencil.minDepthBounds = 0.0
    self.depth_stencil.maxDepthBounds = 1.0
}
```

We will leave the stencil parts all off, but we will enable depth testing, and pass the depth
OP into the structure.

Now time to use it from the place where we build the pipelines. Change this part on
`engine_init_mesh_pipeline`.

```odin
// pipeline_builder_disable_depth_test(&builder)
pipeline_builder_enable_depth_test(&builder, true, .GREATER_OR_EQUAL)

// Connect the image format we will draw into, from draw image
pipeline_builder_set_color_attachment_format(&builder, self.draw_image.image_format)
pipeline_builder_set_depth_attachment_format(&builder, self.depth_image.image_format)
```

We call the `enable_depth_test` procedure from the builder, and we give it depth write, and as
operator `GREATER_OR_EQUAL`. As mentioned, because `0` is far and `1` is near, we will want to
only render the pixels if the current depth value is greater than the depth value on the depth
image.

Modify that `set_depth_format` call on the `engine_init_triangle_pipeline` procedure too. Even
if depth testing is disabled for a draw, we still need to set the format correctly for the
render pass to work without validation layer issues.

You can run the engine now, and the monkey head will be setup properly. The other draws with
the triangle and rectangle render behind it because we have no depth testing set for them so
they neither write or read from the depth attachment.

We need to add cleanup code for the new meshes we are creating, so we will destroy the buffers
of the mesh array in the cleanup procedure, before the main deletion queue flush.

```odin
for &mesh in self.test_meshes {
    destroy_buffer(&mesh.mesh_buffers.index_buffer)
    destroy_buffer(&mesh.mesh_buffers.vertex_buffer)
}
destroy_mesh_assets(&self.test_meshes)

deletion_queue_destroy(&self.main_deletion_queue)
```

Before continuing, remove the code with the rectangle mesh and the triangle in the background.
We will no longer need them. Delete `engine_init_triangle_pipeline` procedure, its objects, and
the creation of the rectangle mesh on `engine_init_default_data` plus its usages. On
`engine_draw_geometry`, move the viewport and scissor code so that its after the call to
`vk.CmdBindPipeline(cmd, .GRAPHICS, self.mesh_pipeline)`, as the call to binding the triangle
pipeline is now gone and those `vk.CmdSetViewport` and `vk.CmdSetScissor` calls need to be done
with a pipeline bound.

Next, we will setup transparent objects and blending.
