package game

import "vendor:raylib"
import dm "../dotmap"
import "core:math/rand"

Dash_Particle :: struct {
	pos:      raylib.Vector2,
	vel:      raylib.Vector2,
	lifetime: f32,
	max_life: f32,
	active:   bool,
}

Player :: struct {
	pos:            raylib.Vector2, // bottom-center
	vel:            raylib.Vector2,
	on_ground:      bool,
	jumps_left:     int,
	facing_left:    bool,
	moving:         bool,
	hp:                 f32,
	damage_flash_timer: f32,
	move_tex:           raylib.Texture2D,
	idle_tex:       raylib.Texture2D,
	roll_tex:       raylib.Texture2D,
	frame_count:    int,
	idle_frames:    int,
	roll_frames:    int,
	current_frame:  f32,
	anim_timer:     f32,
	dashing:        bool,
	dash_timer:     f32,
	dash_cooldown:  f32,
	dash_dir:       f32,
	particles:      [MAX_DASH_PARTICLES]Dash_Particle,
}

init_player :: proc(p: ^Player, spawn: raylib.Vector2) {
	p.pos = spawn
	p.vel = {}
	p.on_ground = false
	p.jumps_left = MAX_JUMPS
	p.facing_left = false
	p.moving = false
	p.hp = PLAYER_MAX_HP
	p.current_frame = 0
	p.anim_timer = 0
	p.dashing = false
	p.dash_timer = 0
	p.dash_cooldown = 0
	p.dash_dir = 1

	p.move_tex = raylib.LoadTexture("assets/sprites/player_move.png")
	p.idle_tex = raylib.LoadTexture("assets/sprites/player_idle.png")
	p.roll_tex = raylib.LoadTexture("assets/sprites/player_roll.png")
	p.frame_count = int(p.move_tex.width) / SPRITE_SRC_SIZE
	p.idle_frames = int(p.idle_tex.width) / SPRITE_SRC_SIZE
	p.roll_frames = int(p.roll_tex.width) / SPRITE_SRC_SIZE
}

unload_player :: proc(p: ^Player) {
	raylib.UnloadTexture(p.move_tex)
	raylib.UnloadTexture(p.idle_tex)
	raylib.UnloadTexture(p.roll_tex)
}

update_player :: proc(p: ^Player, map_data: ^dm.Dot_Map, dt: f32) {
	// Dash cooldown
	if p.dash_cooldown > 0 {
		p.dash_cooldown -= dt
	}

	// Damage flash countdown
	if p.damage_flash_timer > 0 {
		p.damage_flash_timer -= dt
	}

	// Update particles
	update_dash_particles(p, dt)

	// Start dash
	if !p.dashing && p.dash_cooldown <= 0 && raylib.IsKeyPressed(.SPACE) {
		p.dashing = true
		p.dash_timer = DASH_DURATION
		p.dash_dir = p.facing_left ? -1.0 : 1.0
		p.current_frame = 0
		p.anim_timer = 0
	}

	if p.dashing {
		// Dash physics — flat horizontal launch, no gravity
		p.vel.x = DASH_SPEED * p.dash_dir
		p.vel.y = 0
		p.dash_timer -= dt

		// Trail particles
		spawn_dash_particles(p)

		move_and_collide(p, map_data, dt)

		// End dash on timer or wall hit
		if p.dash_timer <= 0 || p.vel.x == 0 {
			p.dashing = false
			p.dash_cooldown = DASH_COOLDOWN
			p.vel.x = 0
		}

		// Roll animation — spread frames across dash duration
		if p.roll_frames > 1 {
			frame_dur := DASH_DURATION / f32(p.roll_frames)
			p.anim_timer += dt
			if p.anim_timer >= frame_dur {
				p.anim_timer -= frame_dur
				p.current_frame += 1
				if int(p.current_frame) >= p.roll_frames {
					p.current_frame = f32(p.roll_frames - 1)
				}
			}
		}
	} else {
		// Normal input
		move_x: f32 = 0
		if raylib.IsKeyDown(.A) || raylib.IsKeyDown(.LEFT) {
			move_x -= 1
		}
		if raylib.IsKeyDown(.D) || raylib.IsKeyDown(.RIGHT) {
			move_x += 1
		}

		p.vel.x = move_x * PLAYER_SPEED

		// Jump (double jump)
		if p.jumps_left > 0 && (raylib.IsKeyPressed(.W) || raylib.IsKeyPressed(.UP)) {
			p.vel.y = JUMP_VELOCITY
			p.on_ground = false
			p.jumps_left -= 1
		}

		// Gravity
		p.vel.y += GRAVITY * dt
		if p.vel.y > MAX_FALL_SPEED {
			p.vel.y = MAX_FALL_SPEED
		}

		move_and_collide(p, map_data, dt)

		// Facing
		was_moving := p.moving
		p.moving = move_x != 0
		if move_x < 0 {
			p.facing_left = true
		} else if move_x > 0 {
			p.facing_left = false
		}

		// Animation
		if p.moving != was_moving {
			p.current_frame = 0
			p.anim_timer = 0
		}

		frames := p.moving ? p.frame_count : p.idle_frames
		if frames > 1 {
			p.anim_timer += dt
			if p.anim_timer >= ANIM_FRAME_TIME {
				p.anim_timer -= ANIM_FRAME_TIME
				p.current_frame += 1
				if int(p.current_frame) >= frames {
					p.current_frame = 0
				}
			}
		}
	}
}

