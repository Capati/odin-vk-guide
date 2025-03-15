---
sidebar_position: 3
sidebar_label: "Mesh buffers"
---

# Mesh Buffers

To render objects properly, we need to send our vertex data to the vertex shader. Right now, we
are using a hardcoded array, but that will not work for anything other than a single triangle
or similar geometry.

As we arent using the fixed procedure vertex attribute fetch logic on the pipeline, we have
total freedom on how exactly do we load our vertex data in the shaders. We will be loading the
vertices from big gpu buffers passed through Buffer Device Adress, which gives high performance
and great flexibility.

## Vulkan Buffers

In vulkan, we can allocate general usage memory through buffers. They are different from images
in that they dont need samplers and act more as a typical cpu side structure or array. We can
access them in the shaders just as structures or array of structures.

When a buffer is created, we need to set the usage flags for it. We will be setting those as we
use them.

For the general read/write operations in the shaders, there are 2 types of buffers. **Uniform
Buffers** and **Storage Buffers**.

With uniform buffers (UBO), only a small amount can be accessed in the shader (vendor
dependant, 16 kilobytes guaranteed minimum) and the memory will be read-only. On the other
side, this offers the fastest access possible as the GPU might pre-cache it when loading the
pipeline. The size limit is only on the part that is bound to the shader. Its completely fine
to create a single big uniform buffer, and then bind to the shader only small sections of it.
Depending on the hardware, push-constants can be implemented as a type of uniform-buffer
handled by the driver.

Storage buffers (SSBO) are fully generic read-write buffers with very high size. Spec minimum
size is 128 megabytes, and the modern PC gpus we are targetting with this tutorial all have it
at 4 gigabits, and only because its what a `u32` size can hold. Storage buffers dont get
preloaded in the same way uniform buffers can, and are more "generic" data load/store.

Due to the small size of uniform buffers, we cant use them for vertex geometry. But they are
great for material parameters and global scene configuration.

The exact speed difference between uniform buffers and storage buffers depends on the specific
gpu and what the shader is doing, so its quite common to use storage buffers for almost
everything and take advantage of their greater flexibility, as the possible speed difference
might end up not mattering for the project.

In this benchmark, different ways of accessing buffers are compared [PerfTest][].

[PerfTest]: https://github.com/sebbbi/perftest

When creating the descriptors, its also possible to have them as **Dynamic** buffer. If you use
that, you can control the offset the buffer is bound to when writing the commands. This lets
you use 1 descriptor set for multiple objects draws, by storing the uniform data for multiple
objects into a big buffer, and then binding that descriptor at different offsets within that.
It works well for uniform buffers, but for storage buffers its better to go with
device-address.

## Buffer Device Address

Normally, buffers will need to be bound through descriptor sets, where we would bind 1 buffer
of a given type. This means we need to know the specific buffer dimensions from the CPU (for
uniform buffers) and need to deal with the lifetime of descriptor sets. For this project, as we
are targetting vulkan 1.3, we can take advantage of a different way of accessing buffers,
Buffer Device Adress. This essentially lets us send a `i64` pointer to the gpu (through
whatever way) and then access it in the shader, and its even allowed to do pointer math with
it. Its essentially the same mechanics as a Cpp pointer would have, with things like linked
lists and indirect accesses allowed.

We will be using this for our vertices because accessing a SSBO through device address is
faster than accessing it through descriptor sets, and we can send it through push constants for
a really fast and really easy way of binding the vertex data to the shaders.

## Immediate GPU Commands

In Vulkan, we typically execute GPU commands as part of a structured draw loop, where rendering
commands are recorded into a command buffer and submitted to the GPU in sync with the swapchain
and the overall rendering pipeline. However, there are scenarios—like performing copy
operations or other one-off tasks—where we need to issue commands to the GPU outside of this normal draw loop. This is
where immediate GPU commands come into play.

