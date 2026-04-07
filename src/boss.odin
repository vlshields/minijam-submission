package game

import "vendor:raylib"
import dm "../dotmap"

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

ED_Phase :: enum {
	Phase1, // breath only
	Phase2, // breath + meteors
	Phase3, // breath + meteors + magma
}

ED_State :: enum {
	Idle,
	Pursuing,
	Breathing,
	Teleporting,
	Dying,
	Dead,
}

ED_Breath_Phase :: enum {
	Start,
	Loop,
	End,
}

ED_Meteor_Phase :: enum {
	Falling,
	Impact,
}

ED_Magma_Phase :: enum {
	Starting,
	Looping,
	Ending,
}

ED_Meteor :: struct {
	active:       bool,
	phase:        ED_Meteor_Phase,
	target_pos:   raylib.Vector2,
	pos:          raylib.Vector2,
	frame:        f32,
	anim_timer:   f32,
	dealt_damage: bool,
}

ED_Magma :: struct {
	active:       bool,
	phase:        ED_Magma_Phase,
	pos:          raylib.Vector2,
	frame:        f32,
	anim_timer:   f32,
	state_timer:  f32,
	dealt_damage: bool,
}

Ember_Demon :: struct {
	active:                bool,
	pos:                   raylib.Vector2,
	vel:                   raylib.Vector2,
	state:                 ED_State,
	phase:                 ED_Phase,
	facing_left:           bool,
	on_ground:             bool,
	hp:                    f32,
	current_frame:         f32,
	anim_timer:            f32,
	state_timer:           f32,
	damage_flash_timer:    f32,
	breath_cooldown:       f32,
	damage_cooldown_timer: f32,

	// Breath effect
	breath_active:         bool,
	breath_phase:          ED_Breath_Phase,
	breath_frame:          f32,
	breath_anim_timer:     f32,
	breath_state_timer:    f32,
	breath_dealt_damage:   bool,

	// Teleport
	teleport_points:       [ED_MAX_TELEPORT_POINTS]raylib.Vector2,
	teleport_count:        int,
	consecutive_damage:    f32,

	// Phase 2/3 attack timers
	meteor_timer:          f32,
	magma_timer:           f32,

	// Active effects
	meteors:               [ED_MAX_METEORS]ED_Meteor,
	magmas:                [ED_MAX_MAGMA]ED_Magma,

	hit_by_companion:      bool,
	hit_by_scythe:         bool,

	// Textures
	move_tex:              raylib.Texture2D,
	attack_tex:            raylib.Texture2D,
	breath_start_tex:      raylib.Texture2D,
	breath_loop_tex:       raylib.Texture2D,
	breath_end_tex:        raylib.Texture2D,
	meteor_fall_tex:       raylib.Texture2D,
	meteor_impact_tex:     raylib.Texture2D,
	magma_start_tex:       raylib.Texture2D,
	magma_loop_tex:        raylib.Texture2D,
	magma_end_tex:         raylib.Texture2D,

	// Frame counts
	move_frames:           int,
	attack_frames:         int,
	breath_start_frames:   int,
	breath_loop_frames:    int,
	breath_end_frames:     int,
	meteor_fall_frames:    int,
	meteor_impact_frames:  int,
	magma_start_frames:    int,
	magma_loop_frames:     int,
	magma_end_frames:      int,
}

// ---------------------------------------------------------------------------
// Lifecycle
// ---------------------------------------------------------------------------

init_ember_demon :: proc(ed: ^Ember_Demon) {
	ed.move_tex = raylib.LoadTexture("assets/sprites/enemy_emberdemon_move.png")
	ed.attack_tex = raylib.LoadTexture("assets/sprites/enemy_emberdemon_ember_breath_attack.png")
	ed.breath_start_tex = raylib.LoadTexture("assets/sprites/emberbreath_start.png")
	ed.breath_loop_tex = raylib.LoadTexture("assets/sprites/emberbreath_loop.png")
	ed.breath_end_tex = raylib.LoadTexture("assets/sprites/emberbreath_end.png")
	ed.meteor_fall_tex = raylib.LoadTexture("assets/sprites/meteor_falling.png")
	ed.meteor_impact_tex = raylib.LoadTexture("assets/sprites/meteor_impact.png")
	ed.magma_start_tex = raylib.LoadTexture("assets/sprites/magma_floor_start.png")
	ed.magma_loop_tex = raylib.LoadTexture("assets/sprites/magma_floor_loop.png")
	ed.magma_end_tex = raylib.LoadTexture("assets/sprites/magma_floor_end.png")

	ed.move_frames = int(ed.move_tex.width) / ED_SRC_SIZE
	ed.attack_frames = int(ed.attack_tex.width) / ED_SRC_SIZE
	ed.breath_start_frames = int(ed.breath_start_tex.width) / ED_BREATH_SRC_SIZE
	ed.breath_loop_frames = int(ed.breath_loop_tex.width) / ED_BREATH_SRC_SIZE
	ed.breath_end_frames = int(ed.breath_end_tex.width) / ED_BREATH_SRC_SIZE
	ed.meteor_fall_frames = int(ed.meteor_fall_tex.width) / ED_METEOR_SRC_SIZE
	ed.meteor_impact_frames = int(ed.meteor_impact_tex.width) / ED_METEOR_SRC_SIZE
	ed.magma_start_frames = int(ed.magma_start_tex.width) / ED_MAGMA_SRC_SIZE
	ed.magma_loop_frames = int(ed.magma_loop_tex.width) / ED_MAGMA_SRC_SIZE
	ed.magma_end_frames = int(ed.magma_end_tex.width) / ED_MAGMA_SRC_SIZE

	ed.active = false
}

