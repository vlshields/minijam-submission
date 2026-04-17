package game

import "vendor:raylib"
import dm "../dotmap"
import "core:fmt"
import "core:math"
import "core:math/rand"
import "core:strings"

Game_Phase :: enum {
	Main_Menu,
	Cutscene,
	Pre_Round,
	Boss_Intro,
	Playing,
	Paused,
	Round_Won,
	Game_Won,
	Game_Over,
}

Game_State :: struct {
	map_data:       dm.Dot_Map,
	tile_textures:  map[u8][dynamic]raylib.Texture2D,
	camera:         raylib.Camera2D,
	player:         Player,
	companion:      Companion,
	gadreela:       Gadreela,
	blood_scythe:   Blood_Scythe,
	enemies:            Enemy_Pool,
	flamewardens:       FW_Pool,
	devils:             Devil_Pool,
	moloch:        Moloch,
	door:          Door,
	white_flash_shader: raylib.Shader,
	render_target:      raylib.RenderTexture2D,
	screen_scale:   f32,
	screen_offset:  raylib.Vector2,
	window_w:       i32,
	window_h:       i32,
	should_quit:    bool,
	bg_color:       raylib.Color,
	parallax_tex:   raylib.Texture2D,

	// Round / Blood Points
	phase:          Game_Phase,
	current_round:  int,
	blood_points:   i32,
	bp_drain_timer: f32,
	phase_timer:    f32,
	enemy_scale:    f32,

	// Audio
	sfx_jump:         raylib.Sound,
	sfx_footsteps:    raylib.Sound,
	sfx_confirm:      raylib.Sound,
	sfx_back:         raylib.Sound,
	sfx_hit:          raylib.Sound,
	sfx_dash:         raylib.Sound,
	sfx_dash_impact:  raylib.Sound,
	sfx_quick_attack: raylib.Sound,
	sfx_summon:            raylib.Sound,
	sfx_despawn:           raylib.Sound,
	sfx_scythe_attack:     raylib.Sound,
	sfx_scythe_qa_fang:    raylib.Sound,
	sfx_boss_laugh:        raylib.Sound,
	sfx_boss_breath:       raylib.Sound,
	sfx_boss_meteor:       raylib.Sound,
	sfx_flameball_agroed:  raylib.Sound,
	sfx_fw_attack:         raylib.Sound,
	sfx_devil_attack:      raylib.Sound,
	sfx_you_died:          raylib.Sound,
	music_theme:      raylib.Music,
	music_cutscene:   raylib.Music,
	music_boss:       raylib.Music,
	sfx_volume:       f32,
	music_volume:     f32,
	footstep_timer:   f32,
	audio_selection:  int, // 0=music, 1=sfx

	// Pause menu
	pause_selection:     int,
	pause_show_controls: bool,
	pause_show_audio:    bool,

	// Controls remapping
	controls_selection: int,
	controls_listening: bool,

	// Main menu
	menu_selection:    int,
	menu_timer:        f32,
	menu_title_y:      f32,
	menu_items_x:      f32,
	menu_fall_frame:   f32,
	menu_fall_timer:   f32,
	menu_show_options: bool,
	options_selection: int,

	// Cutscene
	cutscene_scene:  Cutscene_Scene,
	cutscene_line:   int,
	cutscene_shake:  f32,
	cutscene_played: bool,

	// Combat screenshake
	screen_shake: f32,

	// Boss intro
	boss_intro_timer: f32,

	// Game over fade
	game_over_timer: f32,

	// Map transition fade-in (counts down while new map fades from black)
	map_fade_in_timer: f32,


}

@(private = "file")
gs: Game_State

@(private = "file")
update_screen_scale :: proc() {
	win_w := gs.window_w
	win_h := gs.window_h
	if win_w <= 0 || win_h <= 0 {
		win_w = raylib.GetScreenWidth()
		win_h = raylib.GetScreenHeight()
	}
	scale_x := f32(win_w) / f32(SCREEN_WIDTH)
	scale_y := f32(win_h) / f32(SCREEN_HEIGHT)
	gs.screen_scale = min(scale_x, scale_y)
	gs.screen_offset = {
		(f32(win_w) - f32(SCREEN_WIDTH) * gs.screen_scale) / 2,
		(f32(win_h) - f32(SCREEN_HEIGHT) * gs.screen_scale) / 2,
	}
}

// ---------------------------------------------------------------------------
// Map loading / unloading
// ---------------------------------------------------------------------------

@(private = "file")
load_map_data :: proc(path: string) -> bool {
	map_bytes, map_ok := read_entire_file(path)
	if !map_ok {
		fmt.eprintln("Failed to load map file:", path)
		return false
	}
	map_data, parse_ok := dm.parse_map(string(map_bytes))
	delete(map_bytes)
	if !parse_ok {
		fmt.eprintln("Failed to parse map:", path)
		return false
	}
	gs.map_data = map_data

	gs.tile_textures = make(map[u8][dynamic]raylib.Texture2D)
	for sym, td in gs.map_data.metadata {
		textures: [dynamic]raylib.Texture2D
		for tile_path in td.tiles {
			cpath := strings.clone_to_cstring(tile_path)
			defer delete(cpath)
			tex := raylib.LoadTexture(cpath)
			if tex.id > 0 {
				append(&textures, tex)
			} else {
				fmt.eprintln("Failed to load texture:", tile_path)
			}
		}
		gs.tile_textures[sym] = textures
	}

	// Assign random tile variants for cells with multiple textures
	for sym, texs in gs.tile_textures {
		num_variants := len(texs)
		if num_variants > 1 {
			for &row in gs.map_data.grid {
				for &cell in row {
					if cell.symbol == sym {
						cell.tile_index = rand.int_max(num_variants)
					}
				}
			}
		}
	}

	return true
}

@(private = "file")
unload_map_data :: proc() {
	for _, &textures in gs.tile_textures {
		for &tex in textures {
			raylib.UnloadTexture(tex)
		}
		delete(textures)
	}
	delete(gs.tile_textures)
	dm.destroy_map(&gs.map_data)
}

// ---------------------------------------------------------------------------
// Round management
// ---------------------------------------------------------------------------

@(private = "file")
start_round :: proc() {
	round_maps := ROUND_MAPS
	map_path := round_maps[gs.current_round]
	if !load_map_data(map_path) {
		gs.should_quit = true
		return
	}

	// Find player spawn
	spawn_pos := raylib.Vector2{100, 100}
	for row, ry in gs.map_data.grid {
		for cell, cx in row {
			if cell.symbol == 's' {
				td, has_meta := gs.map_data.metadata['s']
				if has_meta {
					spawn_key := dm.extract_kv(td.other, "spawn_point")
					if spawn_key == "player" {
						spawn_pos = {f32(cx) * TILE_SIZE + TILE_SIZE / 2, f32(ry) * TILE_SIZE}
					}
					delete(spawn_key)
				}
			}
		}
	}

	// Reset player state (keep textures)
	gs.player.pos = spawn_pos
	gs.player.vel = {}
	gs.player.hp = PLAYER_MAX_HP
	gs.player.on_ground = false
	gs.player.jumps_left = MAX_JUMPS
	gs.player.facing_left = false
	gs.player.moving = false
	gs.player.current_frame = 0
	gs.player.anim_timer = 0
	gs.player.dashing = false
	gs.player.down_dashing = false
	gs.player.dash_timer = 0
	gs.player.dash_cooldown = 0
	gs.player.dash_impact_active = false
	gs.player.damage_flash_timer = 0
	gs.player.quick_attack_state = .None

	gs.companion.state = .Inactive
	gs.blood_scythe.state = .Inactive
	gs.gadreela.state = .Inactive

	// Gadreela spawn point (descending levels only)
	for row, ry in gs.map_data.grid {
		for cell, cx in row {
			if cell.symbol == '@' {
				td, has_meta := gs.map_data.metadata['@']
				if has_meta {
					spawn_key := dm.extract_kv(td.other, "spawn_point")
					is_daughter := spawn_key == "player_daughter"
					delete(spawn_key)
					if is_daughter {
						pos := raylib.Vector2{
							f32(cx) * TILE_SIZE + TILE_SIZE / 2,
							f32(ry) * TILE_SIZE + TILE_SIZE,
						}
						spawn_gadreela(&gs.gadreela, pos, gs.player.pos.x > pos.x)
					}
				}
			}
		}
	}

	// Respawn enemies from map
	gs.enemies.count = 0
	for row, ry in gs.map_data.grid {
		for cell, cx in row {
			if cell.symbol == 'b' {
				td, has_meta := gs.map_data.metadata['b']
				if has_meta {
					spawn_key := dm.extract_kv(td.other, "spawn_point")
					is_fireball := spawn_key == "enemy_fireball"
					delete(spawn_key)
					if is_fireball {
						pos := raylib.Vector2{
							f32(cx) * TILE_SIZE + TILE_SIZE / 2,
							f32(ry) * TILE_SIZE,
						}
						spawn_enemy(&gs.enemies, pos)
					}
				}
			}
		}
	}

	gs.flamewardens.count = 0
	for row, ry in gs.map_data.grid {
		for cell, cx in row {
			if cell.symbol == 'g' {
				td, has_meta := gs.map_data.metadata['g']
				if has_meta {
					spawn_key := dm.extract_kv(td.other, "spawn_point")
					is_fw := spawn_key == "enemy_flamewarden"
					delete(spawn_key)
					if is_fw {
						pos := raylib.Vector2{
							f32(cx) * TILE_SIZE + TILE_SIZE / 2,
							f32(ry) * TILE_SIZE,
						}
						spawn_flamewarden(&gs.flamewardens, pos)
					}
				}
			}
		}
	}

	gs.devils.count = 0
	for row, ry in gs.map_data.grid {
		for cell, cx in row {
			if cell.symbol == 'd' {
				td, has_meta := gs.map_data.metadata['d']
				if has_meta {
					spawn_key := dm.extract_kv(td.other, "spawn_point")
					is_devil := spawn_key == "enemy_devil"
					delete(spawn_key)
					if is_devil {
						pos := raylib.Vector2{
							f32(cx) * TILE_SIZE + TILE_SIZE / 2,
							f32(ry) * TILE_SIZE,
						}
						spawn_devil(&gs.devils, pos)
					}
				}
			}
		}
	}

	// Moloch boss
	gs.moloch.active = false
	gs.moloch.teleport_count = 0
	for row, ry in gs.map_data.grid {
		for cell, cx in row {
			if cell.symbol == 'B' {
				td, has_meta := gs.map_data.metadata['B']
				if has_meta {
					spawn_key := dm.extract_kv(td.other, "spawn_point")
					is_boss := spawn_key == "moloch"
					delete(spawn_key)
					if is_boss {
						pos := raylib.Vector2{
							f32(cx) * TILE_SIZE + TILE_SIZE / 2,
							f32(ry) * TILE_SIZE,
						}
						spawn_moloch(&gs.moloch, pos)
					}
				}
			}
		}
	}
	for row, ry in gs.map_data.grid {
		for cell, cx in row {
			if cell.symbol == 't' {
				td, has_meta := gs.map_data.metadata['t']
				if has_meta {
					tp_key := dm.extract_kv(td.other, "teleport_point")
					is_ed_tp := tp_key == "moloch"
					delete(tp_key)
					if is_ed_tp {
						pos := raylib.Vector2{
							f32(cx) * TILE_SIZE + TILE_SIZE / 2,
							f32(ry) * TILE_SIZE,
						}
						add_moloch_teleport(&gs.moloch, pos)
					}
				}
			}
		}
	}

	// Door (next-room marker). Player walks into it to transition.
	gs.door.state = .Inactive
	for row, ry in gs.map_data.grid {
		for cell, cx in row {
			if cell.symbol == '*' {
				td, has_meta := gs.map_data.metadata['*']
				if has_meta {
					spawn_key := dm.extract_kv(td.other, "spawn_point")
					is_door := spawn_key == "door_opens"
					delete(spawn_key)
					if is_door {
						pos := raylib.Vector2{f32(cx) * TILE_SIZE, f32(ry) * TILE_SIZE}
						spawn_door(&gs.door, pos)
					}
				}
			}
		}
	}

	gs.enemy_scale = 1.0

	// BP: first round starts fresh, later rounds carry over with floor
	if gs.current_round == 0 {
		gs.blood_points = BP_STARTING
	} else if gs.blood_points < BP_MIN_CARRY {
		gs.blood_points = BP_MIN_CARRY
	}

	gs.bp_drain_timer = BP_DRAIN_INTERVAL
	gs.phase_timer = 0
	gs.map_fade_in_timer = MAP_FADE_IN_DURATION

	if gs.moloch.active {
		gs.phase = .Boss_Intro
		gs.boss_intro_timer = BOSS_INTRO_DURATION
		raylib.PlaySound(gs.sfx_boss_laugh)
	} else {
		gs.phase = .Playing
	}

	// Switch music for the new round
	if raylib.IsMusicStreamPlaying(gs.music_cutscene) {
		raylib.StopMusicStream(gs.music_cutscene)
	}
	if gs.moloch.active {
		// Boss round: switch to boss music
		if raylib.IsMusicStreamPlaying(gs.music_theme) {
			raylib.StopMusicStream(gs.music_theme)
		}
		if !raylib.IsMusicStreamPlaying(gs.music_boss) {
			raylib.PlayMusicStream(gs.music_boss)
		}
	} else {
		if raylib.IsMusicStreamPlaying(gs.music_boss) {
			raylib.StopMusicStream(gs.music_boss)
		}
		if !raylib.IsMusicStreamPlaying(gs.music_theme) {
			raylib.PlayMusicStream(gs.music_theme)
		}
	}

	gs.camera.target = gs.player.pos
}