The need for immediate commands arises because certain operations, such as copying data between
buffers or from a buffer to an image, don’t depend on the rendering process or the swapchain’s
presentation timing. Forcing these operations to wait for the draw loop introduces unnecessary
synchronization overhead and complexity, especially when they’re one-off tasks or preparatory
steps that don’t need to align with frame rendering. In an engine, this flexibility is
critical, as we anticipate needing immediate command execution for various use cases beyond
just copy operations—think resource uploads, debug utilities, or asynchronous compute tasks.

To address this, we’re implementing an `engine_immediate_submit` procedure. This procedure
leverages a dedicated command buffer, separate from the one used for rendering, and employs a
fence for synchronization. Unlike the draw loop’s command buffer, which is tightly coupled to
swapchain presentation and rendering logic, this immediate command buffer allows us to send
commands to the GPU on-demand. The fence ensures that we can track when the GPU has completed
the work, without tying it to the swapchain or the rendering pipeline’s timing. This approach
avoids stalling the main render path and provides a clean, reusable mechanism for submitting
arbitrary GPU work whenever it’s needed.

To begin, lets add some fields into the `Engine` structure.

```odin
Engine :: struct {
    // Immediate submit
    imm_fence:          vk.Fence,
    imm_command_buffer: vk.CommandBuffer,
    imm_command_pool:   vk.CommandPool,
}
```

We have a fence and a command buffer with its pool.

We need to create those syncronization structures for immediate submit, so lets go into
`engine_init_commands()` procedure and hook the command part.

```odin
engine_init_commands :: proc(self: ^Engine) -> (ok: bool) {
    // Other code ---

    vk_check(
        vk.CreateCommandPool(self.vk_device, &command_pool_info, nil, &self.imm_command_pool),
    ) or_return

    // Allocate the command buffer for immediate submits
    cmd_alloc_info := command_buffer_allocate_info(self.imm_command_pool)
    vk_check(
        vk.AllocateCommandBuffers(self.vk_device, &cmd_alloc_info, &self.imm_command_buffer),
    ) or_return

    deletion_queue_push(&self.main_deletion_queue, self.imm_command_pool)

    return true
}
```

This is the same we were doing with the per-frame commands, but this time we are directly
putting it into the deletion queue for cleanup.

Now we need to create the fence, which we are going to add to `engine_init_sync_structures()`.
Add it to the end.

```odin
engine_init_sync_structures :: proc(self: ^Engine) -> (ok: bool) {
    // Other code ---

    vk_check(vk.CreateFence(self.vk_device, &fence_create_info, nil, &self.imm_fence)) or_return

    deletion_queue_push(&self.main_deletion_queue, self.imm_fence)

    return true
}
```

We will use the same `fence_create_info` we were using for the per-frame fences. Same as with
the commands, we are directly adding its destroy procedure to the deletion queue too.

Now implement the `engine_immediate_submit` procedure.

```odin
engine_immediate_submit :: proc(
    self: ^Engine,
    data: $T,
    fn: proc(engine: ^Engine, cmd: vk.CommandBuffer, data: T),
) -> (
    ok: bool,
) {
    vk_check(vk.ResetFences(self.vk_device, 1, &self.imm_fence)) or_return
    vk_check(vk.ResetCommandBuffer(self.imm_command_buffer, {})) or_return

    cmd := self.imm_command_buffer

    cmd_begin_info := command_buffer_begin_info({.ONE_TIME_SUBMIT})

    vk_check(vk.BeginCommandBuffer(cmd, &cmd_begin_info)) or_return

    fn(self, cmd, data)

    vk_check(vk.EndCommandBuffer(cmd)) or_return

    cmd_info := command_buffer_submit_info(cmd)
    submit_info := submit_info(&cmd_info, nil, nil)

    // Submit command buffer to the queue and execute it.
    //  `render_fence` will now block until the graphic commands finish execution
    vk_check(vk.QueueSubmit2(self.graphics_queue, 1, &submit_info, self.imm_fence)) or_return

    vk_check(vk.WaitForFences(self.vk_device, 1, &self.imm_fence, true, 9999999999)) or_return

    return true
}
```

Note how this procedure is very similar and almost the same as the way we are executing
commands on the gpu.

