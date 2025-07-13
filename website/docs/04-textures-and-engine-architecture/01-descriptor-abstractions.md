---
sidebar_position: 1
sidebar_label: "Descriptor Abstractions"
---

# Descriptor Abstractions

Now that we are going to be growing the engine abstractions to support textures and
considerably increase the complexity, we are going to need better abstractions for the
descriptor sets.

In chapter 2, we already created 2 objects, the `Descriptor_Allocator` and
`Descriptor_Layout_Builder`. With the descriptor Allocator we have a basic way of abstracting a
single `vk..DescriptorPool` to allocate descriptors, and the LayoutBuilder abstracts creating
Descriptor Set Layouts.

## DescriptorAllocator 2

We are going to create a new version of the `Descriptor_Allocator`,
`Descriptor_Allocator_Growable`. The one we created before will just crash when the pool runs
out of space. This is fine for some cases where we know the amount of descriptors ahead of
time, but it wont work when we need to load meshes from arbitrary files and cant know ahead of
time how many descriptors we will need. This new structure will perform almost exactly the
same, except instead of handling a single pool, it handles a bunch of them. Whenever a pool
fails to allocate, we create a new one. When this allocator gets cleared, it clears all of its
pools. This way we can use 1 descriptor allocator and it will just grow as we need to.

:::warning[]

We will use fixed array with default maximums based on typical Vulkan implementations, These
values can be too much or not enough, but we can adjust them as needed.

:::

This is the implementation we will have in the `descriptors.odin`.

```odin title="descriptor.odin"
// Core
import sa "core:container/small_array"

MAX_POOLS :: #config(MAX_POOLS, 32)

Ratios :: sa.Small_Array(MAX_POOL_SIZES, Pool_Size_Ratio)
Full_Pools :: sa.Small_Array(MAX_POOLS, vk.DescriptorPool)
Ready_Pools :: sa.Small_Array(MAX_POOLS, vk.DescriptorPool)

Descriptor_Allocator_Growable :: struct {
    device:        vk.Device,
    ratios:        Ratios,
    full_pools:    Full_Pools,
    ready_pools:   Ready_Pools,
    sets_per_pool: u32,
}

descriptor_growable_init :: proc(
    self: ^Descriptor_Allocator_Growable,
    device: vk.Device,
    max_sets: u32,
    pool_ratios: []Pool_Size_Ratio,
) -> (
    ok: bool,
) {
    return
}

descriptor_growable_clear_pools :: proc(self: ^Descriptor_Allocator_Growable) -> (ok: bool) {
}

descriptor_growable_destroy_pools :: proc(self: Descriptor_Allocator_Growable) {
}

descriptor_growable_allocate :: proc(
    self: ^Descriptor_Allocator_Growable,
    layout: ^vk.DescriptorSetLayout,
    pNext: rawptr = nil,
) -> (
    ds: vk.DescriptorSet,
    ok: bool,
) {
    return
}

descriptor_growable_get_pool :: proc(
    self: ^Descriptor_Allocator_Growable,
) -> (
    pool: vk.DescriptorPool,
    ok: bool,
) {
    return
}

descriptor_growable_create_pool :: proc(
    self: ^Descriptor_Allocator_Growable,
    set_count: u32,
) -> (
    pool: vk.DescriptorPool,
    ok: bool,
) {
    return
}
```

This is very similar as in the other descriptor allocator. What has changed is that
now we need to store the array of pool size ratios (for when we reallocate the pools), how many
sets we allocate per pool, and 2 arrays. `full_pools` contains the pools we know we cant
allocate from anymore, and `ready_pools` contains the pools that can still be used, or the
freshly created ones.

The allocation logic will first grab a pool from `ready_pools`, and try to allocate from it. If
it succeeds, it will add the pool back into the `ready_pools` array. If it fails, it will put
the pool on the `full_pools` array, and try to get another pool to retry. The `get_pool`
procedure will pick up a pool from `ready_pools`, or create a new one.