// ---------------------------------------------------------------------------
// Init / Update / Shutdown
// ---------------------------------------------------------------------------

init :: proc() {
	raylib.InitWindow(SCREEN_WIDTH, SCREEN_HEIGHT, "Primal")
	raylib.InitAudioDevice()
	raylib.SetRandomSeed(u32(raylib.GetTime() * 1000000) + 1)

	when ODIN_ARCH != .wasm32 && ODIN_ARCH != .wasm64p32 {
		monitor := raylib.GetCurrentMonitor()
		screen_w := raylib.GetMonitorWidth(monitor)
		screen_h := raylib.GetMonitorHeight(monitor)
		raylib.SetWindowSize(screen_w, screen_h)
		raylib.ToggleFullscreen()
		raylib.SetTargetFPS(TARGET_FPS)
	}

	gs.render_target = raylib.LoadRenderTexture(SCREEN_WIDTH, SCREEN_HEIGHT)
	raylib.SetTextureFilter(gs.render_target.texture, .POINT)
	update_screen_scale()

	gs.bg_color = {0x3d, 0x1f, 0x4c, 0xff}
	gs.parallax_tex = raylib.LoadTexture("assets/sprites/parallax-bg.png")

	// Audio
	gs.sfx_jump = raylib.LoadSound("assets/audio/sfx/player_jump.wav")
	gs.sfx_footsteps = raylib.LoadSound("assets/audio/sfx/player_footsteps.wav")
	gs.sfx_confirm = raylib.LoadSound("assets/audio/sfx/ui_confirm.wav")
	gs.sfx_back = raylib.LoadSound("assets/audio/sfx/negative-back.wav")
	gs.sfx_hit = raylib.LoadSound("assets/audio/sfx/hit.wav")
	gs.sfx_dash = raylib.LoadSound("assets/audio/sfx/player_dash.wav")
	gs.sfx_dash_impact = raylib.LoadSound("assets/audio/sfx/player_dash_ground_impact.wav")
	gs.sfx_quick_attack = raylib.LoadSound("assets/audio/sfx/quick_attacks.wav")
	gs.sfx_summon = raylib.LoadSound("assets/audio/sfx/summon_scythe_or_fangs.wav")
	gs.sfx_despawn = raylib.LoadSound("assets/audio/sfx/scythe_or_fangs_despawn.wav")
	gs.sfx_scythe_attack = raylib.LoadSound("assets/audio/sfx/scythe_attack1.wav")
	gs.sfx_scythe_qa_fang = raylib.LoadSound("assets/audio/sfx/sythe_attack_two_and_fang_attack.wav")
	gs.sfx_boss_laugh = raylib.LoadSound("assets/audio/sfx/boss_laughter.wav")
	gs.sfx_boss_breath = raylib.LoadSound("assets/audio/sfx/boss_emberbreath.wav")
	gs.sfx_boss_meteor = raylib.LoadSound("assets/audio/sfx/boss_meteor_impact.wav")
	gs.sfx_flameball_agroed = raylib.LoadSound("assets/audio/sfx/enemy_flameball_agroed.wav")
	gs.sfx_fw_attack = raylib.LoadSound("assets/audio/sfx/enemy_flamwarden attacks.wav")
	gs.sfx_devil_attack = raylib.LoadSound("assets/audio/sfx/enemy_devil_attacks.wav")
	gs.sfx_you_died = raylib.LoadSound("assets/audio/sfx/you_died.wav")
	gs.music_theme = raylib.LoadMusicStream("assets/audio/soundtrack/theme.ogg")
	gs.music_cutscene = raylib.LoadMusicStream("assets/audio/soundtrack/cutscene_w_belial.ogg")
	gs.music_boss = raylib.LoadMusicStream("assets/audio/soundtrack/boss_fight_theme.ogg")
	gs.sfx_volume = 0.3
	gs.music_volume = 0.5
	raylib.SetSoundVolume(gs.sfx_jump, gs.sfx_volume)
	raylib.SetSoundVolume(gs.sfx_footsteps, gs.sfx_volume)
	raylib.SetSoundVolume(gs.sfx_confirm, gs.sfx_volume)
	raylib.SetSoundVolume(gs.sfx_back, gs.sfx_volume)
	raylib.SetSoundVolume(gs.sfx_hit, gs.sfx_volume)
	raylib.SetSoundVolume(gs.sfx_dash, gs.sfx_volume)
	raylib.SetSoundVolume(gs.sfx_dash_impact, gs.sfx_volume)
	raylib.SetSoundVolume(gs.sfx_quick_attack, gs.sfx_volume)
	raylib.SetSoundVolume(gs.sfx_summon, gs.sfx_volume)
	raylib.SetSoundVolume(gs.sfx_despawn, gs.sfx_volume)
	raylib.SetSoundVolume(gs.sfx_scythe_attack, gs.sfx_volume)
	raylib.SetSoundVolume(gs.sfx_scythe_qa_fang, gs.sfx_volume)
	raylib.SetSoundVolume(gs.sfx_boss_laugh, gs.sfx_volume)
	raylib.SetSoundVolume(gs.sfx_boss_breath, gs.sfx_volume)
	raylib.SetSoundVolume(gs.sfx_boss_meteor, gs.sfx_volume)
	raylib.SetSoundVolume(gs.sfx_flameball_agroed, gs.sfx_volume)
	raylib.SetSoundVolume(gs.sfx_fw_attack, gs.sfx_volume)
	raylib.SetSoundVolume(gs.sfx_devil_attack, gs.sfx_volume)
	raylib.SetSoundVolume(gs.sfx_you_died, gs.sfx_volume)
	raylib.SetMusicVolume(gs.music_theme, gs.music_volume)
	raylib.SetMusicVolume(gs.music_cutscene, gs.music_volume)
	raylib.SetMusicVolume(gs.music_boss, gs.music_volume)
	gs.music_theme.looping = true
	gs.music_cutscene.looping = true
	gs.music_boss.looping = true
	raylib.PlayMusicStream(gs.music_cutscene)

	// Init entity textures (loaded once, reused across rounds)
	init_player(&gs.player, {100, 100})
	init_companion(&gs.companion)
	init_gadreela(&gs.gadreela)
	init_blood_scythe(&gs.blood_scythe)
	init_enemies(&gs.enemies)
	init_flamewardens(&gs.flamewardens)
	init_devils(&gs.devils)
	init_moloch(&gs.moloch)
	init_door(&gs.door)


	// Camera
	gs.camera = raylib.Camera2D{
		zoom   = 2,
		offset = {SCREEN_WIDTH / 2, SCREEN_HEIGHT / 2},
		target = {100, 100},
	}

	// White flash shader for damage indication
	when ODIN_ARCH == .wasm32 || ODIN_ARCH == .wasm64p32 {
		fs :: `#version 100
precision mediump float;
varying vec2 fragTexCoord;
varying vec4 fragColor;
uniform sampler2D texture0;
void main() {
    vec4 texel = texture2D(texture0, fragTexCoord);
    gl_FragColor = vec4(1.0, 1.0, 1.0, texel.a) * fragColor;
}`
		gs.white_flash_shader = raylib.LoadShaderFromMemory(nil, fs)
	} else {
		fs :: `#version 330
in vec2 fragTexCoord;
in vec4 fragColor;
uniform sampler2D texture0;
out vec4 finalColor;
void main() {
    vec4 texel = texture(texture0, fragTexCoord);
    finalColor = vec4(1.0, 1.0, 1.0, texel.a) * fragColor;
}`
		gs.white_flash_shader = raylib.LoadShaderFromMemory(nil, fs)
	}

	// Start at main menu
	gs.current_round = 0
	gs.phase = .Main_Menu
	gs.menu_selection = 0
	gs.menu_timer = 0
	gs.menu_fall_frame = 0
	gs.menu_fall_timer = 0
}