Here’s how it works: First, we reset the fence (`imm_fence`) and the immediate command buffer
(`imm_command_buffer`) to ensure they’re ready for use. We then begin the command buffer with
the `ONE_TIME_SUBMIT` flag, signaling that it’ll be used once and can be optimized accordingly
by the Vulkan driver. Next, we invoke the provided `fn` callback, passing the engine instance,
the command buffer, and the user-provided `data`, allowing the caller to record their desired
commands. After the callback completes, we end the command buffer and submit it to the graphics
queue using `vk.QueueSubmit2`, associating it with the `imm_fence` for synchronization.
Finally, we wait for the fence to signal completion with `vk.WaitForFences`, ensuring the GPU
has finished the work before proceeding.

Its close to the same thing, except we are not syncronizing the submit with the swapchain.

We will be using this procedure for data uploads and other “instant” operations outside of the
render loop. One way to improve it would be to run it on a different queue than the graphics
queue, and that way we could overlap the execution from this with the main render loop.

## Creating Buffers

Lets begin writing the code needed to upload a mesh to gpu. First we need a way to create
buffers.

Add this to `core.odin`.

```odin
Allocated_Buffer :: struct {
    buffer:     vk.Buffer,
    info:       vma.Allocation_Info,
    allocation: vma.Allocation,
    allocator:  vma.Allocator,
}
```

We will use this structure to hold the data for a given buffer. We have the `vk.Buffer` which
is the vulkan handle, and the `vma.Allocation` and `vma.AllocationInfo` which contains metadata
about the buffer and its allocation, needed to be able to free the buffer. We also store the
`vma.Allocator` for use on cleanup later.

Lets add a `create_buffer` procedure into `core.odin`. We will take an allocation size, the
usage flags, and the vma memory usage so that we can control where the buffer memory is.

This is the implementation.

```odin
create_buffer :: proc(
    self: ^Engine,
    alloc_size: vk.DeviceSize,
    usage: vk.BufferUsageFlags,
    memory_usage: vma.Memory_Usage,
) -> (
    new_buffer: Allocated_Buffer,
    ok: bool,
) {
    // allocate buffer
    buffer_info := vk.BufferCreateInfo {
        sType = .BUFFER_CREATE_INFO,
        size  = alloc_size,
        usage = usage,
    }

    vma_alloc_info := vma.Allocation_Create_Info {
        usage = memory_usage,
        flags = {.Mapped},
    }

    new_buffer.allocator = self.vma_allocator

    // allocate the buffer
    vk_check(
        vma.create_buffer(
            self.vma_allocator,
            buffer_info,
            vma_alloc_info,
            &new_buffer.buffer,
            &new_buffer.allocation,
            &new_buffer.info,
        ),
    ) or_return

    return new_buffer, true
}
```

First we need to fill the `vk.BuffercreateInfo` structure from vulkan. It takes a size and
usage flags. Then we create the `vma.Allocation_Create_Info` for the properties needed by
**VMA**. We can use the `Vma.Memory_Usage` flags to control where **VMA** will put our buffer.
With images, we were creating them in device local memory, which is the fastest memory possible
as its on GPU VRAM, but with buffers, we have to decide if we want them to be writeable from
cpu directly or not. These would be the main usages we can use.

* `Gpu_Only` Is for purely GPU-local memory. This memory wont be writeable or readable from CPU
  because its on GPU VRAM, but its the fastest to both read and write with shaders.
* `Cpu_Only` Is for memory that is on the CPU RAM. This is memory we can write to from CPU, but
  the GPU can still read from it. Keep in mind that because this is on CPU ram which is outside
  of the GPU, the accesses to this will come at a performance hit. It is still quite useful if
  we have data that changes every frame or small amounts of data where slower access wont
  matter.
* `Cpu_To_Gpu` Is also writeable from CPU, but might be faster to access from GPU. On vulkan
  1.2 and forwards, GPUs have a small memory region on their own VRAM that is still writeable
  from CPU. Its size is limited unless we use Resizable BAR, but its memory that is both
  cpu-writeable and fast to access in GPU.
* `Gpu_To_Cpu` Used on memory that we want to be safely readable from CPU.