Lets write the get_pool and create_pool procedures.

```odin
descriptor_growable_get_pool :: proc(
    self: ^Descriptor_Allocator_Growable,
) -> (
    pool: vk.DescriptorPool,
    ok: bool,
) {
    if sa.len(self.ready_pools) > 0 {
        // Pop from ready pools
        pool = sa.pop_back(&self.ready_pools)
    } else {
        // Need to create a new pool
        pool = descriptor_growable_create_pool(self, self.sets_per_pool) or_return

        // Grow pool size by 50% each time, with an upper limit
        self.sets_per_pool = u32(f32(self.sets_per_pool) * 1.5)
        // 4096 is the maximum number of descriptor sets per pool supported by most Vulkan
        // implementations. Using 4092 instead of 4096 for alignment/padding safety
        if self.sets_per_pool > 4092 {
            self.sets_per_pool = 4092
        }
    }
    return pool, true
}

descriptor_growable_create_pool :: proc(
    self: ^Descriptor_Allocator_Growable,
    set_count: u32,
) -> (
    pool: vk.DescriptorPool,
    ok: bool,
) {
    pool_sizes: [MAX_POOL_SIZES]vk.DescriptorPoolSize

    for i in 0 ..< sa.len(self.ratios) {
        ratio := sa.get_ptr(&self.ratios, i)
        pool_sizes[i] = vk.DescriptorPoolSize {
            type            = ratio.type,
            descriptorCount = u32(ratio.ratio) * set_count,
        }
    }

    pool_info := vk.DescriptorPoolCreateInfo {
        sType         = .DESCRIPTOR_POOL_CREATE_INFO,
        maxSets       = set_count,
        poolSizeCount = u32(sa.len(self.ratios)),
        pPoolSizes    = &pool_sizes[0],
    }

    vk_check(vk.CreateDescriptorPool(self.device, &pool_info, nil, &pool)) or_return

    return pool, true
}
```

On `get_pool`, when we create a new pool, we increase the `sets_per_pool`, to mimic something
like an array resize. Still, we will limit the max amount of sets per pool to `4092` to avoid it
growing too much. This max limit can be modified if you find it works better in your use cases.

An important detail on this procedure is that we are removing the pool from the `ready_pools`
array when grabbing it. This is so then we can add it back into that array or the other one
once a descriptor is allocated.

On the `create_pool` procedure, its the same we had in the other descriptor allocator.

Lets create the other procedures we need, `init()`, `clear_pools()`, and `destroy_pools()`.

```odin
descriptor_growable_init :: proc(
    self: ^Descriptor_Allocator_Growable,
    device: vk.Device,
    max_sets: u32,
    pool_ratios: []Pool_Size_Ratio,
) -> (
    ok: bool,
) {
    self.device = device

    sa.clear(&self.ratios)
    sa.clear(&self.full_pools)
    sa.clear(&self.ready_pools)

    for r in pool_ratios {
        sa.push_back(&self.ratios, r)
    }

    new_pool := descriptor_growable_create_pool(self, max_sets) or_return

    // Grow it next allocation
    self.sets_per_pool = u32(f32(max_sets) * 1.5)

    sa.push_back(&self.ready_pools, new_pool)

    return true
}

descriptor_growable_clear_pools :: proc(self: ^Descriptor_Allocator_Growable) -> (ok: bool) {
    // Reset ready pools
    for &pool in sa.slice(&self.ready_pools) {
        vk_check(vk.ResetDescriptorPool(self.device, pool, {})) or_return
    }

    // Reset full pools and move them to ready
    for &pool in sa.slice(&self.full_pools) {
        vk_check(vk.ResetDescriptorPool(self.device, pool, {})) or_return
        sa.push_back(&self.ready_pools, pool)
    }

    sa.clear(&self.full_pools)

    return true
}

descriptor_growable_destroy_pools :: proc(self: Descriptor_Allocator_Growable) {
    // Destroy ready pools
    for i in 0 ..< sa.len(self.ready_pools) {
        pool := sa.get(self.ready_pools, i)
        vk.DestroyDescriptorPool(self.device, pool, nil)
    }

    // Destroy full pools
    for i in 0 ..< sa.len(self.full_pools) {
        pool := sa.get(self.full_pools, i)
        vk.DestroyDescriptorPool(self.device, pool, nil)
    }
}
```