update :: proc() {
	free_all(context.temp_allocator)

	dt := raylib.GetFrameTime()
	if dt > 0.05 {
		dt = 0.05
	}

	raylib.UpdateMusicStream(gs.music_theme)
	raylib.UpdateMusicStream(gs.music_cutscene)
	raylib.UpdateMusicStream(gs.music_boss)

	switch gs.phase {
	case .Main_Menu:
		update_main_menu(dt)
	case .Cutscene:
		update_cutscene(dt)
	case .Pre_Round:
		update_pre_round(dt)
	case .Boss_Intro:
		update_boss_intro(dt)
	case .Playing:
		update_playing(dt)
	case .Paused:
		update_paused(dt)
	case .Round_Won:
		update_round_won(dt)
	case .Game_Won:
		update_game_won(dt)
	case .Game_Over:
		update_game_over(dt)
	}

	// Draw to virtual render target
	raylib.BeginTextureMode(gs.render_target)
	raylib.ClearBackground(gs.bg_color)

	switch gs.phase {
	case .Main_Menu:
		draw_main_menu()
	case .Cutscene:
		draw_cutscene()
	case .Pre_Round:
		draw_pre_round()
	case .Boss_Intro:
		draw_boss_intro()
	case .Playing:
		draw_playing()
	case .Paused:
		draw_paused()
	case .Round_Won:
		draw_round_won()
	case .Game_Won:
		draw_game_won()
	case .Game_Over:
		draw_game_over()
	}

	raylib.EndTextureMode()

	// Blit render target scaled to window
	raylib.BeginDrawing()
	raylib.ClearBackground(raylib.BLACK)
	src := raylib.Rectangle{0, 0, f32(SCREEN_WIDTH), -f32(SCREEN_HEIGHT)}
	dst := raylib.Rectangle{
		gs.screen_offset.x,
		gs.screen_offset.y,
		f32(SCREEN_WIDTH) * gs.screen_scale,
		f32(SCREEN_HEIGHT) * gs.screen_scale,
	}
	raylib.DrawTexturePro(gs.render_target.texture, src, dst, {0, 0}, 0, raylib.WHITE)
	raylib.EndDrawing()
}

should_run :: proc() -> bool {
	return !raylib.WindowShouldClose() && !gs.should_quit
}

shutdown :: proc() {
	raylib.UnloadSound(gs.sfx_jump)
	raylib.UnloadSound(gs.sfx_footsteps)
	raylib.UnloadSound(gs.sfx_confirm)
	raylib.UnloadSound(gs.sfx_back)
	raylib.UnloadSound(gs.sfx_hit)
	raylib.UnloadSound(gs.sfx_dash)
	raylib.UnloadSound(gs.sfx_dash_impact)
	raylib.UnloadSound(gs.sfx_quick_attack)
	raylib.UnloadSound(gs.sfx_summon)
	raylib.UnloadSound(gs.sfx_despawn)
	raylib.UnloadSound(gs.sfx_scythe_attack)
	raylib.UnloadSound(gs.sfx_scythe_qa_fang)
	raylib.UnloadSound(gs.sfx_boss_laugh)
	raylib.UnloadSound(gs.sfx_boss_breath)
	raylib.UnloadSound(gs.sfx_boss_meteor)
	raylib.UnloadSound(gs.sfx_flameball_agroed)
	raylib.UnloadSound(gs.sfx_fw_attack)
	raylib.UnloadSound(gs.sfx_devil_attack)
	raylib.UnloadSound(gs.sfx_you_died)
	raylib.UnloadMusicStream(gs.music_theme)
	raylib.UnloadMusicStream(gs.music_cutscene)
	raylib.UnloadMusicStream(gs.music_boss)
	raylib.CloseAudioDevice()
	raylib.UnloadShader(gs.white_flash_shader)
	raylib.UnloadTexture(gs.parallax_tex)
	raylib.UnloadRenderTexture(gs.render_target)
	unload_map_data()
	unload_player(&gs.player)
	unload_companion(&gs.companion)
	unload_gadreela(&gs.gadreela)
	unload_blood_scythe(&gs.blood_scythe)
	unload_enemies(&gs.enemies)
	unload_flamewardens(&gs.flamewardens)
	unload_devils(&gs.devils)
	unload_moloch(&gs.moloch)
	unload_door(&gs.door)

	raylib.CloseWindow()
}

parent_window_size_changed :: proc(w, h: int) {
	gs.window_w = i32(w)
	gs.window_h = i32(h)
	raylib.SetWindowSize(gs.window_w, gs.window_h)
	update_screen_scale()
}

set_web_mouse_pos :: proc(x, y: int) {
	// placeholder for future mouse support
}

set_web_mouse_down :: proc(down: bool) {
	// placeholder for future mouse support
}

// ---------------------------------------------------------------------------
// Phase: Main Menu
// ---------------------------------------------------------------------------

@(private = "file")
update_main_menu :: proc(dt: f32) {
	// Options sub-screen (early out to skip animations)
	if gs.menu_show_options {
		if gs.pause_show_controls {
			update_controls_screen()
			return
		}
		if gs.pause_show_audio {
			update_audio_settings(dt)
			return
		}
		if input_back() {
			raylib.PlaySound(gs.sfx_back)
			gs.menu_show_options = false
			gs.options_selection = 0
			return
		}
		if input_menu_down() {
			gs.options_selection = (gs.options_selection + 1) %% 2
		}
		if input_menu_up() {
			gs.options_selection = (gs.options_selection - 1) %% 2
		}
		if input_confirm() {
			raylib.PlaySound(gs.sfx_confirm)
			switch gs.options_selection {
			case 0: // Audio
				gs.pause_show_audio = true
			case 1: // Controls
				gs.pause_show_controls = true
			}
		}
		return
	}

	gs.menu_timer += dt

	// Title slide-in (cubic ease-out, 0.8s)
	TITLE_ANIM_DUR :: f32(0.8)
	TITLE_START_Y  :: f32(-40)
	TITLE_REST_Y   :: f32(60)
	title_t := min(gs.menu_timer / TITLE_ANIM_DUR, 1.0)
	inv_t := 1.0 - title_t
	title_ease := 1.0 - inv_t * inv_t * inv_t
	gs.menu_title_y = TITLE_START_Y + (TITLE_REST_Y - TITLE_START_Y) * title_ease

	// Items slide-in (cubic ease-out, 0.6s, delayed 0.3s)
	ITEMS_DELAY     :: f32(0.3)
	ITEMS_ANIM_DUR  :: f32(0.6)
	ITEMS_OFFSET    :: f32(-250)
	items_elapsed := max(gs.menu_timer - ITEMS_DELAY, 0.0)
	items_t := min(items_elapsed / ITEMS_ANIM_DUR, 1.0)
	inv_it := 1.0 - items_t
	items_ease := 1.0 - inv_it * inv_it * inv_it
	gs.menu_items_x = ITEMS_OFFSET * (1.0 - items_ease)

	// Looping fall animation
	fall_frames := gs.player.fall_frames
	if fall_frames > 1 {
		gs.menu_fall_timer += dt
		if gs.menu_fall_timer >= ANIM_FRAME_TIME {
			gs.menu_fall_timer -= ANIM_FRAME_TIME
			gs.menu_fall_frame += 1
			if int(gs.menu_fall_frame) >= fall_frames {
				gs.menu_fall_frame = 0
			}
		}
	}

	// Navigation
	if input_menu_down() {
		gs.menu_selection = (gs.menu_selection + 1) %% 3
	}
	if input_menu_up() {
		gs.menu_selection = (gs.menu_selection - 1) %% 3
	}

	// Confirm
	if input_confirm() {
		switch gs.menu_selection {
		case 0: // Play
			raylib.PlaySound(gs.sfx_confirm)
			if !gs.cutscene_played {
				gs.cutscene_scene = .Opening
				gs.cutscene_line = 0
				gs.cutscene_shake = 0
				gs.phase = .Cutscene
			} else {
				start_round()
			}
		case 1: // Options
			raylib.PlaySound(gs.sfx_confirm)
			gs.menu_show_options = true
		case 2: // Quit
			gs.should_quit = true
		}
	}
}

