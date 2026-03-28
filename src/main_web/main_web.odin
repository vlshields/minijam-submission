package main_web

import "base:runtime"
import "core:c"
import "core:mem"
import game ".."

@(private = "file")
web_context: runtime.Context

@(export)
main_start :: proc "c" () {
	context = runtime.default_context()
	context.allocator = emscripten_allocator()
	runtime.init_global_temporary_allocator(1 * mem.Megabyte)
	context.logger = create_emscripten_logger()
	web_context = context
	game.init()
}

@(export)
main_update :: proc "c" () -> bool {
	context = web_context
	game.update()
	return game.should_run()
}

@(export)
main_end :: proc "c" () {
	context = web_context
	game.shutdown()
}

@(export)
web_window_size_changed :: proc "c" (w: c.int, h: c.int) {
	context = web_context
	game.parent_window_size_changed(int(w), int(h))
}

@(export)
web_set_mouse_pos :: proc "c" (x: c.int, y: c.int) {
	context = web_context
	game.set_web_mouse_pos(int(x), int(y))
}

@(export)
web_set_mouse_down :: proc "c" (down: c.int) {
	context = web_context
	game.set_web_mouse_down(down != 0)
}