The init procedure just allocates the first descriptor pool, and adds it to the `ready_pools`
array.

Clearing the pools means going through all pools, and coping from `full_pools` array into the
`ready_pools` array.

Destroying loops over both lists and destroys everything to clear the entire allocator.

Last is the new `allocate` procedure.

```odin
descriptor_growable_allocate :: proc(
    self: ^Descriptor_Allocator_Growable,
    layout: ^vk.DescriptorSetLayout,
    pNext: rawptr = nil,
) -> (
    ds: vk.DescriptorSet,
    ok: bool,
) {
    // Get or create a pool to allocate from
    pool_to_use := descriptor_growable_get_pool(self) or_return

    alloc_info := vk.DescriptorSetAllocateInfo {
        pNext              = pNext,
        sType              = .DESCRIPTOR_SET_ALLOCATE_INFO,
        descriptorPool     = pool_to_use,
        descriptorSetCount = 1,
        pSetLayouts        = layout,
    }

    result := vk.AllocateDescriptorSets(self.device, &alloc_info, &ds)

    // Allocation failed. Try again
    if result == .ERROR_OUT_OF_POOL_MEMORY || result == .ERROR_FRAGMENTED_POOL {
        sa.push_back(&self.full_pools, pool_to_use)

        pool_to_use = descriptor_growable_get_pool(self) or_return
        alloc_info.descriptorPool = pool_to_use
        vk_check(vk.AllocateDescriptorSets(self.device, &alloc_info, &ds)) or_return
    }

    sa.push_back(&self.ready_pools, pool_to_use)

    return ds, true
}
```

We first grab a pool, then allocate from it, and if the allocation failed, we add it into the
`full_pools` array (as we know this pool is filled) and then try again. If the second time
fails too stuff is completely broken so it just error out and returns. Once we have allocated
with a pool, we add it back into the `ready_pools` array.

## Descriptor Writer

When we needed to create a descriptor set for our compute shader, we did the vulkan
`vk.UpdateDescriptorSets()` the manual way, but this is really annoying to deal with. So we are
going to abstract that too. In our writer, we are going to have a `write_image` and
`write_buffer` procedures to bind the data. Lets look at the struct declaration, also on the
`descriptors.odin` file.

```odin
MAX_IMAGE_INFOS :: #config(MAX_IMAGE_INFOS, 64)
MAX_BUFFER_INFOS :: #config(MAX_BUFFER_INFOS, 64)
MAX_WRITES :: #config(MAX_WRITES, 128)

Image_Infos :: sa.Small_Array(MAX_IMAGE_INFOS, vk.DescriptorImageInfo)
Buffer_Infos :: sa.Small_Array(MAX_BUFFER_INFOS, vk.DescriptorBufferInfo)
Writes :: sa.Small_Array(MAX_WRITES, vk.WriteDescriptorSet)

Descriptor_Writer :: struct {
    device:       vk.Device,
    image_infos:  Image_Infos,
    buffer_infos: Buffer_Infos,
    writes:       Writes,
}

descriptor_writer_init :: proc(self: ^Descriptor_Writer, device: vk.Device) {
    self.device = device
}

descriptor_writer_write_image :: proc(
    self: ^Descriptor_Writer,
    binding: int,
    image: vk.ImageView,
    sampler: vk.Sampler,
    layout: vk.ImageLayout,
    type: vk.DescriptorType,
    loc := #caller_location,
) -> bool {
    return
}

descriptor_writer_write_buffer :: proc(
    self: ^Descriptor_Writer,
    binding: int,
    buffer: vk.Buffer,
    size: vk.DeviceSize,
    offset: vk.DeviceSize,
    type: vk.DescriptorType,
    loc := #caller_location,
) -> bool {
    return
}

descriptor_writer_clear :: proc(self: ^Descriptor_Writer) {
}

descriptor_writer_update_set :: proc(
    self: ^Descriptor_Writer,
    set: vk.DescriptorSet,
    loc := #caller_location,
) {
}
```