We are using the allocation create flags `.MAPPED` on all our buffer allocations. This would
map the pointer automatically so we can write to the memory, as long as the buffer is accesible
from CPU. VMA will store that pointer as part of the allocationInfo.

With a create buffer procedure, we also need a destroy buffer procedure. The only thing we need
to do is to call `vma.destroy_buffer`.

```odin
destroy_buffer :: proc(self: ^Allocated_Buffer) {
    vma.destroy_buffer(self.allocator, self.buffer, self.allocation)
}
```

Lets update our deletion queue to handle the destruction of allocated buffers. Here is the
relevant code with other parts omitted:

```odin title="deletion_queue.odin"
Resource :: union {
    // Higher-level custom resources
    ^Allocated_Buffer,
}

deletion_queue_flush :: proc(queue: ^Deletion_Queue) {
    #reverse for &resource in queue.resources {
        switch &res in resource {
        // Higher-level custom resources
        case ^Allocated_Buffer:
            destroy_buffer(res)
        }
    }
}
```

With this we can create our mesh structure and setup the vertex buffer.

## Mesh Buffers On GPU

```odin title="core.odin"
import la "core:math/linalg"

Vertex :: struct {
    position: la.Vector3f32,
    uv_x:     f32,
    normal:   la.Vector3f32,
    uv_y:     f32,
    color:    la.Vector4f32,
}

// Holds the resources needed for a mesh
GPU_Mesh_Buffers :: struct {
    index_buffer:          Allocated_Buffer,
    vertex_buffer:         Allocated_Buffer,
    vertex_buffer_address: vk.DeviceAddress,
}

// Push constants for our mesh object draws
GPU_Draw_Push_Constants :: struct {
    world_matrix:  la.Matrix4f32,
    vertex_buffer: vk.DeviceAddress,
}
```

We need a vertex format, so lets use this one. when creating a vertex format its very important
to compact the data as much as possible, but for the current stage of the tutorial it wont
matter. We will optimize this vertex format later. The reason the uv parameters are interleaved
is due to alignement limitations on GPUs. We want this structure to match the shader version so
interleaving it like this improves it.

We store our mesh data into a `GPU_Mesh_Buffers` struct, which will contain the allocated
buffer for both indices and vertices, plus the buffer device adress for the vertices.

We will create a struct for the push-constants we want to draw the mesh, it will contain the
transform matrix for the object, and the device adress for the mesh buffer.

Now we need a procedure to create those buffers and fill them on the gpu.

```odin title="core.odin"
upload_mesh :: proc(
    self: ^Engine,
    indices: []u32,
    vertices: []Vertex,
) -> (
    new_surface: GPU_Mesh_Buffers,
    ok: bool,
) {
    vertex_buffer_size := vk.DeviceSize(len(vertices) * size_of(Vertex))
    index_buffer_size := vk.DeviceSize(len(indices) * size_of(u32))

    // Create vertex buffer
    new_surface.vertex_buffer = create_buffer(
        self,
        vertex_buffer_size,
        {.STORAGE_BUFFER, .TRANSFER_DST, .SHADER_DEVICE_ADDRESS},
        .Gpu_Only,
    ) or_return
    defer if !ok {
        destroy_buffer(&new_surface.vertex_buffer)
    }

    // Find the address of the vertex buffer
    device_address_info := vk.BufferDeviceAddressInfo {
        sType  = .BUFFER_DEVICE_ADDRESS_INFO,
        buffer = new_surface.vertex_buffer.buffer,
    }
    new_surface.vertex_buffer_address = vk.GetBufferDeviceAddress(
        self.vk_device,
        &device_address_info,
    )

    // Create index buffer
    new_surface.index_buffer = create_buffer(
        self,
        index_buffer_size,
        {.INDEX_BUFFER, .TRANSFER_DST},
        .Gpu_Only,
    ) or_return
    defer if !ok {
        destroy_buffer(&new_surface.index_buffer)
    }

    return new_surface, true
}
```

The procedure will take a slice of integers for its indices, and of `Vertex` for vertices.