@(private = "file")
draw_main_menu :: proc() {
	// Sky layer (static)
	sky_src := raylib.Rectangle{0, 0, f32(SCREEN_WIDTH), f32(SCREEN_HEIGHT)}
	raylib.DrawTextureRec(gs.parallax_tex, sky_src, {0, 0}, raylib.WHITE)

	// Stars layer (scrolling up for falling effect)
	STAR_SCROLL_SPEED :: f32(40)
	star_offset := gs.menu_timer * STAR_SCROLL_SPEED
	wrapped := star_offset - f32(SCREEN_HEIGHT) * math.floor_f32(star_offset / f32(SCREEN_HEIGHT))
	star_src := raylib.Rectangle{0, f32(2 * SCREEN_HEIGHT), f32(SCREEN_WIDTH), f32(SCREEN_HEIGHT)}
	raylib.DrawTextureRec(gs.parallax_tex, star_src, {0, -wrapped}, raylib.WHITE)
	raylib.DrawTextureRec(gs.parallax_tex, star_src, {0, f32(SCREEN_HEIGHT) - wrapped}, raylib.WHITE)

	// Title
	title : cstring = "LIFE BLOOD"
	title_size :: i32(20)
	title_w := raylib.MeasureText(title, title_size)
	title_x := (SCREEN_WIDTH - title_w) / 2
	raylib.DrawText(title, title_x, i32(gs.menu_title_y), title_size, raylib.Color{0xFF, 0x33, 0x33, 0xFF})

	// Menu items
	items := [3]cstring{"PLAY", "OPTIONS", "QUIT"}
	item_size :: i32(10)
	item_base_y :: i32(140)
	item_spacing :: i32(20)

	for item, i in items {
		item_w := raylib.MeasureText(item, item_size)
		item_x := (SCREEN_WIDTH - item_w) / 2 + i32(gs.menu_items_x)
		item_y := item_base_y + i32(i) * item_spacing

		color := raylib.Color{150, 150, 150, 255}
		if i == gs.menu_selection {
			color = raylib.WHITE
		}
		raylib.DrawText(item, item_x, item_y, item_size, color)
	}

	// Selection arrow
	sel_item := items[gs.menu_selection]
	sel_w := raylib.MeasureText(sel_item, item_size)
	arrow_x := (SCREEN_WIDTH - sel_w) / 2 + i32(gs.menu_items_x) - 12
	arrow_y := item_base_y + i32(gs.menu_selection) * item_spacing
	raylib.DrawText(">", arrow_x, arrow_y, item_size, raylib.WHITE)

	// Options overlay
	if gs.menu_show_options {
		raylib.DrawRectangle(0, 0, SCREEN_WIDTH, SCREEN_HEIGHT, raylib.Color{0, 0, 0, 255})

		if gs.pause_show_controls {
			draw_controls_screen()
			return
		}
		if gs.pause_show_audio {
			draw_audio_settings()
			return
		}

		opt_title: cstring = "OPTIONS"
		opt_title_size :: i32(16)
		opt_title_w := raylib.MeasureText(opt_title, opt_title_size)
		raylib.DrawText(opt_title, (SCREEN_WIDTH - opt_title_w) / 2, 90, opt_title_size, raylib.Color{0xFF, 0x33, 0x33, 0xFF})

		opt_items := [2]cstring{"AUDIO", "CONTROLS"}
		opt_item_size :: i32(10)
		opt_base_y :: i32(140)
		opt_spacing :: i32(20)

		for item, i in opt_items {
			iw := raylib.MeasureText(item, opt_item_size)
			ix := (SCREEN_WIDTH - iw) / 2
			iy := opt_base_y + i32(i) * opt_spacing
			color := raylib.Color{150, 150, 150, 255}
			if i == gs.options_selection {
				color = raylib.WHITE
			}
			raylib.DrawText(item, ix, iy, opt_item_size, color)
		}

		sel_opt := opt_items[gs.options_selection]
		sel_opt_w := raylib.MeasureText(sel_opt, opt_item_size)
		opt_arrow_x := (SCREEN_WIDTH - sel_opt_w) / 2 - 12
		opt_arrow_y := opt_base_y + i32(gs.options_selection) * opt_spacing
		raylib.DrawText(">", opt_arrow_x, opt_arrow_y, opt_item_size, raylib.WHITE)

		hint: cstring = "Press ESC to go back"
		hint_size :: i32(8)
		hint_w := raylib.MeasureText(hint, hint_size)
		raylib.DrawText(hint, (SCREEN_WIDTH - hint_w) / 2, 220, hint_size, raylib.Color{150, 150, 150, 255})
		return
	}

	// Decorative falling player sprite
	frame := int(gs.menu_fall_frame)
	src := raylib.Rectangle{
		f32(frame * SPRITE_SRC_SIZE), 0,
		f32(SPRITE_SRC_SIZE),
		f32(SPRITE_SRC_SIZE),
	}
	MENU_SPRITE_SIZE :: f32(48)
	dst := raylib.Rectangle{
		f32(SCREEN_WIDTH) * 0.75 - MENU_SPRITE_SIZE / 2,
		f32(SCREEN_HEIGHT) / 2 - MENU_SPRITE_SIZE / 2,
		MENU_SPRITE_SIZE,
		MENU_SPRITE_SIZE,
	}
	raylib.DrawTexturePro(gs.player.fall_tex, src, dst, {0, 0}, 0, raylib.WHITE)
}

// ---------------------------------------------------------------------------
// Phase: Cutscene
// ---------------------------------------------------------------------------

Cutscene_Line :: struct {
	speaker: cstring,
	text:    cstring,
	shake:   bool,
}

Cutscene_Scene :: enum {
	Opening,
	Moloch_Confronts_Abaddon,
	Abaddon_And_Gadreela_Escape,
}

CUTSCENE_SHAKE_DURATION :: f32(0.4)

@(private = "file")
OPENING_SCENE := [?]Cutscene_Line{
	{"BELIAL",  "Abaddon? What are you doing? I am your friend!\nEver since this city was founded.", false},
	{"Abaddon", "*chuckles* there are no allies in Hell.", false},
	{"BELIAL",  "What could you possibly stand to gain from killing us\ndemonfolk; you are an Angel of Death.\nYou need HUMAN blood to survive!", false},
	{"Abaddon", "It's not just about me anymore Belial.", false},
	{"BELIAL",  "...", false},
	{"Abaddon", "I have a child now. Born of human blood.\nShe needs demon blood to survive.\nAnd her supply is draining rapidly.", false},
	{"BELIAL",  "You can't have offspring!? Angels are...\nWait... No, Abaddon... You didn't... A human??", false},
	{"BELIAL",  "NOOOOOOOOOOOO!!!!", true},
}

@(private = "file")
MOLOCH_CONFRONTS_ABADDON_SCENE := [?]Cutscene_Line{
	{"???",      "HEEELLPPPP!!!!", false},
	{"Abaddon",  "Gadreela? Is that you???", false},
	{"Gadreela", "Dad!?", false},
	{"Abaddon",  "Grrr are you alright? Who is behind this!?", true},
	{"MOLOCH",   "Ha. You do not deserve a child.\nYou are so concerned with providing for her.\nBut you forgot to provide what really matters.", false},
	{"Abaddon",  "Moloch. I forgot you are an expert on this subject.\nWhat did I forget to provide?", false},
	{"MOLOCH",   "Time. Attention.\nYou let me take her right from underneath you.", false},
	{"Abaddon",  "Listen, Moloch. You are the brawn of the royal pantheon here,\nnot the brains. Gadreela is the first of her kind.", true},
	{"Abaddon",  "Basic needs come first. SHE MUST EAT.\nAnd I am not worried about you taking her. I can easily find\nand kill you. In a few years, she will be able to too.", false},
}

@(private = "file")
ABADDON_AND_GADREELA_ESCAPE_SCENE := [?]Cutscene_Line{
	{"Abaddon",  "Gadreela. Come, it is safe now, I know you are here.", false},
	{"Gadreela", "Hey... I'm not hungry anymore...", false},
	{"Abaddon",  "Yes, Moloch's blood is enough to sustain you\nfor seven... maybe ten years.", false},
	{"Abaddon",  "Damn! He's trying to bring this whole city down\nin his last effort. That spiteful...", true},
	{"Abaddon",  "Gadreela, follow me. We must escape this city.", false},
	{"Gadreela", "Where will we go, Dad?", false},
	{"Abaddon",  "We will head for the Middle Realm,\nwhere the Humans dwell.", false},
	{"Gadreela", "What if I get hungry again?", false},
	{"Abaddon",  "There will be other beings from Hel.\nIncluding at least one Arch Angel I know of. Azazeel.\nOthers are bound to come.", false},
}

@(private = "file")
current_cutscene :: proc() -> []Cutscene_Line {
	switch gs.cutscene_scene {
	case .Opening:
		return OPENING_SCENE[:]
	case .Moloch_Confronts_Abaddon:
		return MOLOCH_CONFRONTS_ABADDON_SCENE[:]
	case .Abaddon_And_Gadreela_Escape:
		return ABADDON_AND_GADREELA_ESCAPE_SCENE[:]
	}
	return OPENING_SCENE[:]
}

@(private = "file")
end_cutscene :: proc() {
	raylib.StopMusicStream(gs.music_cutscene)
	switch gs.cutscene_scene {
	case .Opening:
		gs.cutscene_played = true
		gs.phase = .Pre_Round
		raylib.PlayMusicStream(gs.music_theme)
	case .Moloch_Confronts_Abaddon:
		start_round()
	case .Abaddon_And_Gadreela_Escape:
		start_round()
	}
}

@(private = "file")
update_cutscene :: proc(dt: f32) {
	scene := current_cutscene()

	// Skip entire cutscene
	if input_back() {
		end_cutscene()
		return
	}

	// Screenshake countdown
	if gs.cutscene_shake > 0 {
		gs.cutscene_shake -= dt
	}

	// Advance dialogue
	if input_confirm() {
		gs.cutscene_line += 1
		if gs.cutscene_line >= len(scene) {
			end_cutscene()
			return
		}
		if scene[gs.cutscene_line].shake {
			gs.cutscene_shake = CUTSCENE_SHAKE_DURATION
		}
	}
}

@(private = "file")
draw_cutscene :: proc() {
	raylib.ClearBackground(raylib.BLACK)

	scene := current_cutscene()
	line := scene[gs.cutscene_line]

	// Screenshake offset
	shake_x: i32 = 0
	shake_y: i32 = 0
	if gs.cutscene_shake > 0 {
		intensity := gs.cutscene_shake / CUTSCENE_SHAKE_DURATION
		mag := intensity * 4.0
		shake_x = i32(rand.float32_range(-mag, mag))
		shake_y = i32(rand.float32_range(-mag, mag))
	}

	// Dialogue box
	BOX_X :: i32(40)
	BOX_W :: SCREEN_WIDTH - BOX_X * 2
	BOX_H :: i32(90)
	BOX_Y :: SCREEN_HEIGHT - BOX_H - 20
	raylib.DrawRectangle(BOX_X + shake_x, BOX_Y + shake_y, BOX_W, BOX_H, {20, 20, 20, 230})
	raylib.DrawRectangleLines(BOX_X + shake_x, BOX_Y + shake_y, BOX_W, BOX_H, {100, 100, 100, 200})

	// Speaker name
	speaker_color: raylib.Color = {0xAA, 0x82, 0xFF, 0xFF}
	switch string(line.speaker)[0] {
	case 'B':
		speaker_color = {0xFF, 0x99, 0x33, 0xFF}
	case 'M':
		speaker_color = {0xFF, 0x44, 0x33, 0xFF}
	case 'G':
		speaker_color = {0xFF, 0x99, 0xCC, 0xFF}
	case '?':
		speaker_color = {0x99, 0x99, 0x99, 0xFF}
	}
	raylib.DrawText(line.speaker, BOX_X + 10 + shake_x, BOX_Y + 8 + shake_y, 10, speaker_color)

	// Dialogue text
	raylib.DrawText(line.text, BOX_X + 10 + shake_x, BOX_Y + 24 + shake_y, 10, raylib.WHITE)

	// Prompts
	prompt: cstring = gamepad_active() ? "A to continue" : "ENTER to continue"
	prompt_w := raylib.MeasureText(prompt, 6)
	raylib.DrawText(prompt, (SCREEN_WIDTH - prompt_w) / 2, SCREEN_HEIGHT - 14, 6, {150, 150, 150, 255})
	skip: cstring = gamepad_active() ? "B to skip" : "ESC to skip"
	raylib.DrawText(skip, SCREEN_WIDTH - 70, 5, 6, {100, 100, 100, 255})
}