Lets look at the definition of `vk.WriteDescriptorSet`.

```odin
WriteDescriptorSet :: struct {
    sType:            StructureType,
    pNext:            rawptr,
    dstSet:           DescriptorSet,
    dstBinding:       u32,
    dstArrayElement:  u32,
    descriptorCount:  u32,
    descriptorType:   DescriptorType,
    pImageInfo:       ^DescriptorImageInfo,
    pBufferInfo:      ^DescriptorBufferInfo,
    pTexelBufferView: ^BufferView,
}
```

We have target set, target binding element, and the actual buffer or image is done by pointer.
We need to keep the information on the `vk.DescriptorBufferInfo` and others in a way that the
pointers are stable, or a way to fix up those pointers when making the final
`WriteDescriptorSet` array.

Lets look at what the `write_buffer` procedure does.

```odin
descriptor_writer_write_buffer :: proc(
    self: ^Descriptor_Writer,
    binding: int,
    buffer: vk.Buffer,
    size: vk.DeviceSize,
    offset: vk.DeviceSize,
    type: vk.DescriptorType,
    loc := #caller_location,
) -> bool {
    assert(sa.space(self.buffer_infos) != 0, "No space left in buffer_infos array", loc)
    assert(sa.space(self.writes) != 0, "No space left in writes array", loc)

    // Add buffer info
    sa.push_back(
        &self.buffer_infos,
        vk.DescriptorBufferInfo{buffer = buffer, offset = offset, range = size},
    )

    info_ptr := sa.get_ptr(&self.buffer_infos, sa.len(self.buffer_infos) - 1)

    // Add write
    sa.push_back(
        &self.writes,
        vk.WriteDescriptorSet {
            sType           = .WRITE_DESCRIPTOR_SET,
            dstBinding      = u32(binding),
            dstSet          = 0, // Left empty for now until we need to write it
            descriptorCount = 1,
            descriptorType  = type,
            pBufferInfo     = info_ptr,
        },
    )

    return true
}
```

We have to fill a `vk.DescriptorBufferInfo` first, with the buffer itself, and then an offset and
range (size) for it.

Then, we have to setup the write itself. Its only 1 descriptor, at the given binding slot, with
the correct type, and a pointer to the `vk.DescriptorBufferInfo`.

The descriptor types that are allowed for a buffer are these.

```odin
// vk.DescriptorType
.UNIFORM_BUFFER
.STORAGE_BUFFER
.UNIFORM_BUFFER_DYNAMIC
.STORAGE_BUFFER_DYNAMIC
```

We already explained those types of buffers in the last chapter. When we want to bind one or
the other type into a shader, we set the correct type here. Remember that it needs to match the
usage when allocating the `vk.Buffer`.

For images, this is the other procedure.

