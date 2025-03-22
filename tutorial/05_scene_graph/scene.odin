package vk_guide

// Core
import la "core:math/linalg"

// Vendor
import vk "vendor:vulkan"

// Define sentinel values for indicating invalid node
NO_MESH :: max(u32)
NO_MATERIAL :: max(u32)
NO_NAME :: max(u32)

// Render object that holds drawing data.
Render_Object :: struct {
	index_count:           u32,
	first_index:           u32,
	index_buffer:          vk.Buffer,
	material:              u32, // Index into materials array
	transform:             la.Matrix4f32,
	vertex_buffer_address: vk.DeviceAddress,
}

// Define our base drawing context and renderable types.
Draw_Context :: struct {
	opaque_surfaces: [dynamic]Render_Object,
}

// Hierarchy component for scene nodes
Hierarchy :: struct {
	parent:       i32, // -1 means no parent
	first_child:  i32, // -1 means no children
	next_sibling: i32, // -1 means no next sibling
	last_sibling: i32, // -1 means no siblings, otherwise the last sibling for quick appending
	level:        i32, // Depth in the hierarchy, root = 0
}

// Scene container to store all node data in arrays
Scene :: struct {
	// Transform components
	local_transforms:  [dynamic]la.Matrix4f32,
	world_transforms:  [dynamic]la.Matrix4f32,

	// Hierarchy components
	hierarchy:         [dynamic]Hierarchy,

	// Mesh components (Node index -> Mesh index)
	mesh_for_node:     [dynamic]u32,

	// Material components (Node index -> Material index)
	material_for_node: [dynamic]u32,

	// Optional debug components
	name_for_node:     [dynamic]u32,
	node_names:        [dynamic]string,

	// Material instances
	materials:         [dynamic]Material_Instance,

	// Mesh assets
	meshes:            Mesh_Asset_List,
}

// Initialize a new scene.
scene_init :: proc(scene: ^Scene, allocator := context.allocator) {
	context.allocator = allocator
	scene.local_transforms = make([dynamic]la.Matrix4f32)
	scene.world_transforms = make([dynamic]la.Matrix4f32)
	scene.hierarchy = make([dynamic]Hierarchy)
	scene.mesh_for_node = make([dynamic]u32)
	scene.material_for_node = make([dynamic]u32)
	scene.name_for_node = make([dynamic]u32)
	scene.node_names = make([dynamic]string)
	scene.materials = make([dynamic]Material_Instance)
	scene.meshes = make([dynamic]Mesh_Asset)
}

// Free scene resources.
scene_destroy :: proc(scene: ^Scene, allocator := context.allocator) {
	context.allocator = allocator
	delete(scene.local_transforms)
	delete(scene.world_transforms)
	delete(scene.hierarchy)
	delete(scene.mesh_for_node)
	delete(scene.material_for_node)
	delete(scene.name_for_node)
	delete(scene.node_names)
	delete(scene.materials)
	delete(scene.meshes)
}

// Add a new node to the scene.
scene_add_node :: proc(scene: ^Scene, #any_int parent, level: i32) -> i32 {
	// Create new node ID
	node := i32(len(scene.hierarchy))

	// Add transform components with identity matrices
	append(&scene.local_transforms, la.MATRIX4F32_IDENTITY)
	append(&scene.world_transforms, la.MATRIX4F32_IDENTITY)

	// Add default associations
	append(&scene.name_for_node, NO_NAME)
	append(&scene.mesh_for_node, NO_MESH)
	append(&scene.material_for_node, NO_MATERIAL)

	// Add hierarchy component
	new_hierarchy := Hierarchy {
		parent       = parent,
		first_child  = -1,
		next_sibling = -1,
		last_sibling = -1,
		level        = level,
	}
	append(&scene.hierarchy, new_hierarchy)

	// If we have a parent, update the parent's hierarchy
	if parent > -1 {
		// Get the first child of the parent
		first_child := scene.hierarchy[parent].first_child

		if first_child == -1 {
			// This is the first child, update parent
			scene.hierarchy[parent].first_child = node
			scene.hierarchy[parent].last_sibling = node
		} else {
			// Add as a sibling to the existing children
			// Get the last sibling for O(1) insertion instead of traversing
			last_sibling := scene.hierarchy[first_child].last_sibling

			if last_sibling > -1 {
				scene.hierarchy[last_sibling].next_sibling = node
			} else {
				// Legacy fallback traversal method
				dest := first_child
				for scene.hierarchy[dest].next_sibling != -1 {
					dest = scene.hierarchy[dest].next_sibling
				}
				scene.hierarchy[dest].next_sibling = node
			}

			// Update the cached last sibling for future quick additions
			scene.hierarchy[first_child].last_sibling = node
		}
	}

	return node
}