First we do is to calculate how big the buffers need to be. Then, we create our buffers on
GPU-only memory.

 On the vertex buffer we use these Usage flags:

* `STORAGE_BUFFER` because its a SSBO, and
* `SHADER_DEVICE_ADDRESS` because will be taking its adress.

On the index buffer we use `INDEX_BUFFER` to signal that we are going to be using that buffer
for indexed draws.

We also have `TRANSFER_DST` on both buffers as we will be doing memory copy commands to them.

To take the buffer address, we need to call `vk.GetBufferDeviceAddress`, giving it the
`vk.Buffer` we want to do that on. Once we have the `vk.DeviceAddress`, we can do pointer math
with it if we want, which is useful if we are sub-allocating from a bigger buffer.

With the buffers allocated, we need to write the data into them. For that, we will be using a
staging buffer. This is a very common pattern with vulkan. As `GPU_ONLY` memory cant be written
on CPU, we first write the memory on a temporal staging buffer that is CPU writeable, and then
execute a copy command to copy this buffer into the GPU buffers. Its not necesary for meshes to
use `GPU_ONLY` vertex buffers, but its highly recommended unless its something like a CPU side
particle system or other dynamic effects.

```odin title="core.odin"
upload_mesh :: proc(
    self: ^Engine,
    indices: []u32,
    vertices: []Vertex,
) -> (
    new_surface: GPU_Mesh_Buffers,
    ok: bool,
) {
    // Other code ---

    staging := create_buffer(
        self,
        vertex_buffer_size + index_buffer_size,
        {.TRANSFER_SRC},
        .Cpu_Only,
    ) or_return
    defer destroy_buffer(&staging)

    data := staging.info.mapped_data
    // Copy vertex buffer
    intr.mem_copy(data, raw_data(vertices), vertex_buffer_size)
    // Copy index buffer
    intr.mem_copy(
        rawptr(uintptr(data) + uintptr(vertex_buffer_size)),
        raw_data(indices),
        index_buffer_size,
    )

    // Create a struct to hold all the copy parameters
    Copy_Data :: struct {
        staging_buffer:     vk.Buffer,
        vertex_buffer:      vk.Buffer,
        index_buffer:       vk.Buffer,
        vertex_buffer_size: vk.DeviceSize,
        index_buffer_size:  vk.DeviceSize,
    }

    // Prepare the data structure
    copy_data := Copy_Data {
        staging_buffer     = staging.buffer,
        vertex_buffer      = new_surface.vertex_buffer.buffer,
        index_buffer       = new_surface.index_buffer.buffer,
        vertex_buffer_size = vertex_buffer_size,
        index_buffer_size  = index_buffer_size,
    }

    // Call the immediate submit with our data and procedure
    engine_immediate_submit(
        self,
        copy_data,
        proc(engine: ^Engine, cmd: vk.CommandBuffer, data: Copy_Data) {
            // Setup vertex buffer copy
            vertex_copy := vk.BufferCopy {
                srcOffset = 0,
                dstOffset = 0,
                size      = data.vertex_buffer_size,
            }

            // Copy vertex data from staging to the new surface vertex buffer
            vk.CmdCopyBuffer(cmd, data.staging_buffer, data.vertex_buffer, 1, &vertex_copy)

            // Setup index buffer copy
            index_copy := vk.BufferCopy {
                srcOffset = data.vertex_buffer_size,
                dstOffset = 0,
                size      = data.index_buffer_size,
            }

            // Copy index data from staging to the new surface index buffer
            vk.CmdCopyBuffer(cmd, data.staging_buffer, data.index_buffer, 1, &index_copy)
        },
    )

    return new_surface, true
}
```

In the `upload_mesh` procedure, we begin by creating a **staging buffer**, a single temporary
buffer used to facilitate data transfer for both the vertex and index buffers. This buffer is
sized to accommodate the combined data of the vertex buffer (`vertex_buffer_size`) and the
index buffer (`index_buffer_size`). We configure it with the `{.TRANSFER_SRC}` usage flag,
indicating that its sole purpose is to serve as the source for a data transfer operation.
Additionally, we set its memory type to `.Cpu_Only`, ensuring that it is accessible for CPU
writes, which is critical for the subsequent steps.