```odin
descriptor_writer_write_image :: proc(
    self: ^Descriptor_Writer,
    binding: int,
    image: vk.ImageView,
    sampler: vk.Sampler,
    layout: vk.ImageLayout,
    type: vk.DescriptorType,
    loc := #caller_location,
) -> bool {
    assert(sa.space(self.image_infos) != 0, "No space left in image_infos array", loc)
    assert(sa.space(self.writes) != 0, "No space left in writes array", loc)

    // Add image info
    sa.push_back(
        &self.image_infos,
        vk.DescriptorImageInfo{sampler = sampler, imageView = image, imageLayout = layout},
    )

    info_ptr := sa.get_ptr(&self.image_infos, sa.len(self.image_infos) - 1)

    // Add write
    sa.push_back(
        &self.writes,
        vk.WriteDescriptorSet {
            sType           = .WRITE_DESCRIPTOR_SET,
            dstBinding      = u32(binding),
            dstSet          = 0, // Left empty for now until we need to write it
            descriptorCount = 1,
            descriptorType  = type,
            pImageInfo      = info_ptr,
        },
    )

    return true
}
```

Very similar to the buffer one, but we have a different Info type, using a
`vk.DescriptorImageInfo` instead. For that one, we need to give it a sampler, a image view, and
what layout the image uses. The layout is going to be almost always either
`SHADER_READ_ONLY_OPTIMAL`, the best layout to use for accessing textures in the shaders, or
`GENERAL` when we are using them from compute shaders and writing them.

The 3 parameters in the ImageInfo can be optional, depending on the specific `vk.DescriptorType`.

* `.SAMPLER` is JUST the sampler, so it does not need `ImageView` or layout to be set.
* `.SAMPLED_IMAGE` doesnt need the sampler set because its going to be accessed with different
  samplers within the shader, this descriptor type is just a pointer to the image.
* `.COMBINED_IMAGE_SAMPLER` needs everything set, as it holds the information for both the
  sampler, and the image it samples. This is a useful type because it means we only need 1
  descriptor binding to access the texture.
* `.STORAGE_IMAGE` was used back in chapter 2, it does not need sampler, and its used to allow
  compute shaders to directly access pixel data.

In both the `write_image` and `write_buffer` procedures, we are being overly generic. This is done
for simplicity, but if you want, you can add new ones like `write_sampler()` where it has
`SAMPLER` and sets imageview and layout to zero, and other similar abstractions.

With these done, we can perform the write itself.

```odin
descriptor_writer_clear :: proc(self: ^Descriptor_Writer) {
    sa.clear(&self.image_infos)
    sa.clear(&self.buffer_infos)
    sa.clear(&self.writes)
}

descriptor_writer_update_set :: proc(
    self: ^Descriptor_Writer,
    set: vk.DescriptorSet,
    loc := #caller_location,
) {
    assert(self.device != nil, "Invalid 'Device'", loc)

    for &write in sa.slice(&self.writes) {
        write.dstSet = set
    }

    if sa.len(self.writes) > 0 {
        vk.UpdateDescriptorSets(
            self.device,
            u32(sa.len(self.writes)),
            raw_data(sa.slice(&self.writes)),
            0,
            nil,
        )
    }
}
```

The `clear()` procedure resets everything. The `update_set` procedure takes a descriptor set,
connects that set to the array of writes, and then calls `vk.UpdateDescriptorSets` to write the
descriptor set to its new bindings.

Lets look at how this abstraction can be used to replace code we had before in the
`engine_init_descriptors` procedure.

Before:

```odin title="init.odin"
img_info := vk.DescriptorImageInfo {
    imageLayout = .GENERAL,
    imageView   = self.draw_image.image_view,
}

draw_image_write := vk.WriteDescriptorSet {
    sType           = .WRITE_DESCRIPTOR_SET,
    dstBinding      = 0,
    dstSet          = self.draw_image_descriptors,
    descriptorCount = 1,
    descriptorType  = .STORAGE_IMAGE,
    pImageInfo      = &img_info,
}

vk.UpdateDescriptorSets(self.vk_device, 1, &draw_image_write, 0, nil)
```

After:

```odin title="init.odin"
writer: Descriptor_Writer
descriptor_writer_init(&writer, self.vk_device)

descriptor_writer_write_image(
    &writer,
    binding = 0,
    image = self.draw_image.image_view,
    sampler = 0,
    layout = .GENERAL,
    type = .STORAGE_IMAGE,
)

descriptor_writer_update_set(&writer, self.draw_image_descriptors)
```

