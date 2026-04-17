package game

import "vendor:raylib"
import dm "../dotmap"

Gadreela_State :: enum {
	Inactive,
	Spawning,
	Following,
}

Gadreela :: struct {
	state:         Gadreela_State,
	pos:           raylib.Vector2, // bottom-center
	vel:           raylib.Vector2,
	on_ground:     bool,
	facing_left:   bool,
	moving:        bool,
	current_frame: f32,
	anim_timer:    f32,
	idle_tex:      raylib.Texture2D,
	move_tex:      raylib.Texture2D,
	spawn_tex:     raylib.Texture2D,
	idle_frames:   int,
	move_frames:   int,
	spawn_frames:  int,
}

init_gadreela :: proc(g: ^Gadreela) {
	g.state = .Inactive
	g.idle_tex = raylib.LoadTexture("assets/sprites/player_daughter_bloodblob_idle.png")
	g.move_tex = raylib.LoadTexture("assets/sprites/player_daughter_bloodblob_move.png")
	g.spawn_tex = raylib.LoadTexture("assets/sprites/player_daughter_bloodblob_spawn.png")
	g.idle_frames = int(g.idle_tex.width) / GADREELA_SRC_SIZE
	g.move_frames = int(g.move_tex.width) / GADREELA_SRC_SIZE
	g.spawn_frames = int(g.spawn_tex.width) / GADREELA_SRC_SIZE
}

unload_gadreela :: proc(g: ^Gadreela) {
	raylib.UnloadTexture(g.idle_tex)
	raylib.UnloadTexture(g.move_tex)
	raylib.UnloadTexture(g.spawn_tex)
}

spawn_gadreela :: proc(g: ^Gadreela, pos: raylib.Vector2, facing_left: bool) {
	g.state = .Spawning
	g.pos = pos
	g.vel = {}
	g.on_ground = false
	g.facing_left = facing_left
	g.moving = false
	g.current_frame = 0
	g.anim_timer = 0
}

@(private = "file")
gadreela_hitbox :: proc(g: ^Gadreela) -> raylib.Rectangle {
	return {
		g.pos.x - f32(GADREELA_HITBOX_W) / 2,
		g.pos.y - f32(GADREELA_HITBOX_H),
		f32(GADREELA_HITBOX_W),
		f32(GADREELA_HITBOX_H),
	}
}

@(private = "file")
gadreela_move_and_collide :: proc(g: ^Gadreela, map_data: ^dm.Dot_Map, dt: f32) {
	g.pos.x += g.vel.x * dt
	hb := gadreela_hitbox(g)
	if check_rect_solid(map_data, hb) {
		if g.vel.x > 0 {
			tile_x := int(hb.x + hb.width) / TILE_SIZE
			g.pos.x = f32(tile_x * TILE_SIZE) - f32(GADREELA_HITBOX_W) / 2
		} else if g.vel.x < 0 {
			tile_x := int(hb.x) / TILE_SIZE
			g.pos.x = f32((tile_x + 1) * TILE_SIZE) + f32(GADREELA_HITBOX_W) / 2
		}
		g.vel.x = 0
	}

	g.pos.y += g.vel.y * dt
	hb = gadreela_hitbox(g)
	g.on_ground = false
	if check_rect_solid(map_data, hb) {
		if g.vel.y > 0 {
			tile_y := int(hb.y + hb.height) / TILE_SIZE
			g.pos.y = f32(tile_y * TILE_SIZE)
			g.on_ground = true
		} else if g.vel.y < 0 {
			tile_y := int(hb.y) / TILE_SIZE
			g.pos.y = f32((tile_y + 1) * TILE_SIZE) + f32(GADREELA_HITBOX_H)
		}
		g.vel.y = 0
	}
}