spawn_ember_demon :: proc(ed: ^Ember_Demon, pos: raylib.Vector2) {
	ed.active = true
	ed.pos = pos
	ed.vel = {}
	ed.state = .Pursuing
	ed.phase = .Phase1
	ed.facing_left = false
	ed.on_ground = false
	ed.hp = ED_HP
	ed.current_frame = 0
	ed.anim_timer = 0
	ed.state_timer = 0
	ed.damage_flash_timer = 0
	ed.breath_cooldown = 1.0
	ed.damage_cooldown_timer = 0
	ed.breath_active = false
	ed.breath_dealt_damage = false
	ed.consecutive_damage = 0
	ed.meteor_timer = ED_METEOR_INTERVAL
	ed.magma_timer = ED_MAGMA_INTERVAL
	ed.hit_by_companion = false
	ed.hit_by_scythe = false
	for &m in ed.meteors {
		m.active = false
	}
	for &m in ed.magmas {
		m.active = false
	}
}

add_ember_demon_teleport :: proc(ed: ^Ember_Demon, pos: raylib.Vector2) {
	if ed.teleport_count >= ED_MAX_TELEPORT_POINTS {
		return
	}
	ed.teleport_points[ed.teleport_count] = pos
	ed.teleport_count += 1
}

unload_ember_demon :: proc(ed: ^Ember_Demon) {
	raylib.UnloadTexture(ed.move_tex)
	raylib.UnloadTexture(ed.attack_tex)
	raylib.UnloadTexture(ed.breath_start_tex)
	raylib.UnloadTexture(ed.breath_loop_tex)
	raylib.UnloadTexture(ed.breath_end_tex)
	raylib.UnloadTexture(ed.meteor_fall_tex)
	raylib.UnloadTexture(ed.meteor_impact_tex)
	raylib.UnloadTexture(ed.magma_start_tex)
	raylib.UnloadTexture(ed.magma_loop_tex)
	raylib.UnloadTexture(ed.magma_end_tex)
}

// ---------------------------------------------------------------------------
// Update
// ---------------------------------------------------------------------------