// Add a mesh node to the scene.
scene_add_mesh_node :: proc(
	scene: ^Scene,
	#any_int parent: i32,
	#any_int mesh_index, material_index: u32,
	name: string = "",
) -> i32 {
	// Create a new node
	level := parent > -1 ? scene.hierarchy[parent].level + 1 : 0
	node := scene_add_node(scene, parent, level)

	// Associate the mesh with this node
	scene.mesh_for_node[node] = mesh_index

	// Associate the material with this node
	scene.material_for_node[node] = material_index

	// Add name if provided
	if len(name) > 0 {
		name_idx := append_and_get_idx(&scene.node_names, name)
		scene.name_for_node[u32(node)] = name_idx
	}

	return node
}

// Update all world transforms starting from a specific node.
update_transforms :: proc(scene: ^Scene, #any_int node_index: i32) {
	node := scene.hierarchy[node_index]
	parent := node.parent

	// Calculate world transform
	if parent > -1 {
		// Node has a parent, multiply with parent's world transform
		scene.world_transforms[node_index] = la.matrix_mul(
			scene.world_transforms[parent],
			scene.local_transforms[node_index],
		)
	} else {
		// Node is a root, world transform equals local transform
		scene.world_transforms[node_index] = scene.local_transforms[node_index]
	}

	// Recursively update all children
	child := node.first_child
	for child != -1 {
		update_transforms(scene, child)
		child = scene.hierarchy[child].next_sibling
	}
}

// Update all world transforms in the scene.
update_all_transforms :: proc(scene: ^Scene) {
	// Find all root nodes and update their hierarchies
	for &node, i in scene.hierarchy {
		if node.parent == -1 {
			// This is a root node
			update_transforms(scene, i)
		}
	}
}

// Draw a specific node and its children.
scene_draw_node :: proc(scene: ^Scene, #any_int node_index: i32, ctx: ^Draw_Context) {
	// Combine top matrix with node's world transform
	node_matrix := la.matrix_mul(
		scene.local_transforms[node_index],
		scene.world_transforms[node_index],
	)

	// Check if this node has a mesh
	if scene.mesh_for_node[node_index] != NO_MESH {
		mesh_index := scene.mesh_for_node[node_index]
		mesh := &scene.meshes[mesh_index]

		// Add render objects for each surface in the mesh
		for &surface in mesh.surfaces {
			// Get the material index from the node or use the surface's default
			material_index := surface.material_index
			if scene.material_for_node[node_index] != NO_MATERIAL {
				material_index = scene.material_for_node[node_index]
			}

			// Create render object with a valid material index
			def := Render_Object {
				index_count           = surface.count,
				first_index           = surface.start_index,
				index_buffer          = mesh.mesh_buffers.index_buffer.buffer,
				material              = material_index, // Direct material index
				transform             = node_matrix,
				vertex_buffer_address = mesh.mesh_buffers.vertex_buffer_address,
			}

			// Add to render context
			append(&ctx.opaque_surfaces, def)
		}
	}

	// Draw all children
	child := scene.hierarchy[node_index].first_child
	for child != -1 {
		scene_draw_node(scene, child, ctx)
		child = scene.hierarchy[child].next_sibling
	}
}

scene_get_node_name :: proc(self: ^Scene, #any_int node: i32) -> string {
	name_idx := self.name_for_node[u32(node)]
	if name_idx == NO_NAME {
		return ""
	}
	return self.node_names[name_idx]
}
