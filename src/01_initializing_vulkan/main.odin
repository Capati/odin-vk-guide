package vk_guide

// Core
import "core:log"
import "core:mem"

start :: proc() {
	engine := new(Engine)
	ensure(engine != nil, "Failed to allocate 'Engine' object")
	defer free(engine)

	if !engine_init(engine) {
		return
	}
	defer engine_cleanup(engine)

	engine_run(engine)
}

main :: proc() {
	when ODIN_DEBUG {
		context.logger = log.create_console_logger(opt = {.Level, .Terminal_Color})
		defer log.destroy_console_logger(context.logger)

		track: mem.Tracking_Allocator
		mem.tracking_allocator_init(&track, context.allocator)
		context.allocator = mem.tracking_allocator(&track)

		defer {
			if len(track.allocation_map) > 0 {
				log.errorf("=== %v allocations not freed: ===", len(track.allocation_map))
				for _, entry in track.allocation_map {
					log.debugf("%v bytes @ %v", entry.size, entry.location)
				}
			}
			if len(track.bad_free_array) > 0 {
				log.errorf("=== %v incorrect frees: ===", len(track.bad_free_array))
				for entry in track.bad_free_array {
					log.debugf("%p @ %v", entry.memory, entry.location)
				}
			}
			mem.tracking_allocator_destroy(&track)
		}
	}

	start()
}
