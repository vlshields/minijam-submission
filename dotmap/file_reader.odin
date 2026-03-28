#+build !wasm32
#+build !wasm64p32

package dotmap

import "core:fmt"
import "core:os"

parse_map_file :: proc(path: string) -> (Dot_Map, bool) {
	data, err := os.read_entire_file(path, context.allocator)
	if err != nil {
		fmt.eprintln("could not open file:", path)
		return {}, false
	}
	return parse_map(string(data))
}