update_ember_demon :: proc(
	ed: ^Ember_Demon,
	player: ^Player,
	companion: ^Companion,
	scythe: ^Blood_Scythe,
	map_data: ^dm.Dot_Map,
	bp: ^i32,
	sfx_hit: raylib.Sound,
	sfx_breath: raylib.Sound,
	sfx_meteor: raylib.Sound,
	dt: f32,
) {
	if !ed.active || ed.state == .Dead {
		return
	}

	// Dying animation
	if ed.state == .Dying {
		if ed.damage_flash_timer > 0 {
			ed.damage_flash_timer -= dt
		}
		if ed_advance_oneshot(ed, ed.move_frames, dt) {
			ed.state = .Dead
		}
		ed_update_meteors(ed, player, sfx_hit, sfx_meteor, dt)
		ed_update_magma(ed, player, sfx_hit, dt)
		return
	}

	if ed.damage_flash_timer > 0 {
		ed.damage_flash_timer -= dt
	}

	// Consecutive damage reset
	if ed.consecutive_damage > 0 {
		ed.damage_cooldown_timer -= dt
		if ed.damage_cooldown_timer <= 0 {
			ed.consecutive_damage = 0
		}
	}

	if ed.breath_cooldown > 0 {
		ed.breath_cooldown -= dt
	}

	// Phase update
	if ed.hp <= ED_HP / 3.0 {
		ed.phase = .Phase3
	} else if ed.hp <= ED_HP * 2.0 / 3.0 {
		ed.phase = .Phase2
	}

	// --- Main state machine ---
	switch ed.state {
	case .Idle:
		ed_animate_loop(ed, ed.move_frames, dt)
		ed.vel.x = 0
		ed_apply_gravity(ed, dt)
		ed_move_and_collide(ed, map_data, dt)

	case .Pursuing:
		ed.facing_left = player.pos.x < ed.pos.x
		dist_x := abs(player.pos.x - ed.pos.x)

		if dist_x <= ED_BREATH_RANGE && ed.breath_cooldown <= 0 {
			ed.state = .Breathing
			ed.current_frame = 0
			ed.anim_timer = 0
			ed.vel.x = 0
			ed.breath_active = true
			ed.breath_phase = .Start
			ed.breath_frame = 0
			ed.breath_anim_timer = 0
			ed.breath_state_timer = 0
			ed.breath_dealt_damage = false
			raylib.PlaySound(sfx_breath)
		} else {
			ed.vel.x = ed.facing_left ? -ED_SPEED : ED_SPEED
			ed_animate_loop(ed, ed.move_frames, dt)
		}

		ed_apply_gravity(ed, dt)
		ed_move_and_collide(ed, map_data, dt)

	case .Breathing:
		ed.vel.x = 0
		ed_animate_loop(ed, ed.attack_frames, dt)
		ed_apply_gravity(ed, dt)
		ed_move_and_collide(ed, map_data, dt)

		ed_update_breath(ed, player, sfx_hit, dt)

		if !ed.breath_active {
			ed.state = .Pursuing
			ed.breath_cooldown = ED_BREATH_COOLDOWN
			ed.current_frame = 0
			ed.anim_timer = 0
		}

	case .Teleporting:
		ed.state_timer -= dt
		if ed.state_timer <= 0 {
			ed.state = .Pursuing
			ed.current_frame = 0
			ed.anim_timer = 0
			ed.facing_left = player.pos.x < ed.pos.x
		}
		ed_apply_gravity(ed, dt)
		ed_move_and_collide(ed, map_data, dt)

	case .Dying, .Dead:
	}

	// --- Phase 2/3 independent attacks ---
	if ed.state != .Dying && ed.state != .Dead && ed.state != .Teleporting {
		if ed.phase == .Phase2 || ed.phase == .Phase3 {
			ed.meteor_timer -= dt
			if ed.meteor_timer <= 0 {
				ed_spawn_meteor(ed, player, map_data)
				ed.meteor_timer = ED_METEOR_INTERVAL
			}
		}
		if ed.phase == .Phase3 {
			ed.magma_timer -= dt
			if ed.magma_timer <= 0 {
				ed_spawn_magma(ed, player, map_data)
				ed.magma_timer = ED_MAGMA_INTERVAL
			}
		}
	}

	ed_update_meteors(ed, player, sfx_hit, sfx_meteor, dt)
	ed_update_magma(ed, player, sfx_hit, dt)

	// --- Combat: player weapons hitting boss ---
	if companion.state != .Attacking {
		ed.hit_by_companion = false
	}
	if scythe.state != .Attacking && scythe.state != .Quick_Attacking {
		ed.hit_by_scythe = false
	}

	alive_and_hittable := ed.state != .Dead && ed.state != .Dying && ed.state != .Teleporting

	if alive_and_hittable && companion.state == .Attacking && !ed.hit_by_companion {
		comp_rect := get_companion_rect(companion, player)
		ehb := ed_get_hitbox(ed)
		if raylib.CheckCollisionRecs(comp_rect, ehb) {
			ed.hit_by_companion = true
			ed_take_damage(ed, COMPANION_DAMAGE, player, sfx_hit, bp)
		}
	}

	if alive_and_hittable && (scythe.state == .Attacking || scythe.state == .Quick_Attacking) && !ed.hit_by_scythe {
		scythe_rect := get_scythe_rect(scythe, player)
		ehb := ed_get_hitbox(ed)
		if raylib.CheckCollisionRecs(scythe_rect, ehb) {
			ed.hit_by_scythe = true
			ed_take_damage(ed, SCYTHE_DAMAGE, player, sfx_hit, bp)
		}
	}

	if alive_and_hittable && player.quick_attack_damage_active {
		attack_rect := get_quick_attack_rect(player)
		ehb := ed_get_hitbox(ed)
		if raylib.CheckCollisionRecs(attack_rect, ehb) {
			ed_take_damage(ed, QUICK_ATTACK_DAMAGE, player, sfx_hit, bp)
		}
	}

	if alive_and_hittable && player.dash_impact_active && !player.dash_impact_damage_dealt {
		impact_rect := get_dash_impact_rect(player)
		ehb := ed_get_hitbox(ed)
		if raylib.CheckCollisionRecs(impact_rect, ehb) {
			ed_take_damage(ed, DASH_IMPACT_DAMAGE, player, sfx_hit, bp)
		}
	}

	// Safety: kill if fallen below map
	map_bottom := f32(map_data.height) * TILE_SIZE + 64
	if ed.pos.y > map_bottom {
		ed.state = .Dead
	}
}

// ---------------------------------------------------------------------------
// Breath
// ---------------------------------------------------------------------------