After creating the staging buffer, we retrieve a pointer to its mapped memory via
`staging.info.mapped_data`. This raw pointer (`rawptr`) allows direct CPU access to the
buffer’s memory, a capability enabled by the `{.Mapped}` flag used during allocation. Using
this pointer, we perform two memory copy operations with `intr.mem_copy`:

1. The vertex data (`vertices`) is copied into the staging buffer starting at offset 0.
2. The index data (`indices`) is copied immediately following the vertex data, at an offset
   equal to `vertex_buffer_size`. This layout ensures both datasets are sequentially packed
   into the staging buffer.

With the staging buffer now populated, we prepare to transfer this data to the GPU. To do this
efficiently, we define a `Copy_Data` struct that encapsulates all necessary parameters for the
transfer: the staging buffer, the target vertex and index buffers (stored in `new_surface`),
and their respective sizes. This struct is passed to `engine_immediate_submit`, a utility
procedure that executes a command on the GPU immediately.

Inside the submission callback, we define the GPU-side transfer logic:

* For the vertex buffer, we create a `vk.BufferCopy` structure specifying a source offset of 0
  (where the vertex data begins in the staging buffer), a destination offset of 0 (the start of
  the vertex buffer), and the size of the vertex data. We then issue a `vk.CmdCopyBuffer`
  command to copy this data from the staging buffer to the `new_surface.vertex_buffer`.
* For the index buffer, we create another `vk.BufferCopy` structure. Here, the source offset is
  set to `vertex_buffer_size` (where the index data begins in the staging buffer), the
  destination offset is 0 (the start of the index buffer), and the size matches the index data.
  A second `vk.CmdCopyBuffer` command transfers this data to `new_surface.index_buffer`.

These `vk.CmdCopyBuffer` operations are GPU-accelerated equivalents of the earlier
`intr.mem_copy` calls, but they move data from the staging buffer to the final GPU buffers
instead of from CPU memory to the staging buffer. The `vk.BufferCopy` structures directly
mirror the offsets and sizes used in the CPU-side copies, ensuring a seamless handoff.

Once the `engine_immediate_submit` completes, the staging buffer’s role is finished, so we
destroy it using `destroy_buffer`, leveraging the `defer` statement to ensure cleanup occurs
automatically before the procedure returns.

:::warning[]

Note that this pattern is not very efficient, as we are waiting for the GPU command to fully
execute before continuing with our CPU side logic. This is something people generally put on a
background thread, whose sole job is to execute uploads like this one, and deleting/reusing the
staging buffers.

:::

## Drawing a Mesh

Lets proceed with making a mesh using all this, and draw it. We will be drawing a indexed
rectangle, to combine with our triangle.

The shader needs to change for our vertex buffer, so while we are still going to be using
`colored_triangle.frag` for our fragment shader, we will change the vertex shader to load the
data from the push-constants. We will create that shader as `colored_triangle_mesh.vert`, as it
will be the same as the hardcoded triangle.

```glsl
#version 450
#extension GL_EXT_buffer_reference : require

layout(location = 0) out vec3 outColor;
layout(location = 1) out vec2 outUV;

struct Vertex {

    vec3 position;
    float uv_x;
    vec3 normal;
    float uv_y;
    vec4 color;
};

layout(buffer_reference, std430) readonly buffer VertexBuffer {
    Vertex vertices[];
};

// push constants block
layout(push_constant) uniform constants {
    mat4 render_matrix;
    VertexBuffer vertexBuffer;
} PushConstants;

void main() {
    // load vertex data from device adress
    Vertex v = PushConstants.vertexBuffer.vertices[gl_VertexIndex];

    // output data
    gl_Position = PushConstants.render_matrix * vec4(v.position, 1.0f);
    outColor = v.color.xyz;
    outUV.x = v.uv_x;
    outUV.y = v.uv_y;
}
```

