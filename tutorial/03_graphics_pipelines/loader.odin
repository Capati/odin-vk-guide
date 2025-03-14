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