@(private = "file")
ed_update_breath :: proc(ed: ^Ember_Demon, player: ^Player, sfx_hit: raylib.Sound, dt: f32) {
	frame_dur: f32 = 1.0 / ED_ANIM_FPS

	switch ed.breath_phase {
	case .Start:
		ed.breath_anim_timer += dt
		if ed.breath_anim_timer >= frame_dur {
			ed.breath_anim_timer -= frame_dur
			ed.breath_frame += 1
			if int(ed.breath_frame) >= ed.breath_start_frames {
				ed.breath_phase = .Loop
				ed.breath_frame = 0
				ed.breath_anim_timer = 0
				ed.breath_state_timer = 0
			}
		}
	case .Loop:
		ed.breath_anim_timer += dt
		if ed.breath_anim_timer >= frame_dur {
			ed.breath_anim_timer -= frame_dur
			ed.breath_frame += 1
			if int(ed.breath_frame) >= ed.breath_loop_frames {
				ed.breath_frame = 0
			}
		}
		ed.breath_state_timer += dt

		if !ed.breath_dealt_damage {
			breath_rect := ed_get_breath_rect(ed)
			player_rect := get_hitbox(player)
			if raylib.CheckCollisionRecs(breath_rect, player_rect) && !player.dashing {
				player.hp -= ED_BREATH_DAMAGE
				player.damage_flash_timer = DAMAGE_FLASH_DURATION
				raylib.PlaySound(sfx_hit)
				if player.hp < 0 {
					player.hp = 0
				}
				ed.breath_dealt_damage = true
			}
		}

		if ed.breath_state_timer >= ED_BREATH_LOOP_DURATION {
			ed.breath_phase = .End
			ed.breath_frame = 0
			ed.breath_anim_timer = 0
		}
	case .End:
		ed.breath_anim_timer += dt
		if ed.breath_anim_timer >= frame_dur {
			ed.breath_anim_timer -= frame_dur
			ed.breath_frame += 1
			if int(ed.breath_frame) >= ed.breath_end_frames {
				ed.breath_active = false
			}
		}
	}
}

// ---------------------------------------------------------------------------
// Meteors
// ---------------------------------------------------------------------------

@(private = "file")
ed_spawn_meteor :: proc(ed: ^Ember_Demon, player: ^Player, map_data: ^dm.Dot_Map) {
	slot: ^ED_Meteor = nil
	for &m in ed.meteors {
		if !m.active {
			slot = &m
			break
		}
	}
	if slot == nil {
		return
	}

	offset := f32(raylib.GetRandomValue(-64, 64))
	target_x := player.pos.x + offset
	ground_y := ed_find_ground(target_x, player.pos.y - 100, map_data)
	if ground_y < 0 {
		return
	}

	slot.active = true
	slot.phase = .Falling
	slot.target_pos = {target_x, ground_y}
	slot.pos = {target_x, ground_y - ED_METEOR_SPAWN_HEIGHT}
	slot.frame = 0
	slot.anim_timer = 0
	slot.dealt_damage = false
}

@(private = "file")
ed_update_meteors :: proc(ed: ^Ember_Demon, player: ^Player, sfx_hit: raylib.Sound, sfx_meteor: raylib.Sound, dt: f32) {
	frame_dur: f32 = 1.0 / ED_ANIM_FPS

	for &m in ed.meteors {
		if !m.active {
			continue
		}

		switch m.phase {
		case .Falling:
			m.anim_timer += dt
			if m.anim_timer >= frame_dur {
				m.anim_timer -= frame_dur
				m.frame += 1
				if int(m.frame) >= ed.meteor_fall_frames {
					m.frame = 0
				}
			}
			m.pos.y += ED_METEOR_FALL_SPEED * dt
			if m.pos.y >= m.target_pos.y {
				m.pos.y = m.target_pos.y
				m.phase = .Impact
				m.frame = 0
				m.anim_timer = 0
				raylib.PlaySound(sfx_meteor)
			}
		case .Impact:
			m.anim_timer += dt
			if m.anim_timer >= frame_dur {
				m.anim_timer -= frame_dur
				m.frame += 1
				if int(m.frame) >= ed.meteor_impact_frames {
					m.active = false
					continue
				}
			}
			if !m.dealt_damage {
				impact_rect := raylib.Rectangle{
					m.target_pos.x - f32(ED_METEOR_SRC_SIZE) / 2,
					m.target_pos.y - f32(ED_METEOR_SRC_SIZE),
					f32(ED_METEOR_SRC_SIZE),
					f32(ED_METEOR_SRC_SIZE),
				}
				player_rect := get_hitbox(player)
				if raylib.CheckCollisionRecs(impact_rect, player_rect) && !player.dashing {
					player.hp -= ED_METEOR_DAMAGE
					player.damage_flash_timer = DAMAGE_FLASH_DURATION
					raylib.PlaySound(sfx_hit)
					if player.hp < 0 {
						player.hp = 0
					}
				}
				m.dealt_damage = true
			}
		}
	}
}

