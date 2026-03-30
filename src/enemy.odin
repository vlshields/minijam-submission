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
	Dying,
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
	hit_by_companion:   bool,
	hit_by_scythe:      bool,
}

Enemy_Pool :: struct {
	enemies:      [MAX_ENEMIES]Enemy,
	count:        int,
	idle_tex:     raylib.Texture2D,
	move_tex:     raylib.Texture2D,
	death_tex:    raylib.Texture2D,
	idle_frames:  int,
	move_frames:  int,
	death_frames: int,
}

// ---------------------------------------------------------------------------
// Flameball
// ---------------------------------------------------------------------------

init_enemies :: proc(pool: ^Enemy_Pool) {
	pool.idle_tex = raylib.LoadTexture("assets/sprites/enemy_flameball_idle.png")
	pool.move_tex = raylib.LoadTexture("assets/sprites/enemy_flameball_move.png")
	pool.death_tex = raylib.LoadTexture("assets/sprites/enemy_flameball_death.png")
	pool.idle_frames = int(pool.idle_tex.width) / ENEMY_SRC_SIZE
	pool.move_frames = int(pool.move_tex.width) / ENEMY_SRC_SIZE
	pool.death_frames = int(pool.death_tex.width) / ENEMY_SRC_SIZE
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
	raylib.UnloadTexture(pool.death_tex)
}