draw_player_hud :: proc(p: ^Player) {
	BAR_X      :: 8
	BAR_Y      :: SCREEN_HEIGHT - 16
	BAR_W      :: 60
	BAR_H      :: 6
	OUTLINE    :: raylib.Color{0, 0, 0, 255}
	FILL_COLOR :: raylib.Color{0x33, 0xFF, 0x66, 0xFF}

	// Black outline
	raylib.DrawRectangle(BAR_X - 1, BAR_Y - 1, BAR_W + 2, BAR_H + 2, OUTLINE)
	// Green fill based on current HP
	fill_w := i32(f32(BAR_W) * (p.hp / PLAYER_MAX_HP))
	if fill_w < 0 { fill_w = 0 }
	raylib.DrawRectangle(BAR_X, BAR_Y, fill_w, BAR_H, FILL_COLOR)
}

draw_player :: proc(p: ^Player, white_shader: raylib.Shader) {
	// Draw particles behind player
	draw_dash_particles(p)

	tex: raylib.Texture2D
	if p.dashing {
		tex = p.roll_tex
	} else if p.moving {
		tex = p.move_tex
	} else {
		tex = p.idle_tex
	}

	frame := int(p.current_frame)
	src := raylib.Rectangle{
		f32(frame * SPRITE_SRC_SIZE), 0,
		p.facing_left ? -f32(SPRITE_SRC_SIZE) : f32(SPRITE_SRC_SIZE),
		f32(SPRITE_SRC_SIZE),
	}
	dst := raylib.Rectangle{
		p.pos.x - SPRITE_DST_SIZE / 2,
		p.pos.y - SPRITE_DST_SIZE,
		SPRITE_DST_SIZE,
		SPRITE_DST_SIZE,
	}
	if p.damage_flash_timer > 0 {
		raylib.BeginShaderMode(white_shader)
	}
	raylib.DrawTexturePro(tex, src, dst, {0, 0}, 0, raylib.WHITE)
	if p.damage_flash_timer > 0 {
		raylib.EndShaderMode()
	}
}

// ---------------------------------------------------------------------------
// Dash particles
// ---------------------------------------------------------------------------