We need to enable the `GL_EXT_buffer_reference` extension so that the shader compiler knows how
to handle these buffer references.

Then we have the `Vertex` struct, which is the exact same one as the one we have on CPU.

After that, we declare the `VertexBuffer`, which is a readonly buffer that has an array (unsized)
of `Vertex` structures. by having the `buffer_reference` in the layout, that tells the shader
that this object is used from buffer adress. `std430` is the alignement rules for the
structure.

We have our `push_constant` block which holds a single instance of our `VertexBuffer`, and a
matrix. Because the vertex buffer is declared as `buffer_reference`, this is a `uint64` handle,
while the matrix is a normal matrix (no references).

From our `main()`, we index the vertex array using `gl_VertexIndex`, same as we did with the
hardcoded array. We dont have -> like in cpp when accessing pointers, in GLSL buffer address is
accessed as a reference so it uses `.` to access it. With the vertex grabbed, we just output
the color and position we want, multiplying the position with the render matrix.

Lets create the pipeline now. We will create a new pipeline procedure, separate from
`engine_init_triangle_pipeline()` but almost the same.

Add this to `Engine` structure.

```odin
Engine :: struct {
    mesh_pipeline_layout: vk.PipelineLayout,
    mesh_pipeline:        vk.Pipeline,
    rectangle:            GPU_Mesh_Buffers,
}
```

Lets add the `engine_init_mesh_pipeline`, its going to be mostly a copypaste of
`engine_init_triangle_pipeline()`.

```odin
engine_init_mesh_pipeline :: proc(self: ^Engine) -> (ok: bool) {
    triangle_frag_shader := create_shader_module(
        self.vk_device,
        #load("./../../shaders/compiled/colored_triangle.frag.spv"),
    ) or_return
    defer vk.DestroyShaderModule(self.vk_device, triangle_frag_shader, nil)

    triangle_vertex_shader := create_shader_module(
        self.vk_device,
        #load("./../../shaders/compiled/colored_triangle_mesh.vert.spv"),
    ) or_return
    defer vk.DestroyShaderModule(self.vk_device, triangle_vertex_shader, nil)

    buffer_range := vk.PushConstantRange {
        offset     = 0,
        size       = size_of(GPU_Draw_Push_Constants),
        stageFlags = {.VERTEX},
    }

    pipeline_layout_info := pipeline_layout_create_info()
    pipeline_layout_info.pPushConstantRanges = &buffer_range
    pipeline_layout_info.pushConstantRangeCount = 1

    vk_check(
        vk.CreatePipelineLayout(
            self.vk_device,
            &pipeline_layout_info,
            nil,
            &self.triangle_pipeline_layout,
        ),
    ) or_return
    deletion_queue_push(&self.main_deletion_queue, self.triangle_pipeline_layout)

    return true
}
```

We change the vertex shader to load `colored_triangle_mesh.vert.spv`, and we modify the
pipeline layout to give it the push constants struct we defined above.

For the rest of the procedure, we do the same as in the triangle pipeline procedure, but
changing the pipeline layout and the pipeline name to be the new ones.

```odin
engine_init_mesh_pipeline :: proc(self: ^Engine) -> (ok: bool) {
    // Other code ---

    builder := pipeline_builder_create_default()

    // Use the triangle layout we created
    builder.pipeline_layout = self.mesh_pipeline_layout
    // Add the vertex and pixel shaders to the pipeline
    pipeline_builder_set_shaders(&builder, triangle_vertex_shader, triangle_frag_shader)
    // It will draw triangles
    pipeline_builder_set_input_topology(&builder, .TRIANGLE_LIST)
    // Filled triangles
    pipeline_builder_set_polygon_mode(&builder, .FILL)
    // No backface culling
    pipeline_builder_set_cull_mode(&builder, vk.CullModeFlags_NONE, .CLOCKWISE)
    // No multisampling
    pipeline_builder_set_multisampling_none(&builder)
    // No blending
    pipeline_builder_disable_blending(&builder)
    // No depth testing
    pipeline_builder_disable_depth_test(&builder)

    // Connect the image format we will draw into, from draw image
    pipeline_builder_set_color_attachment_format(&builder, self.draw_image.image_format)
    pipeline_builder_set_depth_attachment_format(&builder, .UNDEFINED)

    // Finally build the pipeline
    self.mesh_pipeline = pipeline_builder_build(&builder, self.vk_device) or_return
    deletion_queue_push(&self.main_deletion_queue, self.mesh_pipeline)

    return true
}
```

