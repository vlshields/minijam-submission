package game

import "vendor:raylib"

DOOR_FRAMES   :: 5
DOOR_FPS      :: 12.0
DOOR_SRC_SIZE :: 16

Door_State :: enum {
	Inactive,
	Idle,
	Opening,
	Done,
}

Door :: struct {
	pos:           raylib.Vector2, // top-left of tile
	state:         Door_State,
	current_frame: f32,
	anim_timer:    f32,
	texture:       raylib.Texture2D,
}

init_door :: proc(d: ^Door) {
	d.texture = raylib.LoadTexture("assets/sprites/door_opens.png")
	d.state = .Inactive
}

unload_door :: proc(d: ^Door) {
	if d.texture.id > 0 {
		raylib.UnloadTexture(d.texture)
	}
}

spawn_door :: proc(d: ^Door, pos: raylib.Vector2) {
	d.pos = pos
	d.state = .Idle
	d.current_frame = 0
	d.anim_timer = 0
}

door_hitbox :: proc(d: ^Door) -> raylib.Rectangle {
	return raylib.Rectangle{d.pos.x, d.pos.y, DOOR_SRC_SIZE, DOOR_SRC_SIZE}
}

// Advances the opening animation. Returns true on the frame the animation
// finishes (used to trigger the map transition).
update_door :: proc(d: ^Door, dt: f32) -> bool {
	if d.state != .Opening {
		return false
	}
	frame_time :: f32(1.0 / DOOR_FPS)
	d.anim_timer += dt
	for d.anim_timer >= frame_time {
		d.anim_timer -= frame_time
		d.current_frame += 1
		if int(d.current_frame) >= DOOR_FRAMES {
			d.current_frame = DOOR_FRAMES - 1
			d.state = .Done
			return true
		}
	}
	return false
}

draw_door :: proc(d: ^Door) {
	if d.state == .Inactive {
		return
	}
	frame := int(d.current_frame)
	if frame >= DOOR_FRAMES {
		frame = DOOR_FRAMES - 1
	}
	src := raylib.Rectangle{
		f32(frame * DOOR_SRC_SIZE), 0,
		f32(DOOR_SRC_SIZE), f32(DOOR_SRC_SIZE),
	}
	dst := raylib.Rectangle{
		d.pos.x, d.pos.y,
		f32(DOOR_SRC_SIZE), f32(DOOR_SRC_SIZE),
	}
	raylib.DrawTexturePro(d.texture, src, dst, {0, 0}, 0, raylib.WHITE)
}