// Phase: Pre-Round
// ---------------------------------------------------------------------------

@(private = "file")
update_pre_round :: proc(dt: f32) {
	if input_confirm() || input_back() {
		start_round()
	}
}

@(private = "file")
draw_pre_round :: proc() {
	raylib.ClearBackground(raylib.BLACK)

	line1: cstring = "Don't let your blood supply deplete!"
	line2: cstring = "Killing enemies replenishes your blood points."
	line3: cstring = "Collect blood for as long as you can..."

	text_size :: i32(10)
	line_spacing :: i32(18)
	base_y :: i32(SCREEN_HEIGHT / 2 - 30)

	w1 := raylib.MeasureText(line1, text_size)
	w2 := raylib.MeasureText(line2, text_size)
	w3 := raylib.MeasureText(line3, text_size)

	raylib.DrawText(line1, (SCREEN_WIDTH - w1) / 2, base_y, text_size, raylib.Color{0xFF, 0x33, 0x33, 0xFF})
	raylib.DrawText(line2, (SCREEN_WIDTH - w2) / 2, base_y + line_spacing, text_size, raylib.WHITE)
	raylib.DrawText(line3, (SCREEN_WIDTH - w3) / 2, base_y + line_spacing * 2, text_size, raylib.WHITE)

	prompt: cstring = gamepad_active() ? "Press A to begin" : "Press ENTER to begin"
	prompt_w := raylib.MeasureText(prompt, 8)
	raylib.DrawText(prompt, (SCREEN_WIDTH - prompt_w) / 2, SCREEN_HEIGHT - 40, 8, raylib.Color{150, 150, 150, 255})
}

// ---------------------------------------------------------------------------
// Map transition fades
// ---------------------------------------------------------------------------

MAP_FADE_IN_DURATION  :: f32(0.9)
ROUND_WON_FADE_DURATION :: f32(1.4)

@(private = "file")
ease_out_quad :: proc(t: f32) -> f32 {
	tc := clamp(t, 0, 1)
	return 1 - (1 - tc) * (1 - tc)
}

@(private = "file")
ease_in_quad :: proc(t: f32) -> f32 {
	tc := clamp(t, 0, 1)
	return tc * tc
}

@(private = "file")
draw_map_fade_in_overlay :: proc() {
	if gs.map_fade_in_timer <= 0 {
		return
	}
	t := gs.map_fade_in_timer / MAP_FADE_IN_DURATION
	alpha := u8(ease_in_quad(t) * 255)
	raylib.DrawRectangle(0, 0, SCREEN_WIDTH, SCREEN_HEIGHT, raylib.Color{0, 0, 0, alpha})
}

// Phase: Boss Intro
// ---------------------------------------------------------------------------

BOSS_INTRO_DURATION :: 2.0

@(private = "file")
update_boss_intro :: proc(dt: f32) {
	if gs.map_fade_in_timer > 0 {
		gs.map_fade_in_timer -= dt
	}
	gs.boss_intro_timer -= dt
	if gs.boss_intro_timer <= 0 {
		gs.phase = .Playing
	}
}

@(private = "file")
draw_boss_intro :: proc() {
	draw_parallax_bg()
	raylib.BeginMode2D(gs.camera)
	draw_map()
	draw_moloch(&gs.moloch, gs.white_flash_shader)
	draw_player(&gs.player, gs.white_flash_shader)
	draw_companion(&gs.companion, &gs.player)
	draw_blood_scythe(&gs.blood_scythe, &gs.player)
	raylib.EndMode2D()

	draw_player_hud(&gs.player)

	// Boss HP bar slides up from below the screen
	progress := 1.0 - (gs.boss_intro_timer / BOSS_INTRO_DURATION)
	bar_alpha := u8(clamp(progress * 2.0, 0.0, 1.0) * 255.0) // fade in over first half
	draw_boss_hp_bar_intro(&gs.moloch, bar_alpha)

	draw_map_fade_in_overlay()
}

// Phase: Playing
// ---------------------------------------------------------------------------

@(private = "file")
update_playing :: proc(dt: f32) {
	if gs.map_fade_in_timer > 0 {
		gs.map_fade_in_timer -= dt
	}
	if input_pause() {
		raylib.PlaySound(gs.sfx_back)
		gs.phase = .Paused
		gs.pause_selection = 0
		gs.pause_show_controls = false
		gs.pause_show_audio = false
		return
	}

	// Companion selection toggle (gamepad RB)
	if input_companion_toggle() {
		selected_companion = selected_companion == .Scythe ? .Fangs : .Scythe
	}

	// BP drain
	gs.bp_drain_timer -= dt
	if gs.bp_drain_timer <= 0 {
		gs.blood_points -= 1
		gs.bp_drain_timer += BP_DRAIN_INTERVAL
	}


	if gs.blood_points <= 0 || gs.player.hp <= 0 {
		gs.blood_points = max(gs.blood_points, 0)
		gs.player.hp = max(gs.player.hp, 0)
		raylib.StopMusicStream(gs.music_boss)
		raylib.StopMusicStream(gs.music_theme)
		raylib.StopSound(gs.sfx_footsteps)
		raylib.PlaySound(gs.sfx_you_died)
		gs.phase = .Game_Over
		gs.game_over_timer = 0
		return
	}

	// Door: player must find the door to advance to the next room.
	if gs.door.state == .Idle {
		player_rect := raylib.Rectangle{
			gs.player.pos.x - PLAYER_HITBOX_W / 2,
			gs.player.pos.y - PLAYER_HITBOX_H,
			PLAYER_HITBOX_W, PLAYER_HITBOX_H,
		}
		if raylib.CheckCollisionRecs(player_rect, door_hitbox(&gs.door)) {
			gs.door.state = .Opening
		}
	}
	if update_door(&gs.door, dt) {
		gs.phase = .Round_Won
		gs.phase_timer = ROUND_WON_FADE_DURATION
		raylib.StopSound(gs.sfx_footsteps)
		return
	}

	// Gameplay — capture previous states for SFX triggers
	prev_jumps := gs.player.jumps_left
	prev_qa_state := gs.player.quick_attack_state
	prev_dashing := gs.player.dashing
	prev_dash_impact := gs.player.dash_impact_active
	prev_comp_state := gs.companion.state
	prev_scythe_state := gs.blood_scythe.state
	prev_player_flash := gs.player.damage_flash_timer

	update_quick_attack(&gs.player, &gs.companion, &gs.blood_scythe, dt)
	update_player(&gs.player, &gs.map_data, dt)
	update_companion(&gs.companion, &gs.player, &gs.blood_scythe, dt)
	update_gadreela(&gs.gadreela, &gs.player, &gs.map_data, dt)

	// SFX: jump
	if gs.player.jumps_left < prev_jumps {
		raylib.PlaySound(gs.sfx_jump)
	}

	// SFX: dash
	if !prev_dashing && gs.player.dashing {
		raylib.PlaySound(gs.sfx_dash)
	}

	// SFX + screenshake: dash ground impact
	if !prev_dash_impact && gs.player.dash_impact_active {
		raylib.PlaySound(gs.sfx_dash_impact)
		gs.screen_shake = SCREENSHAKE_DURATION
	}

	// SFX: quick attack
	if prev_qa_state == .None && (gs.player.quick_attack_state == .Attack1 || gs.player.quick_attack_state == .Attack2) {
		raylib.PlaySound(gs.sfx_quick_attack)
	} else if prev_qa_state == .Attack1 && gs.player.quick_attack_state == .Attack2 {
		raylib.PlaySound(gs.sfx_quick_attack)
	}

	// SFX: companion summon/despawn/attack
	if prev_comp_state != .Spawning && gs.companion.state == .Spawning {
		raylib.PlaySound(gs.sfx_summon)
	}
	if prev_comp_state != .Attacking && gs.companion.state == .Attacking {
		raylib.PlaySound(gs.sfx_scythe_qa_fang)
	}
	if prev_comp_state != .Despawning && gs.companion.state == .Despawning {
		raylib.PlaySound(gs.sfx_despawn)
	}

	// SFX: footsteps (looping while moving on ground)
	if gs.player.on_ground && gs.player.moving && !gs.player.dashing {
		gs.footstep_timer -= dt
		if gs.footstep_timer <= 0 {
			gs.footstep_timer = FOOTSTEP_INTERVAL
			raylib.PlaySound(gs.sfx_footsteps)
		}
	} else {
		gs.footstep_timer = 0
		if raylib.IsSoundPlaying(gs.sfx_footsteps) {
			raylib.StopSound(gs.sfx_footsteps)
		}
	}

	update_blood_scythe(&gs.blood_scythe, &gs.player, &gs.companion, dt)

	// SFX: scythe summon/despawn/attacks
	if prev_scythe_state != .Spawning && gs.blood_scythe.state == .Spawning {
		raylib.PlaySound(gs.sfx_summon)
	}
	if prev_scythe_state != .Attacking && gs.blood_scythe.state == .Attacking {
		raylib.PlaySound(gs.sfx_scythe_attack)
	}
	if prev_scythe_state != .Quick_Attacking && gs.blood_scythe.state == .Quick_Attacking {
		raylib.PlaySound(gs.sfx_scythe_qa_fang)
	}
	if prev_scythe_state != .Despawning && gs.blood_scythe.state == .Despawning {
		raylib.PlaySound(gs.sfx_despawn)
	}

	update_enemies(&gs.enemies, &gs.player, &gs.companion, &gs.blood_scythe, &gs.camera, &gs.map_data, &gs.blood_points, gs.enemy_scale, gs.sfx_hit, gs.sfx_flameball_agroed, dt)
	update_flamewardens(&gs.flamewardens, &gs.player, &gs.companion, &gs.blood_scythe, &gs.camera, &gs.map_data, &gs.blood_points, gs.enemy_scale, gs.sfx_hit, gs.sfx_fw_attack, dt)
	update_devils(&gs.devils, &gs.player, &gs.companion, &gs.blood_scythe, &gs.camera, &gs.map_data, &gs.blood_points, gs.enemy_scale, gs.sfx_hit, gs.sfx_devil_attack, dt)
	update_moloch(&gs.moloch, &gs.player, &gs.companion, &gs.blood_scythe, &gs.map_data, &gs.blood_points, gs.sfx_hit, gs.sfx_boss_breath, gs.sfx_boss_meteor, dt)

	// Mark dash impact damage as dealt after all enemies processed
	if gs.player.dash_impact_active && !gs.player.dash_impact_damage_dealt {
		gs.player.dash_impact_damage_dealt = true
	}

	// Boss defeated — trigger escape cutscene then descending levels
	if gs.moloch.active && gs.moloch.state == .Dead {
		raylib.StopMusicStream(gs.music_boss)
		raylib.StopSound(gs.sfx_footsteps)
		unload_map_data()
		gs.current_round += 1
		gs.cutscene_scene = .Abaddon_And_Gadreela_Escape
		gs.cutscene_line = 0
		gs.cutscene_shake = 0
		gs.phase = .Cutscene
		raylib.PlayMusicStream(gs.music_cutscene)
		return
	}

	// SFX: player got hit + screenshake
	if prev_player_flash <= 0 && gs.player.damage_flash_timer > 0 {
		raylib.PlaySound(gs.sfx_hit)
		gs.screen_shake = SCREENSHAKE_DURATION
	}

	// Screenshake: any enemy just got hit
	if gs.screen_shake <= 0 {
		hit_detected: bool
		for &e in gs.enemies.enemies[:gs.enemies.count] {
			if e.state != .Dead && e.damage_flash_timer == DAMAGE_FLASH_DURATION { hit_detected = true; break }
		}
		if !hit_detected {
			for &fw in gs.flamewardens.wardens[:gs.flamewardens.count] {
				if fw.state != .Dead && fw.damage_flash_timer == DAMAGE_FLASH_DURATION { hit_detected = true; break }
			}
		}
		if !hit_detected {
			for &d in gs.devils.devils[:gs.devils.count] {
				if d.state != .Dead && d.damage_flash_timer == DAMAGE_FLASH_DURATION { hit_detected = true; break }
			}
		}
		if !hit_detected && gs.moloch.active && gs.moloch.state != .Dead && gs.moloch.damage_flash_timer == DAMAGE_FLASH_DURATION {
			hit_detected = true
		}
		if hit_detected {
			gs.screen_shake = SCREENSHAKE_DURATION
		}
	}

	update_camera(dt)
}