This abstraction will prove much more useful when we have more complex descriptor sets,
specially in combination with the allocator and the layout builder.

## Dynamic Descriptor Allocation

Lets start using the abstraction by using it to create a global scene data descriptor every
frame. This is the descriptor set that all of our draws will use. It will contain the camera
matrices so that we can do 3d rendering.

To allocate descriptor sets at runtime, we will hold one descriptor allocator in our
`Frame_Data` structure. This way it will work like with the deletion queue, where we flush the
resources and delete things as we begin the rendering of that frame. Resetting the whole
descriptor pool at once is a lot faster than trying to keep track of individual descriptor set
resource lifetimes.

We add it into `Frame_Data` struct.

```odin
Frame_Data :: struct {
    deletion_queue:    ^Deletion_Queue,
    // Other fields above ---
    frame_descriptors: Descriptor_Allocator_Growable,
}
```

Now, lets initialize it when we initialize the swapchain and create these structs. Add this at
the end of `engine_init_descriptors()`.

```odin
for &frame in self.frames {
    frame_sizes: Ratios
    sa.push_back(&frame_sizes, Pool_Size_Ratio{.STORAGE_IMAGE, 3})
    sa.push_back(&frame_sizes, Pool_Size_Ratio{.STORAGE_BUFFER, 3})
    sa.push_back(&frame_sizes, Pool_Size_Ratio{.UNIFORM_BUFFER, 3})
    sa.push_back(&frame_sizes, Pool_Size_Ratio{.COMBINED_IMAGE_SAMPLER, 4})

    descriptor_growable_init(
        &frame.frame_descriptors,
        self.vk_device,
        1000,
        sa.slice(&frame_sizes),
    )

    deletion_queue_push(&self.main_deletion_queue, &frame.frame_descriptors)
}
```

We also need to update the deletion queue:

```odin title="deletion_queue.odin"
Resource :: union {
    // Higher-level custom resources
    Descriptor_Allocator_Growable,
}

deletion_queue_flush :: proc(queue: ^Deletion_Queue) {
    #reverse for &resource in queue.resources {
        switch &res in resource {
        // Higher-level custom resources
        case Descriptor_Allocator_Growable:
            descriptor_growable_destroy_pools(res)
        }
    }
}
```

And now, we can clear these every frame when we flush the frame deletion queue. This goes at
the start of `engine_draw()`.

```odin title="drawing.odin"
// Wait until the gpu has finished rendering the last frame. Timeout of 1 second
vk_check(vk.WaitForFences(self.vk_device, 1, &frame.render_fence, true, 1e9)) or_return

deletion_queue_flush(&frame.deletion_queue)
descriptor_growable_clear_pools(&frame.frame_descriptors) // < new
```

Now that we can allocate descriptor sets dynamically, we will be allocating the buffer that
holds scene data and create its descriptor set.

Add a new structure that we will use for the uniform buffer of scene data. We will hold view
and projection matrix separated, and then premultiplied view-projection matrix. We also add
some vec4s for a very basic lighting model that we will be building next.

```odin title="engine.odin"
// Core
import la "core:math/linalg"

GPU_Scene_Data :: struct {
    view:               la.Matrix4x4f32,
    proj:               la.Matrix4x4f32,
    viewproj:           la.Matrix4x4f32,
    ambient_color:      la.Vector4f32,
    sunlight_direction: la.Vector4f32, // w for sun power
    sunlight_color:     la.Vector4f32,
}
```

Add a new descriptor Layout on the `Engine` structure.

```odin
Engine :: struct {
    // Scene
    scene_data:                       GPU_Scene_Data,
    gpu_scene_data_descriptor_layout: vk.DescriptorSetLayout,
}
```