update_enemies :: proc(
	pool: ^Enemy_Pool,
	player: ^Player,
	companion: ^Companion,
	scythe: ^Blood_Scythe,
	camera: ^raylib.Camera2D,
	map_data: ^dm.Dot_Map,
	bp: ^i32,
	scale: f32,
	sfx_hit: raylib.Sound,
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
		if e.state == .Dying {
			if e.damage_flash_timer > 0 {
				e.damage_flash_timer -= dt
			}
			if advance_enemy_oneshot(e, pool.death_frames, dt) {
				e.state = .Dead
			}
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
			e.vel.x = e.facing_left ? -ENEMY_SPEED * scale : ENEMY_SPEED * scale

			// Gravity
			e.vel.y += GRAVITY * dt
			if e.vel.y > MAX_FALL_SPEED {
				e.vel.y = MAX_FALL_SPEED
			}
			move_and_collide_enemy(e, map_data, dt)

			// Move animation (one-shot = one attack attempt)
			anim_done := advance_enemy_oneshot(e, pool.move_frames, dt)

			// Check collision with player
			if check_enemy_player_collision(e, player) && !player.dashing {
				player.hp -= ENEMY_DAMAGE * scale
				player.damage_flash_timer = DAMAGE_FLASH_DURATION
				raylib.PlaySound(sfx_hit)
				if player.hp < 0 {
					player.hp = 0
				}
				e.state = .Dying
				e.current_frame = 0
				e.anim_timer = 0
				e.vel = {}
				e.damage_flash_timer = 0
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

		case .Dying, .Dead:
		}

		// Reset hit flags when attacks end
		if companion.state != .Attacking { e.hit_by_companion = false }
		if scythe.state != .Attacking && scythe.state != .Quick_Attacking { e.hit_by_scythe = false }

		// Companion attack collision
		if e.state != .Dead && e.state != .Dying && companion.state == .Attacking && !e.hit_by_companion {
			comp_rect := get_companion_rect(companion, player)
			ehb := get_enemy_hitbox(e)
			if raylib.CheckCollisionRecs(comp_rect, ehb) {
				e.hp -= COMPANION_DAMAGE
				e.damage_flash_timer = DAMAGE_FLASH_DURATION
				e.hit_by_companion = true
				raylib.PlaySound(sfx_hit)
				if e.hp <= 0 {
					e.state = .Dying
					e.current_frame = 0
					e.anim_timer = 0
					e.vel = {}
					bp^ += BP_FLAMEBALL_KILL
				}
			}
		}

		// Blood scythe attack collision
		if e.state != .Dead && e.state != .Dying && (scythe.state == .Attacking || scythe.state == .Quick_Attacking) && !e.hit_by_scythe {
			scythe_rect := get_scythe_rect(scythe, player)
			ehb := get_enemy_hitbox(e)
			if raylib.CheckCollisionRecs(scythe_rect, ehb) {
				e.hp -= SCYTHE_DAMAGE
				e.damage_flash_timer = DAMAGE_FLASH_DURATION
				e.hit_by_scythe = true
				raylib.PlaySound(sfx_hit)
				if e.hp <= 0 {
					e.state = .Dying
					e.current_frame = 0
					e.anim_timer = 0
					e.vel = {}
					bp^ += BP_FLAMEBALL_KILL
				}
			}
		}

		// Quick attack collision
		if e.state != .Dead && e.state != .Dying && player.quick_attack_damage_active {
			attack_rect := get_quick_attack_rect(player)
			ehb := get_enemy_hitbox(e)
			if raylib.CheckCollisionRecs(attack_rect, ehb) {
				e.hp -= QUICK_ATTACK_DAMAGE
				e.damage_flash_timer = DAMAGE_FLASH_DURATION
				raylib.PlaySound(sfx_hit)
				if e.hp <= 0 {
					e.state = .Dying
					e.current_frame = 0
					e.anim_timer = 0
					e.vel = {}
					bp^ += BP_FLAMEBALL_KILL
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
		case .Dying:
			tex = pool.death_tex
			max_frames = pool.death_frames
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

// ---------------------------------------------------------------------------
// Devil
// ---------------------------------------------------------------------------

Devil_State :: enum {
	Idle,
	Pursuing,
	Attacking,
	Cooldown,
	Dying,
	Dead,
}

Devil :: struct {
	pos:                raylib.Vector2, // bottom-center
	vel:                raylib.Vector2,
	state:              Devil_State,
	aggroed:            bool,
	facing_left:        bool,
	on_ground:          bool,
	hp:                 f32,
	current_frame:      f32,
	anim_timer:         f32,
	state_timer:        f32,
	damage_flash_timer: f32,
	bolt_frame:         f32,
	bolt_anim_timer:    f32,
	bolt_active:        bool,
	bolt_dealt_damage:  bool,
	hit_by_companion:   bool,
	hit_by_scythe:      bool,
}

Devil_Pool :: struct {
	devils:        [MAX_DEVILS]Devil,
	count:         int,
	idle_tex:      raylib.Texture2D,
	move_tex:      raylib.Texture2D,
	attack_tex:    raylib.Texture2D,
	bolt_tex:      raylib.Texture2D,
	death_tex:     raylib.Texture2D,
	idle_frames:   int,
	move_frames:   int,
	attack_frames: int,
	bolt_frames:   int,
	death_frames:  int,
}


init_devils :: proc(pool: ^Devil_Pool) {
	pool.idle_tex = raylib.LoadTexture("assets/sprites/enemy_devil_idle.png")
	pool.move_tex = raylib.LoadTexture("assets/sprites/enemy_devil_move.png")
	pool.attack_tex = raylib.LoadTexture("assets/sprites/enemy_devil_attack.png")
	pool.bolt_tex = raylib.LoadTexture("assets/sprites/enemy_devil_flamebolt.png")
	pool.death_tex = raylib.LoadTexture("assets/sprites/enemy_devil_death.png")
	pool.idle_frames = int(pool.idle_tex.width) / DEVIL_SRC_SIZE
	pool.move_frames = int(pool.move_tex.width) / DEVIL_SRC_SIZE
	pool.attack_frames = int(pool.attack_tex.width) / DEVIL_SRC_SIZE
	pool.bolt_frames = int(pool.bolt_tex.width) / DEVIL_BOLT_SRC_SIZE
	pool.death_frames = int(pool.death_tex.width) / DEVIL_SRC_SIZE
	pool.count = 0
}

spawn_devil :: proc(pool: ^Devil_Pool, pos: raylib.Vector2) {
	if pool.count >= MAX_DEVILS {
		return
	}
	d := &pool.devils[pool.count]
	d.pos = pos
	d.vel = {}
	d.state = .Idle
	d.aggroed = false
	d.facing_left = false
	d.on_ground = false
	d.hp = DEVIL_HP
	d.current_frame = 0
	d.anim_timer = 0
	d.state_timer = 0
	d.damage_flash_timer = 0
	d.bolt_active = false
	d.bolt_dealt_damage = false
	pool.count += 1
}

unload_devils :: proc(pool: ^Devil_Pool) {
	raylib.UnloadTexture(pool.idle_tex)
	raylib.UnloadTexture(pool.move_tex)
	raylib.UnloadTexture(pool.attack_tex)
	raylib.UnloadTexture(pool.bolt_tex)
	raylib.UnloadTexture(pool.death_tex)
}

update_devils :: proc(
	pool: ^Devil_Pool,
	player: ^Player,
	companion: ^Companion,
	scythe: ^Blood_Scythe,
	camera: ^raylib.Camera2D,
	map_data: ^dm.Dot_Map,
	bp: ^i32,
	scale: f32,
	sfx_hit: raylib.Sound,
	dt: f32,
) {
	half_w := f32(SCREEN_WIDTH) / (2 * camera.zoom)
	half_h := f32(SCREEN_HEIGHT) / (2 * camera.zoom)
	view_rect := raylib.Rectangle{
		camera.target.x - half_w,
		camera.target.y - half_h,
		half_w * 2,
		half_h * 2,
	}

	for i := 0; i < pool.count; i += 1 {
		d := &pool.devils[i]
		if d.state == .Dead {
			continue
		}
		if d.state == .Dying {
			if d.damage_flash_timer > 0 {
				d.damage_flash_timer -= dt
			}
			if devil_advance_oneshot(d, pool.death_frames, dt) {
				d.state = .Dead
			}
			continue
		}

		if d.damage_flash_timer > 0 {
			d.damage_flash_timer -= dt
		}

		// Aggro — viewport + same platform (unless already aggroed)
		if !d.aggroed {
			dhb := devil_get_hitbox(d)
			in_view := raylib.CheckCollisionRecs(dhb, view_rect)
			same_level := d.on_ground && player.on_ground && abs(player.pos.y - d.pos.y) < 2
			if in_view && same_level {
				d.aggroed = true
				d.state = .Pursuing
				d.facing_left = player.pos.x < d.pos.x
				d.current_frame = 0
				d.anim_timer = 0
			}
		}

		switch d.state {
		case .Idle:
			devil_animate_loop(d, pool.move_frames, dt)
			d.vel.x = 0
			devil_apply_gravity(d, dt)
			devil_move_and_collide(d, map_data, dt)

		case .Pursuing:
			d.facing_left = player.pos.x < d.pos.x
			dist_x := abs(player.pos.x - d.pos.x)

			if dist_x <= DEVIL_ATTACK_RANGE {
				d.state = .Attacking
				d.current_frame = 0
				d.anim_timer = 0
				d.vel.x = 0
				d.bolt_active = true
				d.bolt_frame = 0
				d.bolt_anim_timer = 0
				d.bolt_dealt_damage = false
			} else {
				d.vel.x = d.facing_left ? -DEVIL_SPEED * scale : DEVIL_SPEED * scale
				devil_animate_loop(d, pool.move_frames, dt)
			}

			devil_apply_gravity(d, dt)
			devil_move_and_collide(d, map_data, dt)

		case .Attacking:
			d.vel.x = 0
			devil_apply_gravity(d, dt)
			devil_move_and_collide(d, map_data, dt)

			// Advance devil body animation
			done := devil_advance_oneshot(d, pool.attack_frames, dt)

			// Advance bolt animation
			devil_advance_bolt(d, pool.bolt_frames, dt)

			// Check bolt collision with player
			if d.bolt_active && !d.bolt_dealt_damage {
				bolt_rect := devil_get_bolt_rect(d)
				player_rect := get_hitbox(player)
				if raylib.CheckCollisionRecs(bolt_rect, player_rect) && !player.dashing {
					player.hp -= DEVIL_DAMAGE * scale
					player.damage_flash_timer = DAMAGE_FLASH_DURATION
					raylib.PlaySound(sfx_hit)
					if player.hp < 0 {
						player.hp = 0
					}
					d.bolt_dealt_damage = true
				}
			}

			if done {
				d.bolt_active = false
				d.state = .Cooldown
				d.state_timer = DEVIL_ATTACK_COOLDOWN
				d.current_frame = 0
				d.anim_timer = 0
			}

		case .Cooldown:
			devil_animate_loop(d, pool.move_frames, dt)
			d.vel.x = 0
			devil_apply_gravity(d, dt)
			devil_move_and_collide(d, map_data, dt)

			d.state_timer -= dt
			if d.state_timer <= 0 {
				d.state = .Pursuing
				d.current_frame = 0
				d.anim_timer = 0
			}

		case .Dying, .Dead:
		}

		// Reset hit flags when attacks end
		if companion.state != .Attacking { d.hit_by_companion = false }
		if scythe.state != .Attacking && scythe.state != .Quick_Attacking { d.hit_by_scythe = false }

		// Companion attack collision
		if d.state != .Dead && d.state != .Dying && companion.state == .Attacking && !d.hit_by_companion {
			comp_rect := get_companion_rect(companion, player)
			dhb := devil_get_hitbox(d)
			if raylib.CheckCollisionRecs(comp_rect, dhb) {
				d.hp -= COMPANION_DAMAGE
				d.damage_flash_timer = DAMAGE_FLASH_DURATION
				d.hit_by_companion = true
				raylib.PlaySound(sfx_hit)
				if d.hp <= 0 {
					d.state = .Dying
					d.current_frame = 0
					d.anim_timer = 0
					d.vel = {}
					d.bolt_active = false
					bp^ += BP_DEVIL_KILL
				}
			}
		}

		// Blood scythe collision
		if d.state != .Dead && d.state != .Dying && (scythe.state == .Attacking || scythe.state == .Quick_Attacking) && !d.hit_by_scythe {
			scythe_rect := get_scythe_rect(scythe, player)
			dhb := devil_get_hitbox(d)
			if raylib.CheckCollisionRecs(scythe_rect, dhb) {
				d.hp -= SCYTHE_DAMAGE
				d.damage_flash_timer = DAMAGE_FLASH_DURATION
				d.hit_by_scythe = true
				raylib.PlaySound(sfx_hit)
				if d.hp <= 0 {
					d.state = .Dying
					d.current_frame = 0
					d.anim_timer = 0
					d.vel = {}
					d.bolt_active = false
					bp^ += BP_DEVIL_KILL
				}
			}
		}

		// Quick attack collision
		if d.state != .Dead && d.state != .Dying && player.quick_attack_damage_active {
			attack_rect := get_quick_attack_rect(player)
			dhb := devil_get_hitbox(d)
			if raylib.CheckCollisionRecs(attack_rect, dhb) {
				d.hp -= QUICK_ATTACK_DAMAGE
				d.damage_flash_timer = DAMAGE_FLASH_DURATION
				raylib.PlaySound(sfx_hit)
				if d.hp <= 0 {
					d.state = .Dying
					d.current_frame = 0
					d.anim_timer = 0
					d.vel = {}
					d.bolt_active = false
					bp^ += BP_DEVIL_KILL
				}
			}
		}

		// Safety: kill if fallen below map
		map_bottom := f32(map_data.height) * TILE_SIZE + 64
		if d.pos.y > map_bottom {
			d.state = .Dead
		}
	}
}


draw_devils :: proc(pool: ^Devil_Pool, white_shader: raylib.Shader) {
	for i := 0; i < pool.count; i += 1 {
		d := &pool.devils[i]
		if d.state == .Dead {
			continue
		}

		// Draw devil body
		tex: raylib.Texture2D
		max_frames: int
		switch d.state {
		case .Attacking:
			tex = pool.attack_tex
			max_frames = pool.attack_frames
		case .Idle, .Cooldown:
			tex = pool.idle_tex
			max_frames = pool.idle_frames
		case .Pursuing:
			tex = pool.move_tex
			max_frames = pool.move_frames
		case .Dying:
			tex = pool.death_tex
			max_frames = pool.death_frames
		case .Dead:
			continue
		}

		frame := int(d.current_frame)
		if frame >= max_frames {
			frame = max_frames - 1
		}

		src := raylib.Rectangle{
			f32(frame * DEVIL_SRC_SIZE), 0,
			d.facing_left ? -f32(DEVIL_SRC_SIZE) : f32(DEVIL_SRC_SIZE),
			f32(DEVIL_SRC_SIZE),
		}
		dst := raylib.Rectangle{
			d.pos.x - f32(DEVIL_DRAW_SIZE) / 2,
			d.pos.y - f32(DEVIL_DRAW_SIZE),
			f32(DEVIL_DRAW_SIZE),
			f32(DEVIL_DRAW_SIZE),
		}
		if d.damage_flash_timer > 0 {
			raylib.BeginShaderMode(white_shader)
		}
		raylib.DrawTexturePro(tex, src, dst, {0, 0}, 0, raylib.WHITE)
		if d.damage_flash_timer > 0 {
			raylib.EndShaderMode()
		}

		// Draw flame bolt effect in front of devil
		if d.bolt_active {
			bf := int(d.bolt_frame)
			if bf >= pool.bolt_frames {
				bf = pool.bolt_frames - 1
			}

			bolt_src := raylib.Rectangle{
				f32(bf * DEVIL_BOLT_SRC_SIZE), 0,
				d.facing_left ? -f32(DEVIL_BOLT_SRC_SIZE) : f32(DEVIL_BOLT_SRC_SIZE),
				f32(DEVIL_BOLT_SRC_SIZE),
			}
			bolt_dst := devil_get_bolt_draw_rect(d)
			raylib.DrawTexturePro(pool.bolt_tex, bolt_src, bolt_dst, {0, 0}, 0, raylib.WHITE)
		}
	}
}


@(private = "file")
devil_get_hitbox :: proc(d: ^Devil) -> raylib.Rectangle {
	return {
		d.pos.x - f32(DEVIL_HITBOX_W) / 2,
		d.pos.y - f32(DEVIL_HITBOX_H),
		f32(DEVIL_HITBOX_W),
		f32(DEVIL_HITBOX_H),
	}
}

@(private = "file")
devil_get_bolt_draw_rect :: proc(d: ^Devil) -> raylib.Rectangle {
	// Position bolt sprite in front of the devil, centered on its body
	bolt_x: f32 = d.facing_left \
		? d.pos.x - f32(DEVIL_DRAW_SIZE) / 2 - f32(DEVIL_BOLT_SRC_SIZE) \
		: d.pos.x + f32(DEVIL_DRAW_SIZE) / 2
	return {
		bolt_x,
		d.pos.y - f32(DEVIL_DRAW_SIZE) / 2 - f32(DEVIL_BOLT_SRC_SIZE) / 2,
		f32(DEVIL_BOLT_SRC_SIZE),
		f32(DEVIL_BOLT_SRC_SIZE),
	}
}

@(private = "file")
devil_get_bolt_rect :: proc(d: ^Devil) -> raylib.Rectangle {
	return devil_get_bolt_draw_rect(d)
}

@(private = "file")
devil_apply_gravity :: proc(d: ^Devil, dt: f32) {
	d.vel.y += GRAVITY * dt
	if d.vel.y > MAX_FALL_SPEED {
		d.vel.y = MAX_FALL_SPEED
	}
}

@(private = "file")
devil_move_and_collide :: proc(d: ^Devil, map_data: ^dm.Dot_Map, dt: f32) {
	// Move X
	d.pos.x += d.vel.x * dt
	hb := devil_get_hitbox(d)
	if check_rect_solid(map_data, hb) {
		if d.vel.x > 0 {
			tile_x := int(hb.x + hb.width) / TILE_SIZE
			d.pos.x = f32(tile_x * TILE_SIZE) - f32(DEVIL_HITBOX_W) / 2
		} else if d.vel.x < 0 {
			tile_x := int(hb.x) / TILE_SIZE
			d.pos.x = f32((tile_x + 1) * TILE_SIZE) + f32(DEVIL_HITBOX_W) / 2
		}
		d.vel.x = 0
	}

	// Move Y
	d.pos.y += d.vel.y * dt
	hb = devil_get_hitbox(d)
	d.on_ground = false
	if check_rect_solid(map_data, hb) {
		if d.vel.y > 0 {
			tile_y := int(hb.y + hb.height) / TILE_SIZE
			d.pos.y = f32(tile_y * TILE_SIZE)
			d.on_ground = true
		} else if d.vel.y < 0 {
			tile_y := int(hb.y) / TILE_SIZE
			d.pos.y = f32((tile_y + 1) * TILE_SIZE) + f32(DEVIL_HITBOX_H)
		}
		d.vel.y = 0
	}
}

@(private = "file")
devil_animate_loop :: proc(d: ^Devil, total_frames: int, dt: f32) {
	if total_frames <= 1 {
		return
	}
	d.anim_timer += dt
	if d.anim_timer >= ANIM_FRAME_TIME {
		d.anim_timer -= ANIM_FRAME_TIME
		d.current_frame += 1
		if int(d.current_frame) >= total_frames {
			d.current_frame = 0
		}
	}
}

@(private = "file")
devil_advance_oneshot :: proc(d: ^Devil, total_frames: int, dt: f32) -> bool {
	frame_dur: f32 = 1.0 / DEVIL_ANIM_FPS
	d.anim_timer += dt
	if d.anim_timer >= frame_dur {
		d.anim_timer -= frame_dur
		d.current_frame += 1
		if int(d.current_frame) >= total_frames {
			return true
		}
	}
	return false
}

@(private = "file")
devil_advance_bolt :: proc(d: ^Devil, total_frames: int, dt: f32) {
	if total_frames <= 1 {
		return
	}
	frame_dur: f32 = 1.0 / DEVIL_ANIM_FPS
	d.bolt_anim_timer += dt
	if d.bolt_anim_timer >= frame_dur {
		d.bolt_anim_timer -= frame_dur
		d.bolt_frame += 1
		if int(d.bolt_frame) >= total_frames {
			d.bolt_frame = 0
		}
	}
}

FW_State :: enum {
	Idle,
	Patrol,
	Attack_Windup,
	Attacking,
	Attack_End,
	Cooldown,
	Dying,
	Dead,
}

Flamewarden :: struct {
	pos:                raylib.Vector2, // bottom-center
	vel:                raylib.Vector2,
	state:              FW_State,
	aggroed:            bool,
	facing_left:        bool,
	on_ground:          bool,
	hp:                 f32,
	current_frame:      f32,
	anim_timer:         f32,
	state_timer:        f32,
	damage_flash_timer: f32,
	patrol_dir:         f32, // -1 or +1
	flame_pos:          raylib.Vector2, // where the ground flame spawns
	flame_frame:        f32,
	flame_anim_timer:   f32,
	flame_active:       bool,
	flame_dealt_damage: bool,
	hit_by_companion:   bool,
	hit_by_scythe:      bool,
}

FW_Pool :: struct {
	wardens:              [MAX_FLAMEWARDENS]Flamewarden,
	count:                int,
	idle_tex:             raylib.Texture2D,
	move_tex:             raylib.Texture2D,
	isattacking_tex:      raylib.Texture2D,
	flame_start_tex:      raylib.Texture2D,
	flame_loop_tex:       raylib.Texture2D,
	flame_end_tex:        raylib.Texture2D,
	death_tex:            raylib.Texture2D,
	idle_frames:          int,
	move_frames:          int,
	isattacking_frames:   int,
	flame_start_frames:   int,
	flame_loop_frames:    int,
	flame_end_frames:     int,
	death_frames:         int,
}

// ---------------------------------------------------------------------------
// Lifecycle
// ---------------------------------------------------------------------------

init_flamewardens :: proc(pool: ^FW_Pool) {
	pool.idle_tex = raylib.LoadTexture("assets/sprites/enemy_flamewarden_idle.png")
	pool.move_tex = raylib.LoadTexture("assets/sprites/enemy_flamewarden_move.png")
	pool.isattacking_tex = raylib.LoadTexture("assets/sprites/enemy_flamewarden_isattacking.png")
	pool.flame_start_tex = raylib.LoadTexture("assets/sprites/enemy_flamewarden_attack_start.png")
	pool.flame_loop_tex = raylib.LoadTexture("assets/sprites/enemy_flamewarden_attack_loop.png")
	pool.flame_end_tex = raylib.LoadTexture("assets/sprites/enemy_flamewarden_attack_end.png")

	pool.death_tex = raylib.LoadTexture("assets/sprites/enemy_flamewarden_death.png")
	pool.idle_frames = int(pool.idle_tex.width) / FW_SRC_SIZE
	pool.move_frames = int(pool.move_tex.width) / FW_SRC_SIZE
	pool.isattacking_frames = int(pool.isattacking_tex.width) / FW_SRC_SIZE
	pool.flame_start_frames = int(pool.flame_start_tex.width) / FW_FLAME_SRC_W
	pool.flame_loop_frames = int(pool.flame_loop_tex.width) / FW_FLAME_SRC_W
	pool.flame_end_frames = int(pool.flame_end_tex.width) / FW_FLAME_SRC_W
	pool.death_frames = int(pool.death_tex.width) / FW_SRC_SIZE
	pool.count = 0
}

spawn_flamewarden :: proc(pool: ^FW_Pool, pos: raylib.Vector2) {
	if pool.count >= MAX_FLAMEWARDENS {
		return
	}
	fw := &pool.wardens[pool.count]
	fw.pos = pos
	fw.vel = {}
	fw.state = .Idle
	fw.aggroed = false
	fw.facing_left = false
	fw.on_ground = false
	fw.hp = FW_HP
	fw.current_frame = 0
	fw.anim_timer = 0
	fw.state_timer = 0
	fw.damage_flash_timer = 0
	fw.patrol_dir = 1
	fw.flame_active = false
	fw.flame_dealt_damage = false
	pool.count += 1
}

unload_flamewardens :: proc(pool: ^FW_Pool) {
	raylib.UnloadTexture(pool.idle_tex)
	raylib.UnloadTexture(pool.move_tex)
	raylib.UnloadTexture(pool.isattacking_tex)
	raylib.UnloadTexture(pool.flame_start_tex)
	raylib.UnloadTexture(pool.flame_loop_tex)
	raylib.UnloadTexture(pool.flame_end_tex)
	raylib.UnloadTexture(pool.death_tex)
}

// ---------------------------------------------------------------------------
// Update
// ---------------------------------------------------------------------------

update_flamewardens :: proc(
	pool: ^FW_Pool,
	player: ^Player,
	companion: ^Companion,
	scythe: ^Blood_Scythe,
	camera: ^raylib.Camera2D,
	map_data: ^dm.Dot_Map,
	bp: ^i32,
	scale: f32,
	sfx_hit: raylib.Sound,
	dt: f32,
) {
	half_w := f32(SCREEN_WIDTH) / (2 * camera.zoom)
	half_h := f32(SCREEN_HEIGHT) / (2 * camera.zoom)
	view_rect := raylib.Rectangle{
		camera.target.x - half_w,
		camera.target.y - half_h,
		half_w * 2,
		half_h * 2,
	}

	for i := 0; i < pool.count; i += 1 {
		fw := &pool.wardens[i]
		if fw.state == .Dead {
			continue
		}
		if fw.state == .Dying {
			if fw.damage_flash_timer > 0 {
				fw.damage_flash_timer -= dt
			}
			if fw_advance_oneshot(fw, pool.death_frames, dt) {
				fw.state = .Dead
			}
			continue
		}

		if fw.damage_flash_timer > 0 {
			fw.damage_flash_timer -= dt
		}

		// Aggro check
		if !fw.aggroed {
			fhb := get_fw_hitbox(fw)
			in_view := raylib.CheckCollisionRecs(fhb, view_rect)
			if in_view {
				fw.aggroed = true
				fw.state = .Patrol
				fw.current_frame = 0
				fw.anim_timer = 0
			}
		}

		// Can this warden see the player to attack?
		can_attack := false
		if fw.aggroed && fw.state == .Patrol {
			fhb := get_fw_hitbox(fw)
			in_view := raylib.CheckCollisionRecs(fhb, view_rect)
			// Once aggroed, can attack at infinite range; otherwise viewport only
			can_attack = in_view || fw.aggroed
		}

		switch fw.state {
		case .Idle:
			fw_animate_loop(fw, pool.idle_frames, dt)
			fw.vel.x = 0
			fw_apply_gravity(fw, dt)
			fw_move_and_collide(fw, map_data, dt)

		case .Patrol:
			fw_animate_loop(fw, pool.move_frames, dt)
			fw.facing_left = fw.patrol_dir < 0

			fw.vel.x = fw.patrol_dir * FW_PATROL_SPEED * scale
			fw_apply_gravity(fw, dt)
			fw_move_and_collide(fw, map_data, dt)

			// Turn around at walls or platform edges
			fhb := get_fw_hitbox(fw)
			// Check wall ahead
			probe_x := fw.patrol_dir > 0 ? fhb.x + fhb.width + 1 : fhb.x - 1
			probe_rect := raylib.Rectangle{probe_x, fhb.y, 1, fhb.height}
			hit_wall := check_rect_solid(map_data, probe_rect)

			// Check floor ahead
			floor_x := fw.patrol_dir > 0 ? fhb.x + fhb.width + 2 : fhb.x - 2
			floor_rect := raylib.Rectangle{floor_x, fhb.y + fhb.height + 1, 1, 1}
			no_floor := fw.on_ground && !check_rect_solid(map_data, floor_rect)

			if hit_wall || no_floor {
				fw.patrol_dir = -fw.patrol_dir
				fw.vel.x = 0
			}

			// Try to attack
			if can_attack {
				fw.state = .Attack_Windup
				fw.current_frame = 0
				fw.anim_timer = 0
				fw.flame_frame = 0
				fw.flame_anim_timer = 0
				fw.flame_active = true
				fw.flame_dealt_damage = false
				fw.vel.x = 0
				// Snap flame to player's current X, on the nearest ground surface
				ground_y := fw_find_ground(player.pos.x, player.pos.y, map_data)
				if ground_y < 0 {
					// No ground found — skip attack
					continue
				}
				fw.flame_pos = raylib.Vector2{player.pos.x, ground_y}
				fw.facing_left = player.pos.x < fw.pos.x
			}

		case .Attack_Windup:
			// Flame spawn animation at target position, warden plays isattacking
			fw_animate_loop(fw, pool.isattacking_frames, dt)
			fw.vel.x = 0
			fw_apply_gravity(fw, dt)
			fw_move_and_collide(fw, map_data, dt)

			// Advance flame spawn anim
			done := fw_advance_flame_oneshot(fw, pool.flame_start_frames, dt)
			if done {
				fw.state = .Attacking
				fw.flame_frame = 0
				fw.flame_anim_timer = 0
				fw.state_timer = 0
			}

		case .Attacking:
			// Flame loop + warden isattacking loop
			fw_animate_loop(fw, pool.isattacking_frames, dt)
			fw.vel.x = 0
			fw_apply_gravity(fw, dt)
			fw_move_and_collide(fw, map_data, dt)

			// Track player position — slide flame toward player's X
			target_x := player.pos.x
			diff := target_x - fw.flame_pos.x
			max_move := FW_FLAME_TRACK_SPEED * scale * dt
			if diff > max_move {
				fw.flame_pos.x += max_move
			} else if diff < -max_move {
				fw.flame_pos.x -= max_move
			} else {
				fw.flame_pos.x = target_x
			}
			// Update ground Y at new X
			new_ground := fw_find_ground(fw.flame_pos.x, fw.flame_pos.y - f32(FW_FLAME_SRC_H), map_data)
			if new_ground >= 0 {
				fw.flame_pos.y = new_ground
			}

			// Loop the flame animation for a fixed duration
			fw_animate_flame_loop(fw, pool.flame_loop_frames, dt)
			fw.state_timer += dt

			// Check flame collision with player
			if !fw.flame_dealt_damage {
				flame_rect := get_flame_hitbox(fw)
				player_rect := get_hitbox(player)
				if raylib.CheckCollisionRecs(flame_rect, player_rect) && !player.dashing {
					player.hp -= FW_FLAME_DAMAGE * scale
					player.damage_flash_timer = DAMAGE_FLASH_DURATION
					raylib.PlaySound(sfx_hit)
					if player.hp < 0 {
						player.hp = 0
					}
					fw.flame_dealt_damage = true
				}
			}

			if fw.state_timer >= FW_FLAME_LOOP_DURATION {
				fw.state = .Attack_End
				fw.flame_frame = 0
				fw.flame_anim_timer = 0
			}

		case .Attack_End:
			fw_animate_loop(fw, pool.idle_frames, dt)
			fw.vel.x = 0
			fw_apply_gravity(fw, dt)
			fw_move_and_collide(fw, map_data, dt)

			done := fw_advance_flame_oneshot(fw, pool.flame_end_frames, dt)
			if done {
				fw.flame_active = false
				fw.state = .Cooldown
				fw.state_timer = FW_ATTACK_COOLDOWN
				fw.current_frame = 0
				fw.anim_timer = 0
			}

		case .Cooldown:
			fw_animate_loop(fw, pool.idle_frames, dt)
			fw.vel.x = 0
			fw_apply_gravity(fw, dt)
			fw_move_and_collide(fw, map_data, dt)

			fw.state_timer -= dt
			if fw.state_timer <= 0 {
				fw.state = .Patrol
				fw.current_frame = 0
				fw.anim_timer = 0
			}

		case .Dying, .Dead:
		}

		// Reset hit flags when attacks end
		if companion.state != .Attacking { fw.hit_by_companion = false }
		if scythe.state != .Attacking && scythe.state != .Quick_Attacking { fw.hit_by_scythe = false }

		// Companion attack collision
		if fw.state != .Dead && fw.state != .Dying && companion.state == .Attacking && !fw.hit_by_companion {
			comp_rect := get_companion_rect(companion, player)
			fhb := get_fw_hitbox(fw)
			if raylib.CheckCollisionRecs(comp_rect, fhb) {
				fw.hp -= COMPANION_DAMAGE
				fw.damage_flash_timer = DAMAGE_FLASH_DURATION
				fw.hit_by_companion = true
				raylib.PlaySound(sfx_hit)
				if fw.hp <= 0 {
					fw.state = .Dying
					fw.current_frame = 0
					fw.anim_timer = 0
					fw.vel = {}
					fw.flame_active = false
					bp^ += BP_FLAMEWARDEN_KILL
				}
			}
		}

		// Blood scythe attack collision
		if fw.state != .Dead && fw.state != .Dying && (scythe.state == .Attacking || scythe.state == .Quick_Attacking) && !fw.hit_by_scythe {
			scythe_rect := get_scythe_rect(scythe, player)
			fhb := get_fw_hitbox(fw)
			if raylib.CheckCollisionRecs(scythe_rect, fhb) {
				fw.hp -= SCYTHE_DAMAGE
				fw.damage_flash_timer = DAMAGE_FLASH_DURATION
				fw.hit_by_scythe = true
				raylib.PlaySound(sfx_hit)
				if fw.hp <= 0 {
					fw.state = .Dying
					fw.current_frame = 0
					fw.anim_timer = 0
					fw.vel = {}
					fw.flame_active = false
					bp^ += BP_FLAMEWARDEN_KILL
				}
			}
		}

		// Quick attack collision
		if fw.state != .Dead && fw.state != .Dying && player.quick_attack_damage_active {
			attack_rect := get_quick_attack_rect(player)
			fhb := get_fw_hitbox(fw)
			if raylib.CheckCollisionRecs(attack_rect, fhb) {
				fw.hp -= QUICK_ATTACK_DAMAGE
				fw.damage_flash_timer = DAMAGE_FLASH_DURATION
				raylib.PlaySound(sfx_hit)
				if fw.hp <= 0 {
					fw.state = .Dying
					fw.current_frame = 0
					fw.anim_timer = 0
					fw.vel = {}
					fw.flame_active = false
					bp^ += BP_FLAMEWARDEN_KILL
				}
			}
		}

		// Safety: kill if fallen below map
		map_bottom := f32(map_data.height) * TILE_SIZE + 64
		if fw.pos.y > map_bottom {
			fw.state = .Dead
		}
	}
}

// ---------------------------------------------------------------------------
// Draw
// ---------------------------------------------------------------------------

draw_flamewardens :: proc(pool: ^FW_Pool, white_shader: raylib.Shader) {
	for i := 0; i < pool.count; i += 1 {
		fw := &pool.wardens[i]
		if fw.state == .Dead {
			continue
		}

		// Draw the warden body
		tex: raylib.Texture2D
		max_frames: int
		switch fw.state {
		case .Attack_Windup, .Attacking:
			tex = pool.isattacking_tex
			max_frames = pool.isattacking_frames
		case .Patrol:
			tex = pool.move_tex
			max_frames = pool.move_frames
		case .Idle, .Cooldown, .Attack_End:
			tex = pool.idle_tex
			max_frames = pool.idle_frames
		case .Dying:
			tex = pool.death_tex
			max_frames = pool.death_frames
		case .Dead:
			continue
		}

		frame := int(fw.current_frame)
		if frame >= max_frames {
			frame = max_frames - 1
		}

		src := raylib.Rectangle{
			f32(frame * FW_SRC_SIZE), 0,
			fw.facing_left ? -f32(FW_SRC_SIZE) : f32(FW_SRC_SIZE),
			f32(FW_SRC_SIZE),
		}
		dst := raylib.Rectangle{
			fw.pos.x - f32(FW_SRC_SIZE) / 2,
			fw.pos.y - f32(FW_SRC_SIZE),
			f32(FW_SRC_SIZE),
			f32(FW_SRC_SIZE),
		}
		if fw.damage_flash_timer > 0 {
			raylib.BeginShaderMode(white_shader)
		}
		raylib.DrawTexturePro(tex, src, dst, {0, 0}, 0, raylib.WHITE)
		if fw.damage_flash_timer > 0 {
			raylib.EndShaderMode()
		}

		// Draw flame effect
		if fw.flame_active {
			flame_tex: raylib.Texture2D
			flame_max: int
			switch fw.state {
			case .Attack_Windup:
				flame_tex = pool.flame_start_tex
				flame_max = pool.flame_start_frames
			case .Attacking:
				flame_tex = pool.flame_loop_tex
				flame_max = pool.flame_loop_frames
			case .Attack_End:
				flame_tex = pool.flame_end_tex
				flame_max = pool.flame_end_frames
			case .Idle, .Patrol, .Cooldown, .Dying, .Dead:
				continue
			}

			ff := int(fw.flame_frame)
			// Wrap for loop phase
			if fw.state == .Attacking && flame_max > 0 {
				ff = ff % flame_max
			}
			if ff >= flame_max {
				ff = flame_max - 1
			}

			flame_src := raylib.Rectangle{
				f32(ff * FW_FLAME_SRC_W), 0,
				f32(FW_FLAME_SRC_W),
				f32(FW_FLAME_SRC_H),
			}
			flame_dst := raylib.Rectangle{
				fw.flame_pos.x - f32(FW_FLAME_SRC_W) / 2,
				fw.flame_pos.y - f32(FW_FLAME_SRC_H),
				f32(FW_FLAME_SRC_W),
				f32(FW_FLAME_SRC_H),
			}
			raylib.DrawTexturePro(flame_tex, flame_src, flame_dst, {0, 0}, 0, raylib.WHITE)
		}
	}
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

@(private = "file")
get_fw_hitbox :: proc(fw: ^Flamewarden) -> raylib.Rectangle {
	return {
		fw.pos.x - f32(FW_HITBOX_W) / 2,
		fw.pos.y - f32(FW_HITBOX_H),
		f32(FW_HITBOX_W),
		f32(FW_HITBOX_H),
	}
}

@(private = "file")
fw_find_ground :: proc(x: f32, start_y: f32, map_data: ^dm.Dot_Map) -> f32 {
	tx := int(x) / TILE_SIZE
	start_ty := int(start_y) / TILE_SIZE
	if tx < 0 || tx >= map_data.width {
		return -1
	}
	// Scan downward from player's tile row
	for ty := start_ty; ty < map_data.height; ty += 1 {
		if ty < 0 {
			continue
		}
		if is_solid(map_data, tx, ty) {
			return f32(ty * TILE_SIZE) // top of the solid tile
		}
	}
	return -1
}

@(private = "file")
get_flame_hitbox :: proc(fw: ^Flamewarden) -> raylib.Rectangle {
	return {
		fw.flame_pos.x - f32(FW_FLAME_SRC_W) / 2,
		fw.flame_pos.y - f32(FW_FLAME_SRC_H),
		f32(FW_FLAME_SRC_W),
		f32(FW_FLAME_SRC_H),
	}
}

@(private = "file")
fw_apply_gravity :: proc(fw: ^Flamewarden, dt: f32) {
	fw.vel.y += GRAVITY * dt
	if fw.vel.y > MAX_FALL_SPEED {
		fw.vel.y = MAX_FALL_SPEED
	}
}

@(private = "file")
fw_move_and_collide :: proc(fw: ^Flamewarden, map_data: ^dm.Dot_Map, dt: f32) {
	// Move X
	fw.pos.x += fw.vel.x * dt
	hb := get_fw_hitbox(fw)
	if check_rect_solid(map_data, hb) {
		if fw.vel.x > 0 {
			tile_x := int(hb.x + hb.width) / TILE_SIZE
			fw.pos.x = f32(tile_x * TILE_SIZE) - f32(FW_HITBOX_W) / 2
		} else if fw.vel.x < 0 {
			tile_x := int(hb.x) / TILE_SIZE
			fw.pos.x = f32((tile_x + 1) * TILE_SIZE) + f32(FW_HITBOX_W) / 2
		}
		fw.vel.x = 0
	}

	// Move Y
	fw.pos.y += fw.vel.y * dt
	hb = get_fw_hitbox(fw)
	fw.on_ground = false
	if check_rect_solid(map_data, hb) {
		if fw.vel.y > 0 {
			tile_y := int(hb.y + hb.height) / TILE_SIZE
			fw.pos.y = f32(tile_y * TILE_SIZE)
			fw.on_ground = true
		} else if fw.vel.y < 0 {
			tile_y := int(hb.y) / TILE_SIZE
			fw.pos.y = f32((tile_y + 1) * TILE_SIZE) + f32(FW_HITBOX_H)
		}
		fw.vel.y = 0
	}
}

@(private = "file")
fw_advance_oneshot :: proc(fw: ^Flamewarden, total_frames: int, dt: f32) -> bool {
	frame_dur: f32 = 1.0 / FW_ANIM_FPS
	fw.anim_timer += dt
	if fw.anim_timer >= frame_dur {
		fw.anim_timer -= frame_dur
		fw.current_frame += 1
		if int(fw.current_frame) >= total_frames {
			return true
		}
	}
	return false
}

@(private = "file")
fw_animate_loop :: proc(fw: ^Flamewarden, total_frames: int, dt: f32) {
	if total_frames <= 1 {
		return
	}
	fw.anim_timer += dt
	if fw.anim_timer >= ANIM_FRAME_TIME {
		fw.anim_timer -= ANIM_FRAME_TIME
		fw.current_frame += 1
		if int(fw.current_frame) >= total_frames {
			fw.current_frame = 0
		}
	}
}

@(private = "file")
fw_animate_flame_loop :: proc(fw: ^Flamewarden, total_frames: int, dt: f32) {
	if total_frames <= 1 {
		return
	}
	frame_dur: f32 = 1.0 / FW_ANIM_FPS
	fw.flame_anim_timer += dt
	if fw.flame_anim_timer >= frame_dur {
		fw.flame_anim_timer -= frame_dur
		fw.flame_frame += 1
		if int(fw.flame_frame) >= total_frames {
			fw.flame_frame = 0
		}
	}
}

@(private = "file")
fw_advance_flame_oneshot :: proc(fw: ^Flamewarden, total_frames: int, dt: f32) -> bool {
	frame_dur: f32 = 1.0 / FW_ANIM_FPS
	fw.flame_anim_timer += dt
	if fw.flame_anim_timer >= frame_dur {
		fw.flame_anim_timer -= frame_dur
		fw.flame_frame += 1
		if int(fw.flame_frame) >= total_frames {
			return true
		}
	}
	return false
}