// ---------------------------------------------------------------------------
// Magma Floor
// ---------------------------------------------------------------------------

@(private = "file")
ed_spawn_magma :: proc(ed: ^Ember_Demon, player: ^Player, map_data: ^dm.Dot_Map) {
	slot: ^ED_Magma = nil
	for &m in ed.magmas {
		if !m.active {
			slot = &m
			break
		}
	}
	if slot == nil {
		return
	}

	ground_y := ed_find_ground(player.pos.x, player.pos.y, map_data)
	if ground_y < 0 {
		return
	}

	slot.active = true
	slot.phase = .Starting
	slot.pos = {player.pos.x, ground_y}
	slot.frame = 0
	slot.anim_timer = 0
	slot.state_timer = 0
	slot.dealt_damage = false
}

@(private = "file")
ed_update_magma :: proc(ed: ^Ember_Demon, player: ^Player, sfx_hit: raylib.Sound, dt: f32) {
	frame_dur: f32 = 1.0 / ED_ANIM_FPS

	for &m in ed.magmas {
		if !m.active {
			continue
		}

		switch m.phase {
		case .Starting:
			m.anim_timer += dt
			if m.anim_timer >= frame_dur {
				m.anim_timer -= frame_dur
				m.frame += 1
				if int(m.frame) >= ed.magma_start_frames {
					m.phase = .Looping
					m.frame = 0
					m.anim_timer = 0
					m.state_timer = 0
				}
			}
		case .Looping:
			m.anim_timer += dt
			if m.anim_timer >= frame_dur {
				m.anim_timer -= frame_dur
				m.frame += 1
				if int(m.frame) >= ed.magma_loop_frames {
					m.frame = 0
				}
			}
			m.state_timer += dt

			if !m.dealt_damage {
				magma_rect := raylib.Rectangle{
					m.pos.x - f32(ED_MAGMA_SRC_SIZE) / 2,
					m.pos.y - f32(ED_MAGMA_SRC_SIZE),
					f32(ED_MAGMA_SRC_SIZE),
					f32(ED_MAGMA_SRC_SIZE),
				}
				player_rect := get_hitbox(player)
				if raylib.CheckCollisionRecs(magma_rect, player_rect) && !player.dashing {
					player.hp -= ED_MAGMA_DAMAGE
					player.damage_flash_timer = DAMAGE_FLASH_DURATION
					raylib.PlaySound(sfx_hit)
					if player.hp < 0 {
						player.hp = 0
					}
					m.dealt_damage = true
				}
			}

			if m.state_timer >= ED_MAGMA_LOOP_DURATION {
				m.phase = .Ending
				m.frame = 0
				m.anim_timer = 0
			}
		case .Ending:
			m.anim_timer += dt
			if m.anim_timer >= frame_dur {
				m.anim_timer -= frame_dur
				m.frame += 1
				if int(m.frame) >= ed.magma_end_frames {
					m.active = false
				}
			}
		}
	}
}

// ---------------------------------------------------------------------------
// Damage & Teleport
// ---------------------------------------------------------------------------

@(private = "file")
ed_take_damage :: proc(ed: ^Ember_Demon, damage: f32, player: ^Player, sfx_hit: raylib.Sound, bp: ^i32) {
	ed.hp -= damage
	ed.damage_flash_timer = DAMAGE_FLASH_DURATION
	ed.consecutive_damage += damage
	ed.damage_cooldown_timer = ED_DAMAGE_WINDOW
	raylib.PlaySound(sfx_hit)

	if ed.hp <= 0 {
		ed.hp = 0
		ed.state = .Dying
		ed.current_frame = 0
		ed.anim_timer = 0
		ed.vel = {}
		ed.breath_active = false
		bp^ += ED_BP_KILL
		return
	}

	// Phase transitions
	if ed.hp <= ED_HP / 3.0 {
		ed.phase = .Phase3
	} else if ed.hp <= ED_HP * 2.0 / 3.0 {
		ed.phase = .Phase2
	}

	// Teleport when taking too much consecutive damage
	if ed.consecutive_damage >= ED_TELEPORT_THRESHOLD && ed.state != .Teleporting && ed.teleport_count > 0 {
		ed_start_teleport(ed, player)
	}
}

@(private = "file")
ed_start_teleport :: proc(ed: ^Ember_Demon, player: ^Player) {
	tp, ok := ed_find_best_teleport(ed, player)
	if !ok {
		return
	}

	ed.pos = tp
	ed.vel = {}
	ed.on_ground = false
	ed.state = .Teleporting
	ed.state_timer = ED_TELEPORT_DURATION
	ed.consecutive_damage = 0
	ed.breath_active = false
	ed.current_frame = 0
	ed.anim_timer = 0
}