Create the descriptor set layout as part of `engine_init_descriptors`. It will be a descriptor
set with a single uniform buffer binding. We use uniform buffer here instead of **SSBO**
because this is a small buffer. We arent using it through buffer device adress because we have
a single descriptor set for all objects so there isnt any overhead of managing it.

```odin
{
    builder: Descriptor_Layout_Builder
    descriptor_layout_builder_init(&builder, self.vk_device)
    descriptor_layout_builder_add_binding(&builder, 0, .UNIFORM_BUFFER)
    self.gpu_scene_data_descriptor_layout = descriptor_layout_builder_build(
        &builder,
        self.vk_device,
        {.VERTEX, .FRAGMENT},
    ) or_return
}
deletion_queue_push(&self.main_deletion_queue, self.gpu_scene_data_descriptor_layout)
```

Now, we will create this descriptor set every frame, inside the `engine_draw_geometry()`
procedure. We will also dynamically allocate the uniform buffer itself as a way to showcase how
you could do temporal per-frame data that is dynamically created. It would be better to hold
the buffers cached in our `Frame_Data` structure, but we will be doing it this way to show how.
There are cases with dynamic draws and passes where you might want to do it this way.

```odin
engine_draw_geometry :: proc(self: ^Engine, cmd: vk.CommandBuffer) -> (ok: bool) {
    // ...

    vk.CmdDrawIndexed(
        cmd,
        self.test_meshes[2].surfaces[0].count,
        1,
        self.test_meshes[2].surfaces[0].start_index,
        0,
        0,
    )

    // Other code above ---

    // Allocate a new uniform buffer for the scene data
    gpu_scene_data_buffer := create_buffer(
        self,
        size_of(GPU_Scene_Data),
        {.UNIFORM_BUFFER},
        .Cpu_To_Gpu,
    ) or_return

    // Add it to the deletion queue of this frame so it gets deleted once its been used
    frame := engine_get_current_frame(self)
    deletion_queue_push(&frame.deletion_queue, &gpu_scene_data_buffer)

    // Write the buffer
    scene_uniform_data := cast(^GPU_Scene_Data)gpu_scene_data_buffer.info.mapped_data
    scene_uniform_data^ = self.scene_data

    // Create a descriptor set that binds that buffer and update it
    global_descriptor := descriptor_growable_allocate(
        &frame.frame_descriptors,
        &self.gpu_scene_data_descriptor_layout,
    ) or_return

    writer: Descriptor_Writer
    descriptor_writer_init(&writer, self.vk_device)
    descriptor_writer_write_buffer(
        &writer,
        binding = 0,
        buffer = gpu_scene_data_buffer.buffer,
        size = size_of(GPU_Scene_Data),
        offset = 0,
        type = .UNIFORM_BUFFER,
    )
    descriptor_writer_update_set(&writer, global_descriptor)

    vk.CmdEndRendering(cmd)

    return true
}
```

First we allocate the uniform buffer using the `Cpu_To_Gpu` memory usage so that its a memory
type that the cpu can write and gpu can read. This might be done on CPU RAM, but because its a
small amount of data, the gpu is going to have no problem loading it into its caches. We can
skip the logic with the staging buffer upload to dedicated gpu memory for cases like this.

Then we add it into the destruction queue of the current frame. This will destroy the buffer
after the next frame is rendered, so it gives enough time for the GPU to be done accessing it.
All of the resources we dynamically created for a single frame must go here for deletion.

To allocate the descriptor set we allocate it from the `frame_descriptors`. That pool gets
destroyed every frame, so same as with the deletion queue, it will be deleted automatically
when the gpu is done with it 2 frames later.

Then we write the new buffer into the descriptor set. Now we have the `global_descriptor` ready
to be used for drawing. We aren't using the scene-data buffer right now, but it will be
necessary later.

Before we continue with drawing, lets set up textures.