@(private = "file")
draw_playing :: proc() {
	draw_parallax_bg()
	raylib.BeginMode2D(gs.camera)
	draw_map()
	draw_door(&gs.door)
	draw_enemies(&gs.enemies, gs.white_flash_shader)
	draw_flamewardens(&gs.flamewardens, gs.white_flash_shader)
	draw_devils(&gs.devils, gs.white_flash_shader)
	draw_moloch(&gs.moloch, gs.white_flash_shader)
	draw_gadreela(&gs.gadreela)
	draw_player(&gs.player, gs.white_flash_shader)
	draw_companion(&gs.companion, &gs.player)
	draw_blood_scythe(&gs.blood_scythe, &gs.player)

	raylib.EndMode2D()


	draw_door_offscreen_marker()

	draw_player_hud(&gs.player)
	draw_bp_hud(gs.blood_points)
	draw_boss_hp_bar(&gs.moloch)

	draw_map_fade_in_overlay()
}

@(private = "file")
draw_door_offscreen_marker :: proc() {
	if gs.door.state != .Idle {
		return
	}
	door_center := raylib.Vector2{
		gs.door.pos.x + DOOR_SRC_SIZE / 2,
		gs.door.pos.y + DOOR_SRC_SIZE / 2,
	}
	screen := raylib.Vector2{
		(door_center.x - gs.camera.target.x) * gs.camera.zoom + SCREEN_WIDTH / 2,
		(door_center.y - gs.camera.target.y) * gs.camera.zoom + SCREEN_HEIGHT / 2,
	}

	MARGIN :: f32(14)
	clamped := raylib.Vector2{
		clamp(screen.x, MARGIN, SCREEN_WIDTH - MARGIN),
		clamp(screen.y, MARGIN, SCREEN_HEIGHT - MARGIN),
	}
	if clamped.x == screen.x && clamped.y == screen.y {
		return // door is on-screen
	}

	dir := raylib.Vector2{screen.x - SCREEN_WIDTH / 2, screen.y - SCREEN_HEIGHT / 2}
	angle_rad := math.atan2_f32(dir.y, dir.x)
	angle_deg := angle_rad * 180.0 / math.PI

	pulse := (math.sin_f32(f32(raylib.GetTime()) * 6.0) + 1.0) * 0.5
	alpha := u8(160 + 95 * pulse)
	color := raylib.Color{0x33, 0xFF, 0x66, alpha}
	raylib.DrawPoly(clamped, 3, 7, angle_deg, color)
	raylib.DrawPolyLines(clamped, 3, 7, angle_deg, raylib.Color{0, 0, 0, 200})
}

// ---------------------------------------------------------------------------
// Phase: Paused
// ---------------------------------------------------------------------------

@(private = "file")
PAUSE_ITEMS :: [4]cstring{"CONTINUE", "AUDIO", "CONTROLS", "QUIT"}

@(private = "file")
update_paused :: proc(dt: f32) {
	if gs.pause_show_controls {
		update_controls_screen()
		return
	}

	if gs.pause_show_audio {
		update_audio_settings(dt)
		return
	}

	if input_back() {
		raylib.PlaySound(gs.sfx_back)
		gs.phase = .Playing
		return
	}

	if input_menu_down() {
		gs.pause_selection = (gs.pause_selection + 1) %% len(PAUSE_ITEMS)
	}
	if input_menu_up() {
		gs.pause_selection = (gs.pause_selection - 1) %% len(PAUSE_ITEMS)
	}

	if input_confirm() {
		switch gs.pause_selection {
		case 0: // Continue
			raylib.PlaySound(gs.sfx_confirm)
			gs.phase = .Playing
		case 1: // Audio
			raylib.PlaySound(gs.sfx_confirm)
			gs.pause_show_audio = true
		case 2: // Controls
			raylib.PlaySound(gs.sfx_confirm)
			gs.pause_show_controls = true
		case 3: // Quit
			raylib.PlaySound(gs.sfx_back)
			unload_map_data()
			gs.phase = .Main_Menu
			gs.menu_selection = 0
			gs.menu_timer = 0
			gs.menu_fall_frame = 0
			gs.menu_fall_timer = 0
			raylib.StopMusicStream(gs.music_theme)
			raylib.StopMusicStream(gs.music_boss)
			raylib.PlayMusicStream(gs.music_cutscene)
		}
	}
}

@(private = "file")
draw_paused :: proc() {
	// Draw the game world underneath
	draw_playing()

	// Dim overlay
	raylib.DrawRectangle(0, 0, SCREEN_WIDTH, SCREEN_HEIGHT, raylib.Color{0, 0, 0, 180})

	if gs.pause_show_controls {
		draw_controls_screen()
		return
	}

	if gs.pause_show_audio {
		draw_audio_settings()
		return
	}

	draw_pause_map()

	title: cstring = "PAUSED"
	title_size :: i32(16)
	title_w := raylib.MeasureText(title, title_size)
	raylib.DrawText(title, (SCREEN_WIDTH - title_w) / 2, 140, title_size, raylib.WHITE)

	item_size :: i32(10)
	item_base_y :: i32(170)
	item_spacing :: i32(16)

	for item, i in PAUSE_ITEMS {
		item_w := raylib.MeasureText(item, item_size)
		item_x := (SCREEN_WIDTH - item_w) / 2
		item_y := item_base_y + i32(i) * item_spacing

		color := raylib.Color{150, 150, 150, 255}
		if i == gs.pause_selection {
			color = raylib.WHITE
		}
		raylib.DrawText(item, item_x, item_y, item_size, color)
	}

	items := PAUSE_ITEMS
	sel_item := items[gs.pause_selection]
	sel_w := raylib.MeasureText(sel_item, item_size)
	arrow_x := (SCREEN_WIDTH - sel_w) / 2 - 12
	arrow_y := item_base_y + i32(gs.pause_selection) * item_spacing
	raylib.DrawText(">", arrow_x, arrow_y, item_size, raylib.WHITE)
}

@(private = "file")
draw_pause_map :: proc() {
	CELL :: i32(3)
	mw := i32(gs.map_data.width)
	mh := i32(gs.map_data.height)
	map_px_w := mw * CELL
	map_px_h := mh * CELL
	ox := (SCREEN_WIDTH - map_px_w) / 2
	oy := i32(16)

	// Framed background
	raylib.DrawRectangle(ox - 3, oy - 3, map_px_w + 6, map_px_h + 6, raylib.Color{0, 0, 0, 220})
	raylib.DrawRectangleLines(ox - 3, oy - 3, map_px_w + 6, map_px_h + 6, raylib.Color{80, 80, 80, 255})

	wall_color := raylib.Color{180, 180, 180, 255}
	for row, ry in gs.map_data.grid {
		for cell, cx in row {
			sym := cell.symbol
			if sym == '.' || sym == 's' || sym == 'b' || sym == 'g' ||
			   sym == 'd' || sym == 't' || sym == '*' || sym == 'B' || sym == '@' {
				continue
			}
			x := ox + i32(cx) * CELL
			y := oy + i32(ry) * CELL
			raylib.DrawRectangle(x, y, CELL, CELL, wall_color)
		}
	}

	// Player marker (yellow)
	px := ox + i32(gs.player.pos.x / TILE_SIZE) * CELL
	py := oy + i32(gs.player.pos.y / TILE_SIZE) * CELL
	raylib.DrawRectangle(px - 1, py - 1, CELL + 2, CELL + 2, raylib.Color{0xFF, 0xD7, 0x00, 255})

	// Door marker (pulsing green)
	if gs.door.state != .Inactive {
		dx := ox + i32(gs.door.pos.x / TILE_SIZE) * CELL
		dy := oy + i32(gs.door.pos.y / TILE_SIZE) * CELL
		pulse := (math.sin_f32(f32(raylib.GetTime()) * 4.0) + 1.0) * 0.5
		alpha := u8(140 + 115 * pulse)
		raylib.DrawRectangle(dx - 1, dy - 1, CELL + 2, CELL + 2, raylib.Color{0x33, 0xFF, 0x66, alpha})
	}

	// Boss marker (red)
	if gs.moloch.active && gs.moloch.state != .Dead {
		bx := ox + i32(gs.moloch.pos.x / TILE_SIZE) * CELL
		by := oy + i32(gs.moloch.pos.y / TILE_SIZE) * CELL
		raylib.DrawRectangle(bx - 1, by - 1, CELL + 2, CELL + 2, raylib.Color{0xFF, 0x33, 0x33, 255})
	}
}

