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
	jump_tex:       raylib.Texture2D,
	fall_tex:       raylib.Texture2D,
	frame_count:    int,
	idle_frames:    int,
	roll_frames:    int,
	jump_frames:    int,
	fall_frames:    int,
	current_frame:  f32,
	anim_timer:     f32,
	dashing:        bool,
	dash_timer:     f32,
	dash_cooldown:  f32,
	dash_dir:       f32,
	particles:      [MAX_DASH_PARTICLES]Dash_Particle,
	// Quick attack
	quick_attack_state:         Quick_Attack_State,
	quick_attack_frame:         f32,
	quick_attack_timer:         f32,
	quick_attack_cooldown:      f32,
	quick_attack_damage_active: bool,
	chain_buffered:             bool,
	attack1_tex:                raylib.Texture2D,
	attack2_tex:                raylib.Texture2D,
	quick_attack_frames:        int,
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
	p.jump_tex = raylib.LoadTexture("assets/sprites/player_jump.png")
	p.fall_tex = raylib.LoadTexture("assets/sprites/player_falling.png")
	p.attack1_tex = raylib.LoadTexture("assets/sprites/player_fast_attack1.png")
	p.attack2_tex = raylib.LoadTexture("assets/sprites/player_fast_attack2.png")
	p.quick_attack_frames = int(p.attack1_tex.width) / QUICK_ATTACK_SRC_SIZE
	p.frame_count = int(p.move_tex.width) / SPRITE_SRC_SIZE
	p.idle_frames = int(p.idle_tex.width) / SPRITE_SRC_SIZE
	p.roll_frames = int(p.roll_tex.width) / SPRITE_SRC_SIZE
	p.jump_frames = int(p.jump_tex.width) / SPRITE_SRC_SIZE
	p.fall_frames = int(p.fall_tex.width) / SPRITE_SRC_SIZE
}