@(private = "file")
ed_find_best_teleport :: proc(ed: ^Ember_Demon, player: ^Player) -> (raylib.Vector2, bool) {
	if ed.teleport_count == 0 {
		return {}, false
	}

	best_idx := -1
	best_score: f32 = -999999.0

	for i := 0; i < ed.teleport_count; i += 1 {
		tp := ed.teleport_points[i]
		dx := tp.x - player.pos.x
		dist := abs(dx) + abs(tp.y - player.pos.y)

		// Skip points too close to current boss position
		boss_dist := abs(tp.x - ed.pos.x) + abs(tp.y - ed.pos.y)
		if boss_dist < 48 {
			continue
		}

		// Prefer points behind the player
		behind: f32 = 0
		if (player.facing_left && dx > 0) || (!player.facing_left && dx < 0) {
			behind = 80
		}

		// Prefer moderate distance from player
		near: f32 = 0
		if dist > 32 && dist < 300 {
			near = 300 - dist
		}

		score := behind + near
		if score > best_score {
			best_score = score
			best_idx = i
		}
	}

	if best_idx < 0 {
		// Fallback: any point away from boss
		for i := 0; i < ed.teleport_count; i += 1 {
			tp := ed.teleport_points[i]
			boss_dist := abs(tp.x - ed.pos.x) + abs(tp.y - ed.pos.y)
			if boss_dist >= 48 {
				return tp, true
			}
		}
		return {}, false
	}

	return ed.teleport_points[best_idx], true
}

// ---------------------------------------------------------------------------
// Draw
// ---------------------------------------------------------------------------

draw_ember_demon :: proc(ed: ^Ember_Demon, white_shader: raylib.Shader) {
	if !ed.active || ed.state == .Dead {
		return
	}

	// Magma zones (behind everything)
	for &m in ed.magmas {
		if !m.active {
			continue
		}
		magma_tex: raylib.Texture2D
		magma_max: int
		switch m.phase {
		case .Starting:
			magma_tex = ed.magma_start_tex
			magma_max = ed.magma_start_frames
		case .Looping:
			magma_tex = ed.magma_loop_tex
			magma_max = ed.magma_loop_frames
		case .Ending:
			magma_tex = ed.magma_end_tex
			magma_max = ed.magma_end_frames
		}
		mf := int(m.frame)
		if m.phase == .Looping && magma_max > 0 {
			mf = mf %% magma_max
		}
		if mf >= magma_max {
			mf = magma_max - 1
		}
		src := raylib.Rectangle{
			f32(mf * ED_MAGMA_SRC_SIZE), 0,
			f32(ED_MAGMA_SRC_SIZE), f32(ED_MAGMA_SRC_SIZE),
		}
		dst := raylib.Rectangle{
			m.pos.x - f32(ED_MAGMA_SRC_SIZE) / 2,
			m.pos.y - f32(ED_MAGMA_SRC_SIZE),
			f32(ED_MAGMA_SRC_SIZE), f32(ED_MAGMA_SRC_SIZE),
		}
		raylib.DrawTexturePro(magma_tex, src, dst, {0, 0}, 0, raylib.WHITE)
	}

	// Boss body (skip during teleport)
	if ed.state != .Teleporting {
		body_tex: raylib.Texture2D
		body_max: int
		if ed.state == .Breathing {
			body_tex = ed.attack_tex
			body_max = ed.attack_frames
		} else {
			body_tex = ed.move_tex
			body_max = ed.move_frames
		}

		frame := int(ed.current_frame)
		if frame >= body_max {
			frame = body_max - 1
		}

		src := raylib.Rectangle{
			f32(frame * ED_SRC_SIZE), 0,
			ed.facing_left ? -f32(ED_SRC_SIZE) : f32(ED_SRC_SIZE),
			f32(ED_SRC_SIZE),
		}
		dst := raylib.Rectangle{
			ed.pos.x - f32(ED_SRC_SIZE) / 2,
			ed.pos.y - f32(ED_SRC_SIZE),
			f32(ED_SRC_SIZE),
			f32(ED_SRC_SIZE),
		}
		if ed.damage_flash_timer > 0 {
			raylib.BeginShaderMode(white_shader)
		}
		raylib.DrawTexturePro(body_tex, src, dst, {0, 0}, 0, raylib.WHITE)
		if ed.damage_flash_timer > 0 {
			raylib.EndShaderMode()
		}
	}

	// Breath effect
	if ed.breath_active {
		breath_tex: raylib.Texture2D
		breath_max: int
		switch ed.breath_phase {
		case .Start:
			breath_tex = ed.breath_start_tex
			breath_max = ed.breath_start_frames
		case .Loop:
			breath_tex = ed.breath_loop_tex
			breath_max = ed.breath_loop_frames
		case .End:
			breath_tex = ed.breath_end_tex
			breath_max = ed.breath_end_frames
		}

		bf := int(ed.breath_frame)
		if ed.breath_phase == .Loop && breath_max > 0 {
			bf = bf %% breath_max
		}
		if bf >= breath_max {
			bf = breath_max - 1
		}

		rect := ed_get_breath_rect(ed)
		breath_src := raylib.Rectangle{
			f32(bf * ED_BREATH_SRC_SIZE), 0,
			ed.facing_left ? -f32(ED_BREATH_SRC_SIZE) : f32(ED_BREATH_SRC_SIZE),
			f32(ED_BREATH_SRC_SIZE),
		}
		raylib.DrawTexturePro(breath_tex, breath_src, rect, {0, 0}, 0, raylib.WHITE)
	}

	// Meteors (in front of everything)
	for &m in ed.meteors {
		if !m.active {
			continue
		}
		switch m.phase {
		case .Falling:
			ff := int(m.frame)
			if ff >= ed.meteor_fall_frames {
				ff = ed.meteor_fall_frames - 1
			}
			src := raylib.Rectangle{
				f32(ff * ED_METEOR_SRC_SIZE), 0,
				f32(ED_METEOR_SRC_SIZE), f32(ED_METEOR_SRC_SIZE),
			}
			dst := raylib.Rectangle{
				m.pos.x - f32(ED_METEOR_SRC_SIZE) / 2,
				m.pos.y - f32(ED_METEOR_SRC_SIZE),
				f32(ED_METEOR_SRC_SIZE), f32(ED_METEOR_SRC_SIZE),
			}
			raylib.DrawTexturePro(ed.meteor_fall_tex, src, dst, {0, 0}, 0, raylib.WHITE)
		case .Impact:
			imf := int(m.frame)
			if imf >= ed.meteor_impact_frames {
				imf = ed.meteor_impact_frames - 1
			}
			src := raylib.Rectangle{
				f32(imf * ED_METEOR_SRC_SIZE), 0,
				f32(ED_METEOR_SRC_SIZE), f32(ED_METEOR_SRC_SIZE),
			}
			dst := raylib.Rectangle{
				m.target_pos.x - f32(ED_METEOR_SRC_SIZE) / 2,
				m.target_pos.y - f32(ED_METEOR_SRC_SIZE),
				f32(ED_METEOR_SRC_SIZE), f32(ED_METEOR_SRC_SIZE),
			}
			raylib.DrawTexturePro(ed.meteor_impact_tex, src, dst, {0, 0}, 0, raylib.WHITE)
		}
	}
}

