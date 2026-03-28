#+build wasm32, wasm64p32

package game

import "base:runtime"
import "core:c"
import "core:log"
import "core:strings"

@(default_calling_convention = "c")
foreign {
	fopen :: proc(filename, mode: cstring) -> ^FILE ---
	fseek :: proc(stream: ^FILE, offset: c.long, whence: Whence) -> c.int ---
	ftell :: proc(stream: ^FILE) -> c.long ---
	fclose :: proc(stream: ^FILE) -> c.int ---
	fread :: proc(ptr: rawptr, size: c.size_t, nmemb: c.size_t, stream: ^FILE) -> c.size_t ---
}

@(private = "file")
FILE :: struct {}

Whence :: enum c.int {
	SET,
	CUR,
	END,
}

_read_entire_file :: proc(name: string, allocator := context.allocator, loc := #caller_location) -> (data: []byte, success: bool) {
	if name == "" {
		log.error("No file name provided")
		return
	}

	file := fopen(strings.clone_to_cstring(name, context.temp_allocator), "rb")

	if file == nil {
		log.errorf("Failed to open file %v", name)
		return
	}

	defer fclose(file)

	fseek(file, 0, .END)
	size := ftell(file)
	fseek(file, 0, .SET)

	if size <= 0 {
		log.errorf("Failed to read file %v", name)
		return
	}

	data_err: runtime.Allocator_Error
	data, data_err = make([]byte, size, allocator, loc)

	if data_err != nil {
		log.errorf("Error allocating memory: %v", data_err)
		return
	}

	read_size := fread(raw_data(data), 1, c.size_t(size), file)

	if read_size != c.size_t(size) {
		log.warnf("File %v partially loaded (%i bytes out of %i)", name, read_size, size)
	}

	log.debugf("Successfully loaded %v", name)
	return data, true
}