update_gadreela :: proc(g: ^Gadreela, p: ^Player, map_data: ^dm.Dot_Map, dt: f32) {
	if g.state == .Inactive {
		return
	}

	// Gravity applies in all active states
	g.vel.y += GRAVITY * dt
	if g.vel.y > MAX_FALL_SPEED {
		g.vel.y = MAX_FALL_SPEED
	}

	switch g.state {
	case .Inactive:
		return

	case .Spawning:
		g.vel.x = 0
		gadreela_move_and_collide(g, map_data, dt)
		frame_dur := f32(1.0 / GADREELA_SPAWN_FPS)
		g.anim_timer += dt
		if g.anim_timer >= frame_dur {
			g.anim_timer -= frame_dur
			g.current_frame += 1
			if int(g.current_frame) >= g.spawn_frames {
				g.state = .Following
				g.current_frame = 0
				g.anim_timer = 0
			}
		}

	case .Following:
		// Respawn if player is on a different platform (too far vertically, or way offscreen horizontally)
		dy := p.pos.y - g.pos.y
		dx := p.pos.x - g.pos.x
		if dy < -GADREELA_RESPAWN_DIST_Y || dy > GADREELA_RESPAWN_DIST_Y ||
		   dx < -GADREELA_RESPAWN_DIST_X || dx > GADREELA_RESPAWN_DIST_X {
			// Respawn next to player facing whatever direction player faces
			g.pos = p.pos
			g.vel = {}
			g.facing_left = p.facing_left
			g.moving = false
			g.state = .Spawning
			g.current_frame = 0
			g.anim_timer = 0
			return
		}

		// Player is on our current side? If so, wait for them to pass instead of lerping through.
		// Intended follow side: opposite of player's facing direction (she stays behind).
		follow_on_right := p.facing_left // if player faces left, she should be on the right
		currently_on_right := g.pos.x > p.pos.x

		if follow_on_right == currently_on_right {
			// On correct side — walk toward target position behind player
			target_x := p.pos.x + (follow_on_right ? GADREELA_FOLLOW_DISTANCE : -GADREELA_FOLLOW_DISTANCE)
			delta := target_x - g.pos.x
			abs_delta := delta < 0 ? -delta : delta
			if abs_delta > GADREELA_STOP_TOLERANCE {
				g.vel.x = (delta > 0 ? 1 : -1) * GADREELA_SPEED
				g.moving = true
				g.facing_left = delta < 0
			} else {
				g.vel.x = 0
				g.moving = false
				// Face the same direction as player when idle alongside
				g.facing_left = p.facing_left
			}
		} else {
			// Wrong side — wait for player to pass through before following behind
			g.vel.x = 0
			g.moving = false
			g.facing_left = p.facing_left
		}

		gadreela_move_and_collide(g, map_data, dt)

		frames := g.moving ? g.move_frames : g.idle_frames
		if frames > 1 {
			g.anim_timer += dt
			if g.anim_timer >= ANIM_FRAME_TIME {
				g.anim_timer -= ANIM_FRAME_TIME
				g.current_frame += 1
				if int(g.current_frame) >= frames {
					g.current_frame = 0
				}
			}
		}
	}
}

draw_gadreela :: proc(g: ^Gadreela) {
	if g.state == .Inactive {
		return
	}

	tex: raylib.Texture2D
	frames: int
	switch g.state {
	case .Inactive:
		return
	case .Spawning:
		tex = g.spawn_tex
		frames = g.spawn_frames
	case .Following:
		if g.moving {
			tex = g.move_tex
			frames = g.move_frames
		} else {
			tex = g.idle_tex
			frames = g.idle_frames
		}
	}

	frame := int(g.current_frame)
	if frame >= frames {
		frame = frames - 1
	}

	src := raylib.Rectangle{
		f32(frame * GADREELA_SRC_SIZE), 0,
		g.facing_left ? -f32(GADREELA_SRC_SIZE) : f32(GADREELA_SRC_SIZE),
		f32(GADREELA_SRC_SIZE),
	}
	dst := raylib.Rectangle{
		g.pos.x - f32(GADREELA_SRC_SIZE) / 2,
		g.pos.y - f32(GADREELA_SRC_SIZE),
		f32(GADREELA_SRC_SIZE),
		f32(GADREELA_SRC_SIZE),
	}
	raylib.DrawTexturePro(tex, src, dst, {0, 0}, 0, raylib.WHITE)
}
