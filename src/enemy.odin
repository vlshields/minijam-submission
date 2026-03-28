package game

import "vendor:raylib"
import dm "../dotmap"

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

Enemy_State :: enum {
	Idle,
	Attacking,
	Cooldown,
	Dead,
}

Enemy :: struct {
	pos:           raylib.Vector2, // bottom-center
	vel:           raylib.Vector2,
	state:         Enemy_State,
	aggroed:       bool,
	facing_left:   bool,
	on_ground:     bool,
	hp:            f32,
	current_frame: f32,
	anim_timer:    f32,
	state_timer:       f32,
	damage_flash_timer: f32,
}

Enemy_Pool :: struct {
	enemies:     [MAX_ENEMIES]Enemy,
	count:       int,
	idle_tex:    raylib.Texture2D,
	move_tex:    raylib.Texture2D,
	idle_frames: int,
	move_frames: int,
}

// ---------------------------------------------------------------------------
// Lifecycle
// ---------------------------------------------------------------------------

init_enemies :: proc(pool: ^Enemy_Pool) {
	pool.idle_tex = raylib.LoadTexture("assets/sprites/enemy_flameball_idle.png")
	pool.move_tex = raylib.LoadTexture("assets/sprites/enemy_flameball_move.png")
	pool.idle_frames = int(pool.idle_tex.width) / ENEMY_SRC_SIZE
	pool.move_frames = int(pool.move_tex.width) / ENEMY_SRC_SIZE
	pool.count = 0
}

spawn_enemy :: proc(pool: ^Enemy_Pool, pos: raylib.Vector2) {
	if pool.count >= MAX_ENEMIES {
		return
	}
	e := &pool.enemies[pool.count]
	e.pos = pos
	e.vel = {}
	e.state = .Idle
	e.aggroed = false
	e.facing_left = false
	e.on_ground = false
	e.hp = ENEMY_HP
	e.current_frame = 0
	e.anim_timer = 0
	e.state_timer = 0
	pool.count += 1
}

unload_enemies :: proc(pool: ^Enemy_Pool) {
	raylib.UnloadTexture(pool.idle_tex)
	raylib.UnloadTexture(pool.move_tex)
}

// ---------------------------------------------------------------------------
// Update
// ---------------------------------------------------------------------------

update_enemies :: proc(
	pool: ^Enemy_Pool,
	player: ^Player,
	companion: ^Companion,
	camera: ^raylib.Camera2D,
	map_data: ^dm.Dot_Map,
	dt: f32,
) {
	// Compute viewport rect for aggro check
	half_w := f32(SCREEN_WIDTH) / (2 * camera.zoom)
	half_h := f32(SCREEN_HEIGHT) / (2 * camera.zoom)
	view_rect := raylib.Rectangle{
		camera.target.x - half_w,
		camera.target.y - half_h,
		half_w * 2,
		half_h * 2,
	}

	for i := 0; i < pool.count; i += 1 {
		e := &pool.enemies[i]
		if e.state == .Dead {
			continue
		}

		// Damage flash countdown
		if e.damage_flash_timer > 0 {
			e.damage_flash_timer -= dt
		}

		// Viewport aggro — requires in-view AND same platform level
		if !e.aggroed {
			ehb := get_enemy_hitbox(e)
			in_view := raylib.CheckCollisionRecs(ehb, view_rect)
			same_level := e.on_ground && player.on_ground && abs(player.pos.y - e.pos.y) < 2
			if in_view && same_level {
				e.aggroed = true
				e.state = .Attacking
				e.facing_left = player.pos.x < e.pos.x
				e.current_frame = 0
				e.anim_timer = 0
			}
		}

		switch e.state {
		case .Idle:
			// Pre-aggro: idle animation + gravity
			animate_enemy_loop(e, pool.idle_frames, dt)
			e.vel.x = 0
			e.vel.y += GRAVITY * dt
			if e.vel.y > MAX_FALL_SPEED {
				e.vel.y = MAX_FALL_SPEED
			}
			move_and_collide_enemy(e, map_data, dt)

		case .Attacking:
			// Face and roll toward player
			e.facing_left = player.pos.x < e.pos.x
			e.vel.x = e.facing_left ? -ENEMY_SPEED : ENEMY_SPEED

			// Gravity
			e.vel.y += GRAVITY * dt
			if e.vel.y > MAX_FALL_SPEED {
				e.vel.y = MAX_FALL_SPEED
			}
			move_and_collide_enemy(e, map_data, dt)

			// Move animation (one-shot = one attack attempt)
			anim_done := advance_enemy_oneshot(e, pool.move_frames, dt)

			// Check collision with player
			if check_enemy_player_collision(e, player) {
				player.hp -= ENEMY_DAMAGE
				player.damage_flash_timer = DAMAGE_FLASH_DURATION
				if player.hp < 0 {
					player.hp = 0
				}
				e.state = .Dead
				continue
			}

			// Animation cycle finished without hitting → cooldown
			if anim_done {
				e.state = .Cooldown
				e.state_timer = ENEMY_ATTACK_COOLDOWN
				e.current_frame = 0
				e.anim_timer = 0
				e.vel.x = 0
			}

		case .Cooldown:
			// Idle animation while waiting
			animate_enemy_loop(e, pool.idle_frames, dt)
			e.vel.x = 0
			e.vel.y += GRAVITY * dt
			if e.vel.y > MAX_FALL_SPEED {
				e.vel.y = MAX_FALL_SPEED
			}
			move_and_collide_enemy(e, map_data, dt)

			e.state_timer -= dt
			if e.state_timer <= 0 {
				e.state = .Attacking
				e.facing_left = player.pos.x < e.pos.x
				e.current_frame = 0
				e.anim_timer = 0
			}

		case .Dead:
		}

		// Companion attack collision
		if e.state != .Dead && companion.state == .Attacking {
			comp_rect := get_companion_rect(companion, player)
			ehb := get_enemy_hitbox(e)
			if raylib.CheckCollisionRecs(comp_rect, ehb) {
				e.hp -= COMPANION_DAMAGE
				e.damage_flash_timer = DAMAGE_FLASH_DURATION
				if e.hp <= 0 {
					e.state = .Dead
				}
			}
		}

		// Safety: kill if fallen far below map
		map_bottom := f32(map_data.height) * TILE_SIZE + 64
		if e.pos.y > map_bottom {
			e.state = .Dead
		}
	}
}