unload_player :: proc(p: ^Player) {
	raylib.UnloadTexture(p.move_tex)
	raylib.UnloadTexture(p.idle_tex)
	raylib.UnloadTexture(p.roll_tex)
	raylib.UnloadTexture(p.jump_tex)
	raylib.UnloadTexture(p.fall_tex)
	raylib.UnloadTexture(p.attack1_tex)
	raylib.UnloadTexture(p.attack2_tex)
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
		// Capture previous state for animation transitions
		was_on_ground := p.on_ground
		was_rising := p.vel.y < 0

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

		// Animation — detect state transitions and reset frame
		rising := p.vel.y < 0
		anim_changed := (p.moving != was_moving) ||
			(p.on_ground != was_on_ground) ||
			(!p.on_ground && rising != was_rising)
		if anim_changed {
			p.current_frame = 0
			p.anim_timer = 0
		}

		if p.on_ground {
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
		} else {
			frames := rising ? p.jump_frames : p.fall_frames
			if frames > 1 {
				p.anim_timer += dt
				if p.anim_timer >= ANIM_FRAME_TIME {
					p.anim_timer -= ANIM_FRAME_TIME
					p.current_frame += 1
					if int(p.current_frame) >= frames {
						p.current_frame = f32(frames - 1)
					}
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
	} else if !p.on_ground {
		tex = (p.vel.y < 0) ? p.jump_tex : p.fall_tex
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

	// Draw quick attack overlay on top of player sprite
	if p.quick_attack_state == .Attack1 || p.quick_attack_state == .Attack2 {
		qa_tex := (p.quick_attack_state == .Attack1) ? p.attack1_tex : p.attack2_tex
		qa_frame := int(p.quick_attack_frame)
		if qa_frame >= p.quick_attack_frames {
			qa_frame = p.quick_attack_frames - 1
		}
		qa_src := raylib.Rectangle{
			f32(qa_frame * QUICK_ATTACK_SRC_SIZE), 0,
			p.facing_left ? -f32(QUICK_ATTACK_SRC_SIZE) : f32(QUICK_ATTACK_SRC_SIZE),
			f32(QUICK_ATTACK_SRC_SIZE),
		}
		offset_x: f32 = p.facing_left ? -16 : 16
		qa_dst := raylib.Rectangle{
			p.pos.x - f32(QUICK_ATTACK_SRC_SIZE) / 2 + offset_x,
			p.pos.y - f32(QUICK_ATTACK_SRC_SIZE),
			f32(QUICK_ATTACK_SRC_SIZE),
			f32(QUICK_ATTACK_SRC_SIZE),
		}
		raylib.DrawTexturePro(qa_tex, qa_src, qa_dst, {0, 0}, 0, raylib.WHITE)
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



Blood_Scythe_State :: enum {
	Inactive,
	Spawning,
	Idle,
	Attacking,
	Quick_Attacking,
	Despawning,
}

Blood_Scythe :: struct {
	state:            Blood_Scythe_State,
	facing_left:      bool,
	current_offset_x: f32,
	idle_tex:         raylib.Texture2D,
	spawn_tex:        raylib.Texture2D,
	attack_tex:       raylib.Texture2D,
	despawn_tex:      raylib.Texture2D,
	idle_frames:      int,
	spawn_frames:     int,
	attack_frames:    int,
	despawn_frames:   int,
	current_frame:    f32,
	anim_timer:       f32,
	attack_cooldown:      f32,
	pending_spawn:        bool,
	quick_attack_tex:     raylib.Texture2D,
	quick_attack_frames:  int,
}

init_blood_scythe :: proc(s: ^Blood_Scythe) {
	s.state = .Inactive
	s.facing_left = false
	s.current_offset_x = SCYTHE_OFFSET_X
	s.current_frame = 0
	s.anim_timer = 0
	s.attack_cooldown = 0

	s.idle_tex = raylib.LoadTexture("assets/sprites/blood_scythe_idle.png")
	s.spawn_tex = raylib.LoadTexture("assets/sprites/blood_scythe_spawn.png")
	s.attack_tex = raylib.LoadTexture("assets/sprites/blood_scythe_attack.png")
	s.despawn_tex = raylib.LoadTexture("assets/sprites/blood_scythe_despsawn.png")
	s.quick_attack_tex = raylib.LoadTexture("assets/sprites/blood_scythe_fast_attack.png")
	s.idle_frames = int(s.idle_tex.width) / SCYTHE_SRC_SIZE
	s.spawn_frames = int(s.spawn_tex.width) / SCYTHE_SRC_SIZE
	s.attack_frames = int(s.attack_tex.width) / SCYTHE_SRC_SIZE
	s.despawn_frames = int(s.despawn_tex.width) / SCYTHE_SRC_SIZE
	s.quick_attack_frames = int(s.quick_attack_tex.width) / SCYTHE_SRC_SIZE
}

unload_blood_scythe :: proc(s: ^Blood_Scythe) {
	raylib.UnloadTexture(s.idle_tex)
	raylib.UnloadTexture(s.spawn_tex)
	raylib.UnloadTexture(s.attack_tex)
	raylib.UnloadTexture(s.despawn_tex)
	raylib.UnloadTexture(s.quick_attack_tex)
}

update_blood_scythe :: proc(s: ^Blood_Scythe, p: ^Player, companion: ^Companion, dt: f32) {
	if s.attack_cooldown > 0 {
		s.attack_cooldown -= dt
	}

	switch s.state {
	case .Inactive:
		// Deferred spawn: wait for companion to finish despawning
		if s.pending_spawn && companion.state == .Inactive {
			s.pending_spawn = false
			s.state = .Spawning
			s.facing_left = p.facing_left
			s.current_offset_x = p.facing_left ? -SCYTHE_OFFSET_X : SCYTHE_OFFSET_X
			s.current_frame = 0
			s.anim_timer = 0
			return
		}

		if raylib.IsKeyPressed(.R) {
			if companion.state != .Inactive {
				// Despawn companion first, then spawn scythe
				if companion.state != .Despawning {
					companion.state = .Despawning
					companion.current_frame = 0
					companion.anim_timer = 0
				}
				s.pending_spawn = true
			} else {
				s.state = .Spawning
				s.facing_left = p.facing_left
				s.current_offset_x = p.facing_left ? -SCYTHE_OFFSET_X : SCYTHE_OFFSET_X
				s.current_frame = 0
				s.anim_timer = 0
			}
		}

	case .Spawning:
		scythe_advance_oneshot(s, s.spawn_frames, dt, raylib.EaseBackOut)
		scythe_sync_position(s, p, dt)
		if int(s.current_frame) >= s.spawn_frames {
			s.state = .Idle
			s.current_frame = 0
			s.anim_timer = 0
		}

	case .Idle:
		if raylib.IsKeyPressed(.R) {
			s.state = .Despawning
			s.current_frame = 0
			s.anim_timer = 0
			return
		}

		if s.attack_cooldown <= 0 && (raylib.IsMouseButtonPressed(.LEFT) || raylib.IsKeyPressed(.J)) {
			s.state = .Attacking
			s.current_frame = 0
			s.anim_timer = 0
			return
		}

		if s.attack_cooldown <= 0 && (raylib.IsMouseButtonPressed(.RIGHT) || raylib.IsKeyPressed(.K)) {
			s.state = .Quick_Attacking
			s.current_frame = 0
			s.anim_timer = 0
			return
		}

		// Follow player
		s.facing_left = p.facing_left
		scythe_sync_position(s, p, dt)
		// Idle animation loops regardless of moving/not moving
		scythe_animate_loop(s, dt)

	case .Attacking:
		scythe_advance_oneshot(s, s.attack_frames, dt, raylib.EaseCubicOut)
		scythe_sync_position(s, p, dt)
		if int(s.current_frame) >= s.attack_frames {
			s.state = .Idle
			s.current_frame = 0
			s.anim_timer = 0
			s.attack_cooldown = SCYTHE_ATTACK_COOLDOWN
		}

	case .Quick_Attacking:
		scythe_advance_oneshot(s, s.quick_attack_frames, dt, raylib.EaseCubicOut)
		scythe_sync_position(s, p, dt)
		if int(s.current_frame) >= s.quick_attack_frames {
			s.state = .Idle
			s.current_frame = 0
			s.anim_timer = 0
			s.attack_cooldown = SCYTHE_ATTACK_COOLDOWN
		}

	case .Despawning:
		scythe_advance_oneshot(s, s.despawn_frames, dt, raylib.EaseCubicIn)
		scythe_sync_position(s, p, dt)
		if int(s.current_frame) >= s.despawn_frames {
			s.state = .Inactive
			s.current_frame = 0
			s.anim_timer = 0
		}
	}
}

draw_blood_scythe :: proc(s: ^Blood_Scythe, p: ^Player) {
	if s.state == .Inactive {
		return
	}

	tex: raylib.Texture2D
	frames: int
	switch s.state {
	case .Spawning:
		tex = s.spawn_tex
		frames = s.spawn_frames
	case .Attacking:
		tex = s.attack_tex
		frames = s.attack_frames
	case .Quick_Attacking:
		tex = s.quick_attack_tex
		frames = s.quick_attack_frames
	case .Despawning:
		tex = s.despawn_tex
		frames = s.despawn_frames
	case .Idle:
		tex = s.idle_tex
		frames = s.idle_frames
	case .Inactive:
		return
	}

	frame := int(s.current_frame)
	if frame >= frames {
		frame = frames - 1
	}

	src := raylib.Rectangle{
		f32(frame * SCYTHE_SRC_SIZE), 0,
		s.facing_left ? -f32(SCYTHE_SRC_SIZE) : f32(SCYTHE_SRC_SIZE),
		f32(SCYTHE_SRC_SIZE),
	}

	draw_x := p.pos.x + s.current_offset_x - f32(SCYTHE_SRC_SIZE) / 2
	draw_y := p.pos.y + SCYTHE_OFFSET_Y - f32(SCYTHE_SRC_SIZE)

	dst := raylib.Rectangle{
		draw_x,
		draw_y,
		f32(SCYTHE_SRC_SIZE),
		f32(SCYTHE_SRC_SIZE),
	}

	raylib.DrawTexturePro(tex, src, dst, {0, 0}, 0, raylib.WHITE)
}

get_scythe_rect :: proc(s: ^Blood_Scythe, p: ^Player) -> raylib.Rectangle {
	return {
		p.pos.x + s.current_offset_x - f32(SCYTHE_SRC_SIZE) / 2,
		p.pos.y + SCYTHE_OFFSET_Y - f32(SCYTHE_SRC_SIZE),
		f32(SCYTHE_SRC_SIZE),
		f32(SCYTHE_SRC_SIZE),
	}
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

@(private = "file")
scythe_advance_oneshot :: proc(s: ^Blood_Scythe, total_frames: int, dt: f32, ease: proc(f32, f32, f32, f32) -> f32) {
	total_dur: f32 = f32(total_frames) / SCYTHE_ONESHOT_FPS
	s.anim_timer += dt
	if s.anim_timer >= total_dur {
		s.anim_timer = total_dur
		s.current_frame = f32(total_frames)
	} else {
		s.current_frame = ease(s.anim_timer, 0, f32(total_frames), total_dur)
	}
}

@(private = "file")
scythe_sync_position :: proc(s: ^Blood_Scythe, p: ^Player, dt: f32) {
	target_x: f32 = p.facing_left ? -SCYTHE_OFFSET_X : SCYTHE_OFFSET_X
	diff := target_x - s.current_offset_x
	s.current_offset_x += diff * SCYTHE_LERP_SPEED * dt
	if diff < 0 ? -diff < 0.5 : diff < 0.5 {
		s.current_offset_x = target_x
	}
}

@(private = "file")
scythe_animate_loop :: proc(s: ^Blood_Scythe, dt: f32) {
	if s.idle_frames > 1 {
		s.anim_timer += dt
		if s.anim_timer >= ANIM_FRAME_TIME {
			s.anim_timer -= ANIM_FRAME_TIME
			s.current_frame += 1
			if int(s.current_frame) >= s.idle_frames {
				s.current_frame = 0
			}
		}
	}
}

Companion_State :: enum {
	Inactive,
	Spawning,
	Idle,
	Attacking,
	Despawning,
}

Companion :: struct {
	state:            Companion_State,
	facing_left:      bool,
	moving:           bool,
	current_offset_x: f32,
	move_tex:         raylib.Texture2D,
	idle_tex:         raylib.Texture2D,
	spawn_tex:        raylib.Texture2D,
	attack_tex:       raylib.Texture2D,
	despawn_tex:      raylib.Texture2D,
	frame_count:      int,
	idle_frames:      int,
	spawn_frames:     int,
	attack_frames:    int,
	despawn_frames:   int,
	current_frame:    f32,
	anim_timer:       f32,
	attack_cooldown:  f32,
	pending_spawn:    bool,
}

init_companion :: proc(c: ^Companion) {
	c.state = .Inactive
	c.facing_left = false
	c.moving = false
	c.current_offset_x = COMPANION_OFFSET_X
	c.current_frame = 0
	c.anim_timer = 0
	c.attack_cooldown = 0

	c.move_tex = raylib.LoadTexture("assets/sprites/blood_teeth_move.png")
	c.idle_tex = raylib.LoadTexture("assets/sprites/blood_teeth_idle.png")
	c.spawn_tex = raylib.LoadTexture("assets/sprites/blood_teeth_spawn.png")
	c.attack_tex = raylib.LoadTexture("assets/sprites/blood_teeth_attack.png")
	c.despawn_tex = raylib.LoadTexture("assets/sprites/blood_teeth_despawn.png")
	c.frame_count = int(c.move_tex.width) / COMPANION_SRC_SIZE
	c.idle_frames = int(c.idle_tex.width) / COMPANION_SRC_SIZE
	c.spawn_frames = int(c.spawn_tex.width) / COMPANION_SRC_SIZE
	c.attack_frames = int(c.attack_tex.width) / COMPANION_SRC_SIZE
	c.despawn_frames = int(c.despawn_tex.width) / COMPANION_SRC_SIZE
}

unload_companion :: proc(c: ^Companion) {
	raylib.UnloadTexture(c.move_tex)
	raylib.UnloadTexture(c.idle_tex)
	raylib.UnloadTexture(c.spawn_tex)
	raylib.UnloadTexture(c.attack_tex)
	raylib.UnloadTexture(c.despawn_tex)
}

update_companion :: proc(c: ^Companion, p: ^Player, scythe: ^Blood_Scythe, dt: f32) {
	// Attack cooldown ticks in all states
	if c.attack_cooldown > 0 {
		c.attack_cooldown -= dt
	}

	switch c.state {
	case .Inactive:
		// Deferred spawn: wait for scythe to finish despawning
		if c.pending_spawn && scythe.state == .Inactive {
			c.pending_spawn = false
			c.state = .Spawning
			c.facing_left = p.facing_left
			c.current_offset_x = p.facing_left ? -COMPANION_OFFSET_X : COMPANION_OFFSET_X
			c.current_frame = 0
			c.anim_timer = 0
			return
		}

		if raylib.IsKeyPressed(.F) {
			if scythe.state != .Inactive {
				// Despawn scythe first, then spawn companion
				if scythe.state != .Despawning {
					scythe.state = .Despawning
					scythe.current_frame = 0
					scythe.anim_timer = 0
				}
				c.pending_spawn = true
			} else {
				c.state = .Spawning
				c.facing_left = p.facing_left
				c.current_offset_x = p.facing_left ? -COMPANION_OFFSET_X : COMPANION_OFFSET_X
				c.current_frame = 0
				c.anim_timer = 0
			}
		}

	case .Spawning:
		advance_oneshot(c, c.spawn_frames, dt, raylib.EaseBackOut)
		sync_position(c, p, dt)
		if int(c.current_frame) >= c.spawn_frames {
			c.state = .Idle
			c.current_frame = 0
			c.anim_timer = 0
		}

	case .Idle:
		// Toggle off -> despawn
		if raylib.IsKeyPressed(.F) {
			c.state = .Despawning
			c.current_frame = 0
			c.anim_timer = 0
			return
		}

		// Attack on left click or J
		if c.attack_cooldown <= 0 && (raylib.IsMouseButtonPressed(.LEFT) || raylib.IsKeyPressed(.J)) {
			c.state = .Attacking
			c.current_frame = 0
			c.anim_timer = 0
			return
		}

		// Normal follow behavior
		sync_facing(c, p)
		sync_position(c, p, dt)
		animate_loop(c, p, dt)

	case .Attacking:
		advance_oneshot(c, c.attack_frames, dt, raylib.EaseCubicOut)
		sync_position(c, p, dt)
		if int(c.current_frame) >= c.attack_frames {
			c.state = .Idle
			c.current_frame = 0
			c.anim_timer = 0
			c.attack_cooldown = COMPANION_ATTACK_COOLDOWN
		}

	case .Despawning:
		advance_oneshot(c, c.despawn_frames, dt, raylib.EaseCubicIn)
		sync_position(c, p, dt)
		if int(c.current_frame) >= c.despawn_frames {
			c.state = .Inactive
			c.current_frame = 0
			c.anim_timer = 0
		}
	}
}

draw_companion :: proc(c: ^Companion, p: ^Player) {
	if c.state == .Inactive {
		return
	}

	tex: raylib.Texture2D
	frames: int
	switch c.state {
	case .Spawning:
		tex = c.spawn_tex
		frames = c.spawn_frames
	case .Attacking:
		tex = c.attack_tex
		frames = c.attack_frames
	case .Despawning:
		tex = c.despawn_tex
		frames = c.despawn_frames
	case .Idle:
		if c.moving {
			tex = c.move_tex
			frames = c.frame_count
		} else {
			tex = c.idle_tex
			frames = c.idle_frames
		}
	case .Inactive:
		return
	}

	frame := int(c.current_frame)
	if frame >= frames {
		frame = frames - 1
	}

	src := raylib.Rectangle{
		f32(frame * COMPANION_SRC_SIZE), 0,
		c.facing_left ? -f32(COMPANION_SRC_SIZE) : f32(COMPANION_SRC_SIZE),
		f32(COMPANION_SRC_SIZE),
	}

	draw_x := p.pos.x + c.current_offset_x - f32(COMPANION_SRC_SIZE) / 2
	draw_y := p.pos.y + COMPANION_OFFSET_Y - f32(COMPANION_SRC_SIZE)

	dst := raylib.Rectangle{
		draw_x,
		draw_y,
		f32(COMPANION_SRC_SIZE),
		f32(COMPANION_SRC_SIZE),
	}

	raylib.DrawTexturePro(tex, src, dst, {0, 0}, 0, raylib.WHITE)
}

get_companion_rect :: proc(c: ^Companion, p: ^Player) -> raylib.Rectangle {
	return {
		p.pos.x + c.current_offset_x - f32(COMPANION_SRC_SIZE) / 2,
		p.pos.y + COMPANION_OFFSET_Y - f32(COMPANION_SRC_SIZE),
		f32(COMPANION_SRC_SIZE),
		f32(COMPANION_SRC_SIZE),
	}
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

@(private = "file")
advance_oneshot :: proc(c: ^Companion, total_frames: int, dt: f32, ease: proc(f32, f32, f32, f32) -> f32) {
	total_dur: f32 = f32(total_frames) / COMPANION_ONESHOT_FPS
	c.anim_timer += dt
	if c.anim_timer >= total_dur {
		c.anim_timer = total_dur
		c.current_frame = f32(total_frames)
	} else {
		c.current_frame = ease(c.anim_timer, 0, f32(total_frames), total_dur)
	}
}

@(private = "file")
sync_facing :: proc(c: ^Companion, p: ^Player) {
	was_moving := c.moving
	c.moving = p.moving
	c.facing_left = p.facing_left

	if c.moving != was_moving {
		c.current_frame = 0
		c.anim_timer = 0
	}
}

@(private = "file")
sync_position :: proc(c: ^Companion, p: ^Player, dt: f32) {
	target_x: f32 = p.facing_left ? -COMPANION_OFFSET_X : COMPANION_OFFSET_X
	diff := target_x - c.current_offset_x
	c.current_offset_x += diff * COMPANION_LERP_SPEED * dt
	if diff < 0 ? -diff < 0.5 : diff < 0.5 {
		c.current_offset_x = target_x
	}
}

@(private = "file")
animate_loop :: proc(c: ^Companion, p: ^Player, dt: f32) {
	frames := c.moving ? c.frame_count : c.idle_frames
	if frames > 1 {
		c.anim_timer += dt
		if c.anim_timer >= ANIM_FRAME_TIME {
			c.anim_timer -= ANIM_FRAME_TIME
			c.current_frame += 1
			if int(c.current_frame) >= frames {
				c.current_frame = 0
			}
		}
	}
}

Quick_Attack_State :: enum {
	None,
	Attack1,
	Attack2,
}

update_quick_attack :: proc(p: ^Player, companion: ^Companion, scythe: ^Blood_Scythe, dt: f32) {
	if p.quick_attack_cooldown > 0 {
		p.quick_attack_cooldown -= dt
	}

	// Reset damage flag every frame; set to true only on the hit-frame transition
	p.quick_attack_damage_active = false

	weapons_inactive := companion.state == .Inactive && scythe.state == .Inactive
	attack_pressed := raylib.IsKeyPressed(.J) || raylib.IsMouseButtonPressed(.LEFT)

	switch p.quick_attack_state {
	case .None:
		if weapons_inactive && !p.dashing && p.quick_attack_cooldown <= 0 && attack_pressed {
			p.quick_attack_state = .Attack1
			p.quick_attack_frame = 0
			p.quick_attack_timer = 0
			p.chain_buffered = false
		}

	case .Attack1:
		prev := int(p.quick_attack_frame)
		qa_advance_oneshot(p, dt, raylib.EaseCubicOut)
		cur := int(p.quick_attack_frame)

		if prev < QUICK_ATTACK_HIT_FRAME && cur >= QUICK_ATTACK_HIT_FRAME {
			p.quick_attack_damage_active = true
		}

		// Buffer chain input during last 3 frames
		if cur >= p.quick_attack_frames - QUICK_ATTACK_CHAIN_WINDOW && attack_pressed {
			p.chain_buffered = true
		}

		if cur >= p.quick_attack_frames {
			if p.chain_buffered {
				p.quick_attack_state = .Attack2
				p.quick_attack_frame = 0
				p.quick_attack_timer = 0
			} else {
				p.quick_attack_state = .None
				p.quick_attack_cooldown = QUICK_ATTACK_COOLDOWN
			}
		}

	case .Attack2:
		prev := int(p.quick_attack_frame)
		qa_advance_oneshot(p, dt, raylib.EaseCubicOut)
		cur := int(p.quick_attack_frame)

		if prev < QUICK_ATTACK_HIT_FRAME && cur >= QUICK_ATTACK_HIT_FRAME {
			p.quick_attack_damage_active = true
		}

		if cur >= p.quick_attack_frames {
			p.quick_attack_state = .None
			p.quick_attack_cooldown = QUICK_ATTACK_COOLDOWN
		}
	}
}

get_quick_attack_rect :: proc(p: ^Player) -> raylib.Rectangle {
	offset_x: f32 = p.facing_left ? -16 : 16
	return {
		p.pos.x - f32(QUICK_ATTACK_SRC_SIZE) / 2 + offset_x,
		p.pos.y - f32(QUICK_ATTACK_SRC_SIZE),
		f32(QUICK_ATTACK_SRC_SIZE),
		f32(QUICK_ATTACK_SRC_SIZE),
	}
}

@(private = "file")
qa_advance_oneshot :: proc(p: ^Player, dt: f32, ease: proc(f32, f32, f32, f32) -> f32) {
	total_dur: f32 = f32(p.quick_attack_frames) / QUICK_ATTACK_FPS
	p.quick_attack_timer += dt
	if p.quick_attack_timer >= total_dur {
		p.quick_attack_timer = total_dur
		p.quick_attack_frame = f32(p.quick_attack_frames)
	} else {
		p.quick_attack_frame = ease(p.quick_attack_timer, 0, f32(p.quick_attack_frames), total_dur)
	}
}