@(private = "file")
update_controls_screen :: proc() {
	if gs.controls_listening {
		// ESC cancels
		if raylib.IsKeyPressed(.ESCAPE) {
			gs.controls_listening = false
			raylib.PlaySound(gs.sfx_back)
			return
		}
		// Scan remappable buttons
		if gamepad_active() {
			for btn in REMAPPABLE_BUTTONS {
				if raylib.IsGamepadButtonPressed(GAMEPAD_ID, btn) {
					apply_gamepad_binding(gs.controls_selection, btn)
					gs.controls_listening = false
					raylib.PlaySound(gs.sfx_confirm)
					return
				}
			}
		}
		return
	}

	// No gamepad: read-only, just exit
	if !gamepad_active() {
		if input_back() || input_confirm() {
			raylib.PlaySound(gs.sfx_back)
			gs.pause_show_controls = false
			gs.controls_selection = 0
		}
		return
	}

	if input_back() {
		raylib.PlaySound(gs.sfx_back)
		gs.pause_show_controls = false
		gs.controls_selection = 0
		return
	}

	if input_menu_up() {
		gs.controls_selection = (gs.controls_selection - 1) %% REMAPPABLE_ACTION_COUNT
	}
	if input_menu_down() {
		gs.controls_selection = (gs.controls_selection + 1) %% REMAPPABLE_ACTION_COUNT
	}

	if input_confirm() {
		gs.controls_listening = true
		raylib.PlaySound(gs.sfx_confirm)
	}
}

@(private = "file")
draw_controls_screen :: proc() {
	title: cstring = "CONTROLS"
	title_size :: i32(16)
	title_w := raylib.MeasureText(title, title_size)
	raylib.DrawText(title, (SCREEN_WIDTH - title_w) / 2, 50, title_size, raylib.Color{0xFF, 0x33, 0x33, 0xFF})

	label_size :: i32(10)
	col_label_x :: i32(140)
	col_key_x   :: i32(360)
	row_y       :: i32(80)
	row_h       :: i32(18)

	gp := gamepad_active()

	if !gp {
		// Keyboard display — read-only
		controls_kb := [?][2]cstring{
			{"Move",                    "A / D  or  LEFT / RIGHT"},
			{"Jump",                    "W  or  UP"},
			{"Dash",                    "SPACE"},
			{"Quick Attack",            "J  or  LEFT CLICK"},
			{"Secondary Scythe Attack", "K  or  RIGHT CLICK"},
			{"Summon Blood Scythe",     "R"},
			{"Summon Blood Fangs",      "F"},
			{"Pause",                   "ESC"},
		}
		for entry, i in controls_kb {
			y := row_y + i32(i) * row_h
			raylib.DrawText(entry[0], col_label_x, y, label_size, raylib.Color{200, 200, 200, 255})
			raylib.DrawText(entry[1], col_key_x, y, label_size, raylib.WHITE)
		}
		back: cstring = "Press ESC or ENTER to go back"
		back_w := raylib.MeasureText(back, label_size)
		raylib.DrawText(back, (SCREEN_WIDTH - back_w) / 2, 250, label_size, raylib.Color{150, 150, 150, 255})
		return
	}

	// Gamepad display — interactive remapping
	// Static row: Move
	raylib.DrawText("Move", col_label_x, row_y, label_size, raylib.Color{200, 200, 200, 255})
	raylib.DrawText("Left Stick", col_key_x, row_y, label_size, raylib.WHITE)

	// Remappable rows
	remap_start_y := row_y + row_h
	for i in 0 ..< REMAPPABLE_ACTION_COUNT {
		y := remap_start_y + i32(i) * row_h
		selected := i == gs.controls_selection

		label_color: raylib.Color = selected ? raylib.WHITE : raylib.Color{200, 200, 200, 255}
		raylib.DrawText(REMAPPABLE_ACTION_NAMES[i], col_label_x, y, label_size, label_color)

		// Button value
		btn_label: cstring = selected && gs.controls_listening ? "-" : gamepad_button_name(get_gamepad_binding(i))
		raylib.DrawText(btn_label, col_key_x, y, label_size, label_color)

		// Selection arrow
		if selected {
			raylib.DrawText(">", col_label_x - 12, y, label_size, raylib.WHITE)
		}
	}

	// Static row: Pause
	pause_y := remap_start_y + i32(REMAPPABLE_ACTION_COUNT) * row_h
	raylib.DrawText("Pause", col_label_x, pause_y, label_size, raylib.Color{200, 200, 200, 255})
	raylib.DrawText("START", col_key_x, pause_y, label_size, raylib.WHITE)

	// Hint text
	hint: cstring = gs.controls_listening ? "Press a button to assign, or ESC to cancel" : "Press A to remap, B to go back"
	hint_w := raylib.MeasureText(hint, 8)
	raylib.DrawText(hint, (SCREEN_WIDTH - hint_w) / 2, 260, 8, raylib.Color{150, 150, 150, 255})
}

// ---------------------------------------------------------------------------
// Phase: Round Won
// ---------------------------------------------------------------------------

@(private = "file")
update_round_won :: proc(dt: f32) {
	gs.phase_timer -= dt
	if gs.phase_timer <= 0 || input_confirm() {
		// Final descending level complete — go to Game_Won (keep map loaded for its draw)
		if gs.current_round + 1 >= ROUND_COUNT {
			gs.current_round += 1
			raylib.StopMusicStream(gs.music_theme)
			gs.phase = .Game_Won
			gs.phase_timer = 3.0
			return
		}

		unload_map_data()
		gs.current_round += 1
		if gs.current_round == 3 {
			// Play Moloch confronts Abaddon cutscene before level4
			gs.cutscene_scene = .Moloch_Confronts_Abaddon
			gs.cutscene_line = 0
			gs.cutscene_shake = 0
			gs.phase = .Cutscene
			if raylib.IsMusicStreamPlaying(gs.music_theme) {
				raylib.StopMusicStream(gs.music_theme)
			}
			raylib.PlayMusicStream(gs.music_cutscene)
		} else {
			start_round()
		}
	}
}

@(private = "file")
draw_round_won :: proc() {
	draw_parallax_bg()
	raylib.BeginMode2D(gs.camera)
	draw_map()
	draw_door(&gs.door)
	draw_enemies(&gs.enemies, gs.white_flash_shader)
	draw_flamewardens(&gs.flamewardens, gs.white_flash_shader)
	draw_devils(&gs.devils, gs.white_flash_shader)
	draw_moloch(&gs.moloch, gs.white_flash_shader)
	draw_gadreela(&gs.gadreela)
	draw_player(&gs.player, gs.white_flash_shader)
	raylib.EndMode2D()

	// Eased fade-to-black based on phase_timer countdown
	fade_t := 1 - (gs.phase_timer / ROUND_WON_FADE_DURATION)
	overlay_alpha := u8(ease_out_quad(fade_t) * 255)
	raylib.DrawRectangle(0, 0, SCREEN_WIDTH, SCREEN_HEIGHT, raylib.Color{0, 0, 0, overlay_alpha})
}

// ---------------------------------------------------------------------------
// Phase: Game Won
// ---------------------------------------------------------------------------

@(private = "file")
update_game_won :: proc(dt: f32) {
	gs.phase_timer -= dt
	if gs.phase_timer <= 0 && input_confirm() {
		unload_map_data()
		gs.current_round = 0
		gs.phase = .Main_Menu
		raylib.StopMusicStream(gs.music_boss)
		raylib.PlayMusicStream(gs.music_cutscene)
	}
}

@(private = "file")
draw_game_won :: proc() {
	draw_parallax_bg()
	raylib.BeginMode2D(gs.camera)
	draw_map()
	draw_moloch(&gs.moloch, gs.white_flash_shader)
	draw_player(&gs.player, gs.white_flash_shader)
	raylib.EndMode2D()

	fade_t := 1 - (gs.phase_timer / 3.0)
	eased := ease_out_quad(fade_t)
	overlay_alpha := u8(eased * 255)
	raylib.DrawRectangle(0, 0, SCREEN_WIDTH, SCREEN_HEIGHT, raylib.Color{0, 0, 0, overlay_alpha})

	text_alpha := u8(eased * 255)
	title : cstring = "VICTORY"
	title_w := raylib.MeasureText(title, 20)
	raylib.DrawText(title, (SCREEN_WIDTH - title_w) / 2, SCREEN_HEIGHT / 2 - 20, 20, raylib.Color{0xFF, 0xD7, 0x00, text_alpha})

	sub : cstring = gamepad_active() ? "Press A to return to menu" : "Press ENTER to return to menu"
	sub_w := raylib.MeasureText(sub, 10)
	raylib.DrawText(sub, (SCREEN_WIDTH - sub_w) / 2, SCREEN_HEIGHT / 2 + 10, 10, raylib.Color{200, 200, 200, text_alpha})
}

// ---------------------------------------------------------------------------
// Phase: Game Over
// ---------------------------------------------------------------------------

@(private = "file")
GAME_OVER_FADE_DURATION :: f32(2.0)
GAME_OVER_MENU_DELAY    :: f32(1.2)

@(private = "file")
update_game_over :: proc(dt: f32) {
	gs.game_over_timer += dt
	if gs.game_over_timer >= GAME_OVER_FADE_DURATION && input_confirm() {
		unload_map_data()
		gs.current_round = 0
		start_round()
	}
}

@(private = "file")
draw_game_over :: proc() {
	draw_parallax_bg()
	raylib.BeginMode2D(gs.camera)
	draw_map()
	draw_player(&gs.player, gs.white_flash_shader)
	raylib.EndMode2D()

	// Ease-to-black overlay (quadratic ease-out)
	fade_t := clamp(gs.game_over_timer / GAME_OVER_FADE_DURATION, 0, 1)
	eased := 1 - (1 - fade_t) * (1 - fade_t)
	overlay_alpha := u8(eased * 255)
	raylib.DrawRectangle(0, 0, SCREEN_WIDTH, SCREEN_HEIGHT, raylib.Color{0, 0, 0, overlay_alpha})

	// Menu fade-in after short delay
	menu_t := clamp((gs.game_over_timer - GAME_OVER_MENU_DELAY) / (GAME_OVER_FADE_DURATION - GAME_OVER_MENU_DELAY), 0, 1)
	if menu_t <= 0 {
		return
	}
	menu_alpha := u8(menu_t * 255)

	title : cstring = gs.player.hp <= 0 ? "YOU DIED" : "BLOOD DEPLETED"
	title_w := raylib.MeasureText(title, 20)
	raylib.DrawText(title, (SCREEN_WIDTH - title_w) / 2, SCREEN_HEIGHT / 2 - 20, 20, raylib.Color{0xFF, 0x33, 0x33, menu_alpha})

	sub : cstring = gamepad_active() ? "Press A to play again" : "Press ENTER to play again"
	sub_w := raylib.MeasureText(sub, 10)
	raylib.DrawText(sub, (SCREEN_WIDTH - sub_w) / 2, SCREEN_HEIGHT / 2 + 10, 10, raylib.Color{255, 255, 255, menu_alpha})
}