@(private = "file")
spawn_dash_particles :: proc(p: ^Player) {
	spawned := 0
	for &part in p.particles {
		if spawned >= 2 {
			break
		}
		if !part.active {
			part.active = true
			part.pos = {
				p.pos.x + (rand.float32() * 6 - 3),
				p.pos.y - (rand.float32() * 8 + 2),
			}
			part.vel = {
				-p.dash_dir * (rand.float32() * 40 + 20),
				rand.float32() * 40 - 20,
			}
			part.max_life = rand.float32() * 0.15 + 0.15
			part.lifetime = part.max_life
			spawned += 1
		}
	}
}

@(private = "file")
update_dash_particles :: proc(p: ^Player, dt: f32) {
	for &part in p.particles {
		if part.active {
			part.pos.x += part.vel.x * dt
			part.pos.y += part.vel.y * dt
			part.lifetime -= dt
			if part.lifetime <= 0 {
				part.active = false
			}
		}
	}
}

@(private = "file")
draw_dash_particles :: proc(p: ^Player) {
	for &part in p.particles {
		if part.active {
			t := part.lifetime / part.max_life
			alpha := u8(255 * t)
			size := 1.0 + t * 1.5
			color := raylib.Color{255, 255, 255, alpha}
			raylib.DrawCircleV(part.pos, size, color)
		}
	}
}

// ---------------------------------------------------------------------------
// Collision
// ---------------------------------------------------------------------------

get_hitbox :: proc(p: ^Player) -> raylib.Rectangle {
	return {
		p.pos.x - f32(PLAYER_HITBOX_W) / 2,
		p.pos.y - f32(PLAYER_HITBOX_H),
		f32(PLAYER_HITBOX_W),
		f32(PLAYER_HITBOX_H),
	}
}

is_solid :: proc(map_data: ^dm.Dot_Map, tx, ty: int) -> bool {
	if ty < 0 || ty >= len(map_data.grid) {
		return true
	}
	row := map_data.grid[ty]
	if tx < 0 || tx >= len(row) {
		return true
	}
	sym := row[tx].symbol
	td, has := map_data.metadata[sym]
	if !has {
		return false
	}
	return !td.passable && len(td.tiles) > 0
}

check_rect_solid :: proc(map_data: ^dm.Dot_Map, rect: raylib.Rectangle) -> bool {
	x0 := int(rect.x) / TILE_SIZE
	y0 := int(rect.y) / TILE_SIZE
	x1 := int(rect.x + rect.width - 0.01) / TILE_SIZE
	y1 := int(rect.y + rect.height - 0.01) / TILE_SIZE

	for ty in y0 ..= y1 {
		for tx in x0 ..= x1 {
			if is_solid(map_data, tx, ty) {
				return true
			}
		}
	}
	return false
}

@(private = "file")
move_and_collide :: proc(p: ^Player, map_data: ^dm.Dot_Map, dt: f32) {
	// Move X
	p.pos.x += p.vel.x * dt
	hb := get_hitbox(p)
	if check_rect_solid(map_data, hb) {
		// Push back
		if p.vel.x > 0 {
			tile_x := int(hb.x + hb.width) / TILE_SIZE
			p.pos.x = f32(tile_x * TILE_SIZE) - f32(PLAYER_HITBOX_W) / 2
		} else if p.vel.x < 0 {
			tile_x := int(hb.x) / TILE_SIZE
			p.pos.x = f32((tile_x + 1) * TILE_SIZE) + f32(PLAYER_HITBOX_W) / 2
		}
		p.vel.x = 0
	}

	// Move Y
	p.pos.y += p.vel.y * dt
	hb = get_hitbox(p)
	p.on_ground = false
	if check_rect_solid(map_data, hb) {
		if p.vel.y > 0 {
			// Landing
			tile_y := int(hb.y + hb.height) / TILE_SIZE
			p.pos.y = f32(tile_y * TILE_SIZE)
			p.on_ground = true
			p.jumps_left = MAX_JUMPS
		} else if p.vel.y < 0 {
			// Hit ceiling
			tile_y := int(hb.y) / TILE_SIZE
			p.pos.y = f32((tile_y + 1) * TILE_SIZE) + f32(PLAYER_HITBOX_H)
		}
		p.vel.y = 0
	}
}
