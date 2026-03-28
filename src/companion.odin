package game

import "vendor:raylib"

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

update_companion :: proc(c: ^Companion, p: ^Player, dt: f32) {
	// Attack cooldown ticks in all states
	if c.attack_cooldown > 0 {
		c.attack_cooldown -= dt
	}

	switch c.state {
	case .Inactive:
		if raylib.IsKeyPressed(.F) {
			c.state = .Spawning
			c.facing_left = p.facing_left
			c.current_offset_x = p.facing_left ? -COMPANION_OFFSET_X : COMPANION_OFFSET_X
			c.current_frame = 0
			c.anim_timer = 0
		}

	case .Spawning:
		advance_oneshot(c, c.spawn_frames, dt)
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
		advance_oneshot(c, c.attack_frames, dt)
		sync_position(c, p, dt)
		if int(c.current_frame) >= c.attack_frames {
			c.state = .Idle
			c.current_frame = 0
			c.anim_timer = 0
			c.attack_cooldown = COMPANION_ATTACK_COOLDOWN
		}

	case .Despawning:
		advance_oneshot(c, c.despawn_frames, dt)
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
advance_oneshot :: proc(c: ^Companion, total_frames: int, dt: f32) {
	frame_dur: f32 = 1.0 / COMPANION_ONESHOT_FPS
	c.anim_timer += dt
	if c.anim_timer >= frame_dur {
		c.anim_timer -= frame_dur
		c.current_frame += 1
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