// ---------------------------------------------------------------------------
// Audio settings (shared between main menu and pause menu)
// ---------------------------------------------------------------------------

@(private = "file")
apply_volumes :: proc() {
	raylib.SetSoundVolume(gs.sfx_jump, gs.sfx_volume)
	raylib.SetSoundVolume(gs.sfx_footsteps, gs.sfx_volume)
	raylib.SetSoundVolume(gs.sfx_confirm, gs.sfx_volume)
	raylib.SetSoundVolume(gs.sfx_back, gs.sfx_volume)
	raylib.SetSoundVolume(gs.sfx_hit, gs.sfx_volume)
	raylib.SetSoundVolume(gs.sfx_dash, gs.sfx_volume)
	raylib.SetSoundVolume(gs.sfx_dash_impact, gs.sfx_volume)
	raylib.SetSoundVolume(gs.sfx_quick_attack, gs.sfx_volume)
	raylib.SetSoundVolume(gs.sfx_summon, gs.sfx_volume)
	raylib.SetSoundVolume(gs.sfx_despawn, gs.sfx_volume)
	raylib.SetSoundVolume(gs.sfx_scythe_attack, gs.sfx_volume)
	raylib.SetSoundVolume(gs.sfx_scythe_qa_fang, gs.sfx_volume)
	raylib.SetSoundVolume(gs.sfx_boss_laugh, gs.sfx_volume)
	raylib.SetSoundVolume(gs.sfx_boss_breath, gs.sfx_volume)
	raylib.SetSoundVolume(gs.sfx_boss_meteor, gs.sfx_volume)
	raylib.SetSoundVolume(gs.sfx_flameball_agroed, gs.sfx_volume)
	raylib.SetSoundVolume(gs.sfx_fw_attack, gs.sfx_volume)
	raylib.SetSoundVolume(gs.sfx_devil_attack, gs.sfx_volume)
	raylib.SetSoundVolume(gs.sfx_you_died, gs.sfx_volume)
	raylib.SetMusicVolume(gs.music_theme, gs.music_volume)
	raylib.SetMusicVolume(gs.music_cutscene, gs.music_volume)
	raylib.SetMusicVolume(gs.music_boss, gs.music_volume)
}

@(private = "file")
update_audio_settings :: proc(dt: f32) {
	VOLUME_STEP :: f32(0.1)

	if input_back() || input_confirm() {
		raylib.PlaySound(gs.sfx_back)
		gs.pause_show_audio = false
		gs.audio_selection = 0
		return
	}

	if input_menu_up() {
		gs.audio_selection = (gs.audio_selection - 1) %% 2
	}
	if input_menu_down() {
		gs.audio_selection = (gs.audio_selection + 1) %% 2
	}

	if input_menu_left() {
		if gs.audio_selection == 0 {
			gs.music_volume = max(gs.music_volume - VOLUME_STEP, 0.0)
		} else {
			gs.sfx_volume = max(gs.sfx_volume - VOLUME_STEP, 0.0)
		}
		apply_volumes()
	}
	if input_menu_right() {
		if gs.audio_selection == 0 {
			gs.music_volume = min(gs.music_volume + VOLUME_STEP, 1.0)
		} else {
			gs.sfx_volume = min(gs.sfx_volume + VOLUME_STEP, 1.0)
		}
		apply_volumes()
		if gs.audio_selection == 1 {
			raylib.PlaySound(gs.sfx_confirm)
		}
	}
}

@(private = "file")
draw_audio_settings :: proc() {
	title: cstring = "AUDIO"
	title_size :: i32(16)
	title_w := raylib.MeasureText(title, title_size)
	raylib.DrawText(title, (SCREEN_WIDTH - title_w) / 2, 80, title_size, raylib.Color{0xFF, 0x33, 0x33, 0xFF})

	label_size :: i32(10)
	bar_y_base :: i32(130)
	bar_spacing :: i32(30)
	bar_x :: i32(260)
	bar_w :: i32(120)
	bar_h :: i32(8)

	labels := [2]cstring{"MUSIC", "SFX"}
	volumes := [2]f32{gs.music_volume, gs.sfx_volume}

	for label, i in labels {
		y := bar_y_base + i32(i) * bar_spacing

		color: raylib.Color = {150, 150, 150, 255}
		if i == gs.audio_selection {
			color = raylib.WHITE
		}

		// Label
		label_w := raylib.MeasureText(label, label_size)
		raylib.DrawText(label, bar_x - label_w - 16, y - 2, label_size, color)

		// Background bar
		raylib.DrawRectangle(bar_x, y, bar_w, bar_h, raylib.Color{60, 60, 60, 255})

		// Filled portion
		fill_w := i32(volumes[i] * f32(bar_w))
		raylib.DrawRectangle(bar_x, y, fill_w, bar_h, color)

		// Percentage text
		pct := fmt.ctprintf("%d%%", int(volumes[i] * 100 + 0.5))
		raylib.DrawText(pct, bar_x + bar_w + 8, y - 2, label_size, color)

		// Arrows for selected
		if i == gs.audio_selection {
			raylib.DrawText("<", bar_x - 10, y - 2, label_size, raylib.WHITE)
			raylib.DrawText(">", bar_x + bar_w + 40, y - 2, label_size, raylib.WHITE)
		}
	}

	back: cstring = "LEFT/RIGHT to adjust, ESC to go back"
	back_w := raylib.MeasureText(back, 8)
	raylib.DrawText(back, (SCREEN_WIDTH - back_w) / 2, 220, 8, raylib.Color{150, 150, 150, 255})
}

// ---------------------------------------------------------------------------
// Camera
// ---------------------------------------------------------------------------

@(private = "file")
update_camera :: proc(dt: f32) {
	gs.camera.target = gs.player.pos

	// Clamp camera to map bounds
	map_w := f32(gs.map_data.width) * TILE_SIZE
	map_h := f32(gs.map_data.height) * TILE_SIZE
	half_w := f32(SCREEN_WIDTH) / (2 * gs.camera.zoom)
	half_h := f32(SCREEN_HEIGHT) / (2 * gs.camera.zoom)

	if gs.camera.target.x < half_w {
		gs.camera.target.x = half_w
	}
	if gs.camera.target.x > map_w - half_w {
		gs.camera.target.x = map_w - half_w
	}
	if gs.camera.target.y < half_h {
		gs.camera.target.y = half_h
	}
	if gs.camera.target.y > map_h - half_h {
		gs.camera.target.y = map_h - half_h
	}

	// Combat screenshake
	if gs.screen_shake > 0 {
		gs.screen_shake -= dt
		if gs.screen_shake > 0 {
			intensity := gs.screen_shake / SCREENSHAKE_DURATION
			mag := SCREENSHAKE_MAGNITUDE * intensity
			gs.camera.target.x += rand.float32_range(-mag, mag)
			gs.camera.target.y += rand.float32_range(-mag, mag)
		}
	}
}

// ---------------------------------------------------------------------------
// Parallax background
// ---------------------------------------------------------------------------

@(private = "file")
draw_parallax_bg :: proc() {
	speeds := PARALLAX_SPEEDS
	draw_order := PARALLAX_DRAW_ORDER
	for di in 0 ..< PARALLAX_LAYER_COUNT {
		layer := draw_order[di]
		offset := gs.camera.target.x * speeds[layer] * gs.camera.zoom
		wrapped : f32 = offset - f32(SCREEN_WIDTH) * math.floor_f32(offset / f32(SCREEN_WIDTH))

		src := raylib.Rectangle{0, f32(layer * SCREEN_HEIGHT), f32(SCREEN_WIDTH), f32(SCREEN_HEIGHT)}
		raylib.DrawTextureRec(gs.parallax_tex, src, {-wrapped, 0}, raylib.WHITE)
		raylib.DrawTextureRec(gs.parallax_tex, src, {f32(SCREEN_WIDTH) - wrapped, 0}, raylib.WHITE)
	}
}

// ---------------------------------------------------------------------------
// Map drawing
// ---------------------------------------------------------------------------

@(private = "file")
draw_map :: proc() {
	cam := gs.camera
	half_w := f32(SCREEN_WIDTH) / (2 * cam.zoom)
	half_h := f32(SCREEN_HEIGHT) / (2 * cam.zoom)
	min_x := int((cam.target.x - half_w) / TILE_SIZE) - 1
	max_x := int((cam.target.x + half_w) / TILE_SIZE) + 1
	min_y := int((cam.target.y - half_h) / TILE_SIZE) - 1
	max_y := int((cam.target.y + half_h) / TILE_SIZE) + 1

	if min_x < 0 {
		min_x = 0
	}
	if min_y < 0 {
		min_y = 0
	}
	if max_x >= gs.map_data.width {
		max_x = gs.map_data.width - 1
	}
	if max_y >= gs.map_data.height {
		max_y = gs.map_data.height - 1
	}

	for ry in min_y ..= max_y {
		if ry >= len(gs.map_data.grid) {
			break
		}
		row := gs.map_data.grid[ry]
		for cx in min_x ..= max_x {
			if cx >= len(row) {
				break
			}
			cell := row[cx]
			draw_x := f32(cx) * TILE_SIZE
			draw_y := f32(ry) * TILE_SIZE

			if cell.symbol == '.' || cell.symbol == 's' || cell.symbol == 'b' || cell.symbol == 'g' || cell.symbol == 'd' || cell.symbol == '@' {
				continue
			}

			textures, has_tex := gs.tile_textures[cell.symbol]
			if !has_tex || len(textures) == 0 {
				continue
			}

			idx := cell.tile_index
			if idx >= len(textures) {
				idx = 0
			}
			tex := textures[idx]
			raylib.DrawTexture(tex, i32(draw_x), i32(draw_y), raylib.WHITE)
		}
	}
}