// ---------------------------------------------------------------------------
// Draw
// ---------------------------------------------------------------------------

draw_enemies :: proc(pool: ^Enemy_Pool, white_shader: raylib.Shader) {
	for i := 0; i < pool.count; i += 1 {
		e := &pool.enemies[i]
		if e.state == .Dead {
			continue
		}

		tex: raylib.Texture2D
		max_frames: int
		switch e.state {
		case .Attacking:
			tex = pool.move_tex
			max_frames = pool.move_frames
		case .Idle, .Cooldown:
			tex = pool.idle_tex
			max_frames = pool.idle_frames
		case .Dead:
			continue
		}

		frame := int(e.current_frame)
		if frame >= max_frames {
			frame = max_frames - 1
		}

		src := raylib.Rectangle{
			f32(frame * ENEMY_SRC_SIZE), 0,
			e.facing_left ? -f32(ENEMY_SRC_SIZE) : f32(ENEMY_SRC_SIZE),
			f32(ENEMY_SRC_SIZE),
		}
		dst := raylib.Rectangle{
			e.pos.x - f32(ENEMY_SRC_SIZE) / 2,
			e.pos.y - f32(ENEMY_SRC_SIZE),
			f32(ENEMY_SRC_SIZE),
			f32(ENEMY_SRC_SIZE),
		}
		if e.damage_flash_timer > 0 {
			raylib.BeginShaderMode(white_shader)
		}
		raylib.DrawTexturePro(tex, src, dst, {0, 0}, 0, raylib.WHITE)
		if e.damage_flash_timer > 0 {
			raylib.EndShaderMode()
		}
	}
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

@(private = "file")
get_enemy_hitbox :: proc(e: ^Enemy) -> raylib.Rectangle {
	return {
		e.pos.x - f32(ENEMY_HITBOX_W) / 2,
		e.pos.y - f32(ENEMY_HITBOX_H),
		f32(ENEMY_HITBOX_W),
		f32(ENEMY_HITBOX_H),
	}
}

@(private = "file")
check_enemy_player_collision :: proc(e: ^Enemy, p: ^Player) -> bool {
	return raylib.CheckCollisionRecs(get_enemy_hitbox(e), get_hitbox(p))
}

@(private = "file")
move_and_collide_enemy :: proc(e: ^Enemy, map_data: ^dm.Dot_Map, dt: f32) {
	// Move X
	e.pos.x += e.vel.x * dt
	hb := get_enemy_hitbox(e)
	if check_rect_solid(map_data, hb) {
		if e.vel.x > 0 {
			tile_x := int(hb.x + hb.width) / TILE_SIZE
			e.pos.x = f32(tile_x * TILE_SIZE) - f32(ENEMY_HITBOX_W) / 2
		} else if e.vel.x < 0 {
			tile_x := int(hb.x) / TILE_SIZE
			e.pos.x = f32((tile_x + 1) * TILE_SIZE) + f32(ENEMY_HITBOX_W) / 2
		}
		e.vel.x = 0
	}

	// Move Y
	e.pos.y += e.vel.y * dt
	hb = get_enemy_hitbox(e)
	e.on_ground = false
	if check_rect_solid(map_data, hb) {
		if e.vel.y > 0 {
			tile_y := int(hb.y + hb.height) / TILE_SIZE
			e.pos.y = f32(tile_y * TILE_SIZE)
			e.on_ground = true
		} else if e.vel.y < 0 {
			tile_y := int(hb.y) / TILE_SIZE
			e.pos.y = f32((tile_y + 1) * TILE_SIZE) + f32(ENEMY_HITBOX_H)
		}
		e.vel.y = 0
	}
}

@(private = "file")
advance_enemy_oneshot :: proc(e: ^Enemy, total_frames: int, dt: f32) -> bool {
	frame_dur: f32 = 1.0 / ENEMY_ANIM_FPS
	e.anim_timer += dt
	if e.anim_timer >= frame_dur {
		e.anim_timer -= frame_dur
		e.current_frame += 1
		if int(e.current_frame) >= total_frames {
			return true
		}
	}
	return false
}

@(private = "file")
animate_enemy_loop :: proc(e: ^Enemy, total_frames: int, dt: f32) {
	if total_frames <= 1 {
		return
	}
	e.anim_timer += dt
	if e.anim_timer >= ANIM_FRAME_TIME {
		e.anim_timer -= ANIM_FRAME_TIME
		e.current_frame += 1
		if int(e.current_frame) >= total_frames {
			e.current_frame = 0
		}
	}
}