draw_boss_hp_bar :: proc(ed: ^Ember_Demon) {
	if !ed.active || ed.state == .Dead {
		return
	}

	BAR_W :: 200
	BAR_H :: 8
	BAR_X :: (SCREEN_WIDTH - BAR_W) / 2
	BAR_Y :: SCREEN_HEIGHT - 30

	name: cstring = "Ember Demon"
	name_w := raylib.MeasureText(name, 8)
	raylib.DrawText(name, (SCREEN_WIDTH - name_w) / 2, BAR_Y - 12, 8, raylib.Color{0xFF, 0x88, 0x33, 0xFF})

	// Outline
	raylib.DrawRectangle(BAR_X - 1, BAR_Y - 1, BAR_W + 2, BAR_H + 2, raylib.Color{0, 0, 0, 255})

	// Fill
	fill_w := i32(f32(BAR_W) * (ed.hp / ED_HP))
	if fill_w < 0 {
		fill_w = 0
	}

	fill_color: raylib.Color
	switch ed.phase {
	case .Phase1:
		fill_color = {0xFF, 0x44, 0x11, 0xFF}
	case .Phase2:
		fill_color = {0xFF, 0x88, 0x00, 0xFF}
	case .Phase3:
		fill_color = {0xFF, 0x00, 0x00, 0xFF}
	}

	raylib.DrawRectangle(BAR_X, BAR_Y, fill_w, BAR_H, fill_color)
}

