package dotmap

import "core:fmt"
import "core:strings"

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

Cell :: struct {
	symbol:     u8,
	tile_index: int,
	collected:  bool,
}

Tile_Def :: struct {
	symbol:      u8,
	tiles:       [dynamic]string,
	passable:    bool,
	collectable: bool,
	other:       string,
	condition:   string,
	to_room:     string,
}

Dot_Map :: struct {
	grid:     [dynamic][dynamic]Cell,
	height:   int,
	width:    int,
	metadata: map[u8]Tile_Def,
}

Parser :: struct {
	src:  string,
	pos:  int,
	line: int,
	col:  int,
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

parse_map :: proc(source: string) -> (Dot_Map, bool) {
	p := Parser{src = source, pos = 0, line = 1, col = 1}

	result: Dot_Map
	result.metadata = make(map[u8]Tile_Def)

	// ---- MAP_START … MAP_END ------------------------------------------------
	skip_whitespace(&p)
	if !expect_token(&p, "MAP_START") {
		fmt.eprintln("expected MAP_START")
		return {}, false
	}
	skip_to_next_line(&p)

	max_cols := 0
	for {
		skip_leading_spaces(&p)
		if starts_with_token(&p, "MAP_END") {
			advance_n(&p, len("MAP_END"))
			break
		}
		row := make([dynamic]Cell)
		for !at_eol(&p) && !at_end(&p) {
			append(&row, Cell{symbol = p.src[p.pos]})
			advance(&p)
		}
		if len(row) > max_cols {
			max_cols = len(row)
		}
		append(&result.grid, row)
		skip_to_next_line(&p)
	}
	result.height = len(result.grid)
	result.width = max_cols

	// ---- metadata { … } ----------------------------------------------------
	skip_whitespace(&p)
	if !expect_token(&p, "metadata") {
		fmt.eprintln("expected 'metadata'")
		return {}, false
	}
	skip_whitespace(&p)
	if !expect_char(&p, '{') {
		fmt.eprintln("expected '{' after metadata")
		return {}, false
	}

	for {
		skip_whitespace(&p)
		if peek(&p) == '}' {
			advance(&p)
			break
		}
		if at_end(&p) {
			fmt.eprintln("unexpected end of file inside metadata block")
			return {}, false
		}

		// symbol character (single char like x, w, d …)
		sym := p.src[p.pos]
		advance(&p)
		if !expect_char_after_ws(&p, ':') {
			return {}, false
		}
		skip_whitespace(&p)
		if !expect_char(&p, '{') {
			return {}, false
		}

		td := Tile_Def{symbol = sym}

		// parse fields inside { }
		for {
			skip_whitespace(&p)
			if peek(&p) == '}' {
				advance(&p)
				break
			}
			field, fok := read_identifier(&p)
			if !fok {
				return {}, false
			}

			if !expect_char_after_ws(&p, ':') {
				return {}, false
			}
			skip_spaces(&p)

			switch field {
			case "tiles":
				td.tiles = parse_tiles_value(&p)
			case "passable":
				td.passable = parse_bool(&p)
			case "collectable":
				td.collectable = parse_bool(&p)
			case "other":
				td.other = parse_other_value(&p)
			case:
				// unknown field – skip value until comma/newline/}
				skip_value(&p)
			}

			// consume optional trailing comma
			skip_spaces(&p)
			if !at_end(&p) && peek(&p) == ',' {
				advance(&p)
			}
		}

		td.condition = extract_kv(td.other, "condition")
		td.to_room = extract_kv(td.other, "to_room")
		result.metadata[sym] = td
	}

	return result, true
}

destroy_map :: proc(m: ^Dot_Map) {
	for &row in m.grid {
		delete(row)
	}
	delete(m.grid)
	for _, &td in m.metadata {
		for &t in td.tiles {
			delete(t)
		}
		delete(td.tiles)
	}
	delete(m.metadata)
}

// ---------------------------------------------------------------------------
// Value parsers
// ---------------------------------------------------------------------------

parse_tiles_value :: proc(p: ^Parser) -> [dynamic]string {
	result := make([dynamic]string)
	skip_spaces(p)

	if peek(p) == '[' {
		// array of paths
		advance(p) // skip '['
		for {
			skip_whitespace(p)
			if peek(p) == ']' {
				advance(p)
				break
			}
			path := read_until_delim(p, {',', ']', '\n'})
			path = strings.trim_space(path)
			if len(path) > 0 && path != "nil" {
				append(&result, strings.clone(path))
			}
			skip_spaces(p)
			if peek(p) == ',' {
				advance(p)
			}
		}
	} else {
		// single path or nil
		val := read_until_delim(p, {',', '\n', '}'})
		val = strings.trim_space(val)
		if val != "nil" && len(val) > 0 {
			append(&result, strings.clone(val))
		}
	}

	return result
}

parse_bool :: proc(p: ^Parser) -> bool {
	skip_spaces(p)
	val := read_until_delim(p, {',', '\n', '}'})
	val = strings.trim_space(val)
	return val == "true"
}

extract_kv :: proc(s: string, key: string) -> string {
	if len(s) == 0 {
		return ""
	}
	parts := strings.split(s, ",")
	defer delete(parts)
	for part in parts {
		trimmed := strings.trim_space(part)
		eq := strings.index(trimmed, "=")
		if eq < 0 {
			continue
		}
		if trimmed[:eq] == key {
			return strings.clone(trimmed[eq + 1:])
		}
	}
	return ""
}

parse_other_value :: proc(p: ^Parser) -> string {
	skip_spaces(p)
	val := read_until_delim(p, {'\n', '}'})
	val = strings.trim_space(val)
	if val == "nil" || len(val) == 0 {
		return ""
	}
	return strings.clone(val)
}

// ---------------------------------------------------------------------------
// Low-level helpers
// ---------------------------------------------------------------------------

advance :: proc(p: ^Parser) {
	if p.pos >= len(p.src) {
		return
	}
	if p.src[p.pos] == '\n' {
		p.line += 1
		p.col = 1
	} else {
		p.col += 1
	}
	p.pos += 1
}

advance_n :: proc(p: ^Parser, n: int) {
	for _ in 0 ..< n {
		advance(p)
	}
}

at_end :: proc(p: ^Parser) -> bool {
	return p.pos >= len(p.src)
}

at_eol :: proc(p: ^Parser) -> bool {
	return at_end(p) || p.src[p.pos] == '\n' || p.src[p.pos] == '\r'
}

peek :: proc(p: ^Parser) -> u8 {
	if at_end(p) {
		return 0
	}
	return p.src[p.pos]
}

skip_whitespace :: proc(p: ^Parser) {
	for !at_end(p) {
		c := p.src[p.pos]
		if c == ' ' || c == '\t' || c == '\n' || c == '\r' {
			advance(p)
		} else {
			break
		}
	}
}

skip_spaces :: proc(p: ^Parser) {
	for !at_end(p) && (p.src[p.pos] == ' ' || p.src[p.pos] == '\t') {
		advance(p)
	}
}

skip_leading_spaces :: proc(p: ^Parser) {
	skip_spaces(p)
}

skip_to_next_line :: proc(p: ^Parser) {
	for !at_end(p) && p.src[p.pos] != '\n' {
		advance(p)
	}
	if !at_end(p) {
		advance(p) // consume '\n'
	}
}

skip_value :: proc(p: ^Parser) {
	for !at_end(p) && p.src[p.pos] != ',' && p.src[p.pos] != '\n' && p.src[p.pos] != '}' {
		advance(p)
	}
}

starts_with_token :: proc(p: ^Parser, token: string) -> bool {
	if p.pos + len(token) > len(p.src) {
		return false
	}
	return p.src[p.pos:][:len(token)] == token
}

expect_token :: proc(p: ^Parser, token: string) -> bool {
	if !starts_with_token(p, token) {
		return false
	}
	advance_n(p, len(token))
	return true
}

expect_char :: proc(p: ^Parser, c: u8) -> bool {
	if at_end(p) || p.src[p.pos] != c {
		return false
	}
	advance(p)
	return true
}

expect_char_after_ws :: proc(p: ^Parser, c: u8) -> bool {
	skip_whitespace(p)
	return expect_char(p, c)
}

read_identifier :: proc(p: ^Parser) -> (string, bool) {
	start := p.pos
	for !at_end(p) {
		c := p.src[p.pos]
		if (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_' || (c >= '0' && c <= '9') {
			advance(p)
		} else {
			break
		}
	}
	if p.pos == start {
		return "", false
	}
	return p.src[start:p.pos], true
}

read_until_delim :: proc(p: ^Parser, delims: []u8) -> string {
	start := p.pos
	outer: for !at_end(p) {
		for d in delims {
			if p.src[p.pos] == d {
				break outer
			}
		}
		advance(p)
	}
	return p.src[start:p.pos]
}