Now we call this procedure from our main `engine_init_pipelines()` procedure.

```odin
engine_init_pipelines :: proc(self: ^Engine) -> (ok: bool) {
    // Compute pipelines
    engine_init_background_pipeline(self) or_return

    // Graphics pipelines
    engine_init_triangle_pipeline(self) or_return
    engine_init_mesh_pipeline(self) or_return

    return true
}
```

Next we need to create and upload the mesh. We create a new initialization procedure,
`engine_init_default_data()` for our default data in the engine. Add it into the main
`engine_init()` procedure, at the end.

```odin
engine_init_default_data :: proc(self: ^Engine) -> (ok: bool) {
    // odinfmt: disable
    rect_vertices := [4]Vertex {
        { position = {0.5,-0.5, 0},  color = { 0,0, 0.0, 1.0 }},
        { position = {0.5,0.5, 0},   color = { 0.5, 0.5, 0.5 ,1.0 }},
        { position = {-0.5,-0.5, 0}, color = { 1,0, 0.0, 1.0 }},
        { position = {-0.5,0.5, 0},  color = { 0.0, 1.0, 0.0, 1.0 }},
    }

    rect_indices := [6]u32 {
        0, 1, 2,
        2, 1, 3,
    }
    // odinfmt: enable

    rectangle := upload_mesh(self, rect_indices[:], rect_vertices[:]) or_return

    // Delete the rectangle data on engine shutdown
    deletion_queue_push(&self.main_deletion_queue, &rectangle.index_buffer)
    deletion_queue_push(&self.main_deletion_queue, &rectangle.vertex_buffer)

    return true
}
```

We create 2 arrays for vertices and indices, and call the `upload_mesh` procedure to convert it
all into buffers.

We can now execute the draw. We will add the new draw command on `engine_draw_geometry()`
procedure, after the triangle we had.

```odin
engine_draw_geometry :: proc(self: ^Engine, cmd: vk.CommandBuffer) -> (ok: bool) {
    // Launch a draw command to draw 3 vertices
    vk.CmdDraw(cmd, 3, 1, 0, 0)

    // Other code above ---

    vk.CmdBindPipeline(cmd, .GRAPHICS, self.mesh_pipeline)

    push_constants := GPU_Draw_Push_Constants {
        world_matrix  = la.MATRIX4F32_IDENTITY, // import la "core:math/linalg"
        vertex_buffer = self.rectangle.vertex_buffer_address,
    }

    vk.CmdPushConstants(
        cmd,
        self.mesh_pipeline_layout,
        {.VERTEX},
        0,
        size_of(GPU_Draw_Push_Constants),
        &push_constants,
    )
    vk.CmdBindIndexBuffer(cmd, self.rectangle.index_buffer.buffer, 0, .UINT32)

    vk.CmdDrawIndexed(cmd, 6, 1, 0, 0, 0)

    // Other code bellow ---

    vk.CmdEndRendering(cmd)

    return true
}
```

We bind another pipeline, this time the rectangle mesh one.

Then, we use push-constants to upload the vertex buffer address to the gpu. For the matrix, we
will be defaulting it for now until we implement mesh transformations.

We then need to do a `vk.CmdBindPipeline` to bind the index buffer for graphics. Sadly there is
no way of using device adress here, and you need to give it the `vk.Buffer` and offsets.

Last, we use `vkCmdDrawIndexed` to draw 2 triangles (6 indices). This is the same as the
`vk.CmdDraw`, but it uses the currently bound index buffer to draw meshes.

Thats all, we now have a generic way of rendering any mesh.

Next we will load mesh files from a **GLTF** in the most basic way so we can play around with
fancier things than a rectangle.