draw_boss_hp_bar_intro :: proc(ed: ^Ember_Demon, alpha: u8) {
	if !ed.active || alpha == 0 {
		return
	}

	BAR_W :: 200
	BAR_H :: 8
	BAR_X :: (SCREEN_WIDTH - BAR_W) / 2
	BAR_Y :: SCREEN_HEIGHT - 30

	name: cstring = "Ember Demon"
	name_w := raylib.MeasureText(name, 8)
	raylib.DrawText(name, (SCREEN_WIDTH - name_w) / 2, BAR_Y - 12, 8, raylib.Color{0xFF, 0x88, 0x33, alpha})

	raylib.DrawRectangle(BAR_X - 1, BAR_Y - 1, BAR_W + 2, BAR_H + 2, raylib.Color{0, 0, 0, alpha})

	fill_w := i32(f32(BAR_W) * (ed.hp / ED_HP))
	if fill_w < 0 {
		fill_w = 0
	}

	fill_color: raylib.Color
	switch ed.phase {
	case .Phase1:
		fill_color = {0xFF, 0x44, 0x11, alpha}
	case .Phase2:
		fill_color = {0xFF, 0x88, 0x00, alpha}
	case .Phase3:
		fill_color = {0xFF, 0x00, 0x00, alpha}
	}

	raylib.DrawRectangle(BAR_X, BAR_Y, fill_w, BAR_H, fill_color)
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

@(private = "file")
ed_get_hitbox :: proc(ed: ^Ember_Demon) -> raylib.Rectangle {
	return {
		ed.pos.x - f32(ED_HITBOX_W) / 2,
		ed.pos.y - f32(ED_HITBOX_H),
		f32(ED_HITBOX_W),
		f32(ED_HITBOX_H),
	}
}

@(private = "file")
ed_get_breath_rect :: proc(ed: ^Ember_Demon) -> raylib.Rectangle {
	off_x: f32 = ed.facing_left ? -(f32(ED_SRC_SIZE) / 2 + f32(ED_BREATH_SRC_SIZE)) : f32(ED_SRC_SIZE) / 2
	return {
		ed.pos.x + off_x,
		ed.pos.y - f32(ED_BREATH_SRC_SIZE),
		f32(ED_BREATH_SRC_SIZE),
		f32(ED_BREATH_SRC_SIZE),
	}
}

@(private = "file")
ed_apply_gravity :: proc(ed: ^Ember_Demon, dt: f32) {
	ed.vel.y += GRAVITY * dt
	if ed.vel.y > MAX_FALL_SPEED {
		ed.vel.y = MAX_FALL_SPEED
	}
}

@(private = "file")
ed_move_and_collide :: proc(ed: ^Ember_Demon, map_data: ^dm.Dot_Map, dt: f32) {
	// Move X
	ed.pos.x += ed.vel.x * dt
	hb := ed_get_hitbox(ed)
	if check_rect_solid(map_data, hb) {
		if ed.vel.x > 0 {
			tile_x := int(hb.x + hb.width) / TILE_SIZE
			ed.pos.x = f32(tile_x * TILE_SIZE) - f32(ED_HITBOX_W) / 2
		} else if ed.vel.x < 0 {
			tile_x := int(hb.x) / TILE_SIZE
			ed.pos.x = f32((tile_x + 1) * TILE_SIZE) + f32(ED_HITBOX_W) / 2
		}
		ed.vel.x = 0
	}

	// Move Y
	ed.pos.y += ed.vel.y * dt
	hb = ed_get_hitbox(ed)
	ed.on_ground = false
	if check_rect_solid(map_data, hb) {
		if ed.vel.y > 0 {
			tile_y := int(hb.y + hb.height) / TILE_SIZE
			ed.pos.y = f32(tile_y * TILE_SIZE)
			ed.on_ground = true
		} else if ed.vel.y < 0 {
			tile_y := int(hb.y) / TILE_SIZE
			ed.pos.y = f32((tile_y + 1) * TILE_SIZE) + f32(ED_HITBOX_H)
		}
		ed.vel.y = 0
	}
}

@(private = "file")
ed_animate_loop :: proc(ed: ^Ember_Demon, total_frames: int, dt: f32) {
	if total_frames <= 1 {
		return
	}
	ed.anim_timer += dt
	if ed.anim_timer >= ANIM_FRAME_TIME {
		ed.anim_timer -= ANIM_FRAME_TIME
		ed.current_frame += 1
		if int(ed.current_frame) >= total_frames {
			ed.current_frame = 0
		}
	}
}

@(private = "file")
ed_advance_oneshot :: proc(ed: ^Ember_Demon, total_frames: int, dt: f32) -> bool {
	frame_dur: f32 = 1.0 / ED_ANIM_FPS
	ed.anim_timer += dt
	if ed.anim_timer >= frame_dur {
		ed.anim_timer -= frame_dur
		ed.current_frame += 1
		if int(ed.current_frame) >= total_frames {
			return true
		}
	}
	return false
}

@(private = "file")
ed_find_ground :: proc(x: f32, start_y: f32, map_data: ^dm.Dot_Map) -> f32 {
	tx := int(x) / TILE_SIZE
	start_ty := int(start_y) / TILE_SIZE
	if tx < 0 || tx >= map_data.width {
		return -1
	}
	for ty := start_ty; ty < map_data.height; ty += 1 {
		if ty < 0 {
			continue
		}
		if is_solid(map_data, tx, ty) {
			return f32(ty * TILE_SIZE)
		}
	}
	return -1
}
