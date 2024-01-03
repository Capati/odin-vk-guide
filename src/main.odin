package main

// Core
import "core:fmt"
import "core:log"
import "core:mem"

main :: proc() {
	when ODIN_DEBUG {
		context.logger = log.create_console_logger(opt = {.Level, .Terminal_Color})
		defer log.destroy_console_logger(context.logger)

		track: mem.Tracking_Allocator
		mem.tracking_allocator_init(&track, context.allocator)
		context.allocator = mem.tracking_allocator(&track)
		defer mem.tracking_allocator_destroy(&track)

		defer {
			for _, leak in track.allocation_map {
				fmt.printf("%v leaked %v bytes\n", leak.location, leak.size)
			}
			for bad_free in track.bad_free_array {
				fmt.printf(
					"%v allocation %p was freed badly\n",
					bad_free.location,
					bad_free.memory,
				)
			}
		}
	}

	if err := engine_init(); err != nil do return

	engine_run()

	engine_cleanup()
}
