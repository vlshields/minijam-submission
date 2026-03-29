package game

import "vendor:raylib"
import dm "../dotmap"
import "core:fmt"
import "core:math"
import "core:math/rand"
import "core:strings"

Game_Phase :: enum {
	Main_Menu,
	Playing,
	Paused,
	Round_Won,
	Game_Over,
}

Game_State :: struct {
	map_data:       dm.Dot_Map,
	tile_textures:  map[u8][dynamic]raylib.Texture2D,
	camera:         raylib.Camera2D,
	player:         Player,
	companion:      Companion,
	blood_scythe:   Blood_Scythe,
	enemies:            Enemy_Pool,
	flamewardens:       FW_Pool,
	devils:             Devil_Pool,
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
	round_timer:    f32,
	blood_points:   i32,
	bp_drain_timer: f32,
	phase_timer:    f32,
	enemy_scale:    f32,

	// Pause menu
	pause_selection:     int,
	pause_show_controls: bool,

	// Main menu
	menu_selection:  int,
	menu_timer:      f32,
	menu_title_y:    f32,
	menu_items_x:    f32,
	menu_fall_frame: f32,
	menu_fall_timer: f32,
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

	// Assign random tile variants for 'w' cells
	if w_texs, ok := gs.tile_textures['w']; ok {
		num_variants := len(w_texs)
		if num_variants > 1 {
			for &row in gs.map_data.grid {
				for &cell in row {
					if cell.symbol == 'w' {
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
	is_endless := gs.current_round >= ROUND_COUNT
	map_path: string
	if is_endless {
		endless_maps := ENDLESS_MAPS
		map_path = endless_maps[rand.int_max(len(endless_maps))]
	} else {
		round_maps := ROUND_MAPS
		map_path = round_maps[gs.current_round]
	}
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
	gs.player.dash_timer = 0
	gs.player.dash_cooldown = 0
	gs.player.damage_flash_timer = 0
	gs.player.quick_attack_state = .None

	gs.companion.state = .Inactive
	gs.blood_scythe.state = .Inactive

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

	// Compute enemy scale for endless rounds (10% increase per round)
	if is_endless {
		gs.enemy_scale = math.pow(f32(ENDLESS_SCALE_PER_ROUND), f32(gs.current_round - ROUND_COUNT + 1))
	} else {
		gs.enemy_scale = 1.0
	}

	// Scale enemy HP for endless rounds
	if gs.enemy_scale > 1.0 {
		for i := 0; i < gs.enemies.count; i += 1 {
			gs.enemies.enemies[i].hp *= gs.enemy_scale
		}
		for i := 0; i < gs.flamewardens.count; i += 1 {
			gs.flamewardens.wardens[i].hp *= gs.enemy_scale
		}
		for i := 0; i < gs.devils.count; i += 1 {
			gs.devils.devils[i].hp *= gs.enemy_scale
		}
	}

	// BP: first round starts fresh, later rounds carry over with floor
	if gs.current_round == 0 {
		gs.blood_points = BP_STARTING
	} else if gs.blood_points < BP_MIN_CARRY {
		gs.blood_points = BP_MIN_CARRY
	}

	if is_endless {
		gs.round_timer = ENDLESS_ROUND_DURATION
	} else {
		durations := ROUND_DURATIONS
		gs.round_timer = durations[gs.current_round]
	}
	gs.bp_drain_timer = BP_DRAIN_INTERVAL
	gs.phase = .Playing
	gs.phase_timer = 0

	gs.camera.target = gs.player.pos
}

// ---------------------------------------------------------------------------
// Init / Update / Shutdown
// ---------------------------------------------------------------------------

init :: proc() {
	raylib.InitWindow(SCREEN_WIDTH, SCREEN_HEIGHT, "Primal")

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

	// Init entity textures (loaded once, reused across rounds)
	init_player(&gs.player, {100, 100})
	init_companion(&gs.companion)
	init_blood_scythe(&gs.blood_scythe)
	init_enemies(&gs.enemies)
	init_flamewardens(&gs.flamewardens)
	init_devils(&gs.devils)

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

	switch gs.phase {
	case .Main_Menu:
		update_main_menu(dt)
	case .Playing:
		update_playing(dt)
	case .Paused:
		update_paused(dt)
	case .Round_Won:
		update_round_won(dt)
	case .Game_Over:
		update_game_over(dt)
	}

	// Draw to virtual render target
	raylib.BeginTextureMode(gs.render_target)
	raylib.ClearBackground(gs.bg_color)

	switch gs.phase {
	case .Main_Menu:
		draw_main_menu()
	case .Playing:
		draw_playing()
	case .Paused:
		draw_paused()
	case .Round_Won:
		draw_round_won()
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
	raylib.UnloadShader(gs.white_flash_shader)
	raylib.UnloadTexture(gs.parallax_tex)
	raylib.UnloadRenderTexture(gs.render_target)
	unload_map_data()
	unload_player(&gs.player)
	unload_companion(&gs.companion)
	unload_blood_scythe(&gs.blood_scythe)
	unload_enemies(&gs.enemies)
	unload_flamewardens(&gs.flamewardens)
	unload_devils(&gs.devils)
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
	if raylib.IsKeyPressed(.DOWN) || raylib.IsKeyPressed(.S) {
		gs.menu_selection = (gs.menu_selection + 1) %% 2
	}
	if raylib.IsKeyPressed(.UP) || raylib.IsKeyPressed(.W) {
		gs.menu_selection = (gs.menu_selection - 1) %% 2
	}

	// Confirm
	if raylib.IsKeyPressed(.ENTER) || raylib.IsKeyPressed(.KP_ENTER) {
		if gs.menu_selection == 0 {
			start_round()
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
	items := [2]cstring{"PLAY", "OPTIONS"}
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

// Phase: Playing
// ---------------------------------------------------------------------------

@(private = "file")
update_playing :: proc(dt: f32) {
	if raylib.IsKeyPressed(.ESCAPE) {
		gs.phase = .Paused
		gs.pause_selection = 0
		gs.pause_show_controls = false
		return
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
		gs.phase = .Game_Over
		return
	}

	// Round timer (0 = infinite, for round 4 TBD)
	if gs.round_timer > 0 {
		gs.round_timer -= dt
		if gs.round_timer <= 0 {
			gs.round_timer = 0
			gs.phase = .Round_Won
			gs.phase_timer = 2.0
			return
		}
	}

	// Gameplay
	update_quick_attack(&gs.player, &gs.companion, &gs.blood_scythe, dt)
	update_player(&gs.player, &gs.map_data, dt)
	update_companion(&gs.companion, &gs.player, &gs.blood_scythe, dt)
	update_blood_scythe(&gs.blood_scythe, &gs.player, &gs.companion, dt)
	update_enemies(&gs.enemies, &gs.player, &gs.companion, &gs.blood_scythe, &gs.camera, &gs.map_data, &gs.blood_points, gs.enemy_scale, dt)
	update_flamewardens(&gs.flamewardens, &gs.player, &gs.companion, &gs.blood_scythe, &gs.camera, &gs.map_data, &gs.blood_points, gs.enemy_scale, dt)
	update_devils(&gs.devils, &gs.player, &gs.companion, &gs.blood_scythe, &gs.camera, &gs.map_data, &gs.blood_points, gs.enemy_scale, dt)
	update_camera(dt)
}

@(private = "file")
draw_playing :: proc() {
	draw_parallax_bg()
	raylib.BeginMode2D(gs.camera)
	draw_map()
	draw_enemies(&gs.enemies, gs.white_flash_shader)
	draw_flamewardens(&gs.flamewardens, gs.white_flash_shader)
	draw_devils(&gs.devils, gs.white_flash_shader)
	draw_player(&gs.player, gs.white_flash_shader)
	draw_companion(&gs.companion, &gs.player)
	draw_blood_scythe(&gs.blood_scythe, &gs.player)
	raylib.EndMode2D()

	draw_player_hud(&gs.player)
	draw_bp_hud(gs.blood_points, gs.round_timer, gs.current_round)
}

// ---------------------------------------------------------------------------
// Phase: Paused
// ---------------------------------------------------------------------------

@(private = "file")
PAUSE_ITEMS :: [3]cstring{"CONTINUE", "CONTROLS", "QUIT"}

@(private = "file")
update_paused :: proc(dt: f32) {
	if gs.pause_show_controls {
		if raylib.IsKeyPressed(.ESCAPE) || raylib.IsKeyPressed(.ENTER) || raylib.IsKeyPressed(.KP_ENTER) {
			gs.pause_show_controls = false
		}
		return
	}

	if raylib.IsKeyPressed(.ESCAPE) {
		gs.phase = .Playing
		return
	}

	if raylib.IsKeyPressed(.DOWN) || raylib.IsKeyPressed(.S) {
		gs.pause_selection = (gs.pause_selection + 1) %% len(PAUSE_ITEMS)
	}
	if raylib.IsKeyPressed(.UP) || raylib.IsKeyPressed(.W) {
		gs.pause_selection = (gs.pause_selection - 1) %% len(PAUSE_ITEMS)
	}

	if raylib.IsKeyPressed(.ENTER) || raylib.IsKeyPressed(.KP_ENTER) {
		switch gs.pause_selection {
		case 0: // Continue
			gs.phase = .Playing
		case 1: // Controls
			gs.pause_show_controls = true
		case 2: // Quit
			unload_map_data()
			gs.phase = .Main_Menu
			gs.menu_selection = 0
			gs.menu_timer = 0
			gs.menu_fall_frame = 0
			gs.menu_fall_timer = 0
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

	title: cstring = "PAUSED"
	title_size :: i32(20)
	title_w := raylib.MeasureText(title, title_size)
	raylib.DrawText(title, (SCREEN_WIDTH - title_w) / 2, 80, title_size, raylib.WHITE)

	item_size :: i32(10)
	item_base_y :: i32(140)
	item_spacing :: i32(20)

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
draw_controls_screen :: proc() {
	title: cstring = "CONTROLS"
	title_size :: i32(16)
	title_w := raylib.MeasureText(title, title_size)
	raylib.DrawText(title, (SCREEN_WIDTH - title_w) / 2, 50, title_size, raylib.Color{0xFF, 0x33, 0x33, 0xFF})

	label_size :: i32(10)
	col_label_x :: i32(140)
	col_key_x   :: i32(360)
	row_y       :: i32(90)
	row_h       :: i32(18)

	controls := [?][2]cstring{
		{"Move", "A / D  or  LEFT / RIGHT"},
		{"Jump", "W  or  UP"},
		{"Dash", "SPACE"},
		{"Quick Attack", "J  or  LEFT CLICK"},
		{"Secondary Scythe Attack", "K  or  RIGHT CLICK"},
		{"Summon Blood Scythe", "R"},
		{"Summon Blood Fangs", "F"},
		{"Pause", "ESC"},
	}

	for entry, i in controls {
		y := row_y + i32(i) * row_h
		raylib.DrawText(entry[0], col_label_x, y, label_size, raylib.Color{200, 200, 200, 255})
		raylib.DrawText(entry[1], col_key_x, y, label_size, raylib.WHITE)
	}

	back: cstring = "Press ESC or ENTER to go back"
	back_w := raylib.MeasureText(back, label_size)
	raylib.DrawText(back, (SCREEN_WIDTH - back_w) / 2, 250, label_size, raylib.Color{150, 150, 150, 255})
}

// ---------------------------------------------------------------------------
// Phase: Round Won
// ---------------------------------------------------------------------------

@(private = "file")
update_round_won :: proc(dt: f32) {
	gs.phase_timer -= dt
	if gs.phase_timer <= 0 || raylib.IsKeyPressed(.ENTER) || raylib.IsKeyPressed(.KP_ENTER) {
		unload_map_data()
		gs.current_round += 1
		start_round()
	}
}

@(private = "file")
draw_round_won :: proc() {
	draw_parallax_bg()
	raylib.BeginMode2D(gs.camera)
	draw_map()
	draw_enemies(&gs.enemies, gs.white_flash_shader)
	draw_flamewardens(&gs.flamewardens, gs.white_flash_shader)
	draw_devils(&gs.devils, gs.white_flash_shader)
	draw_player(&gs.player, gs.white_flash_shader)
	raylib.EndMode2D()

	raylib.DrawRectangle(0, 0, SCREEN_WIDTH, SCREEN_HEIGHT, raylib.Color{0, 0, 0, 160})

	title := fmt.ctprintf("ROUND %d COMPLETE", gs.current_round + 1)
	title_w := raylib.MeasureText(title, 20)
	raylib.DrawText(title, (SCREEN_WIDTH - title_w) / 2, SCREEN_HEIGHT / 2 - 20, 20, raylib.WHITE)

	sub : cstring = "Press ENTER to continue"
	sub_w := raylib.MeasureText(sub, 10)
	raylib.DrawText(sub, (SCREEN_WIDTH - sub_w) / 2, SCREEN_HEIGHT / 2 + 10, 10, raylib.Color{200, 200, 200, 255})
}

// ---------------------------------------------------------------------------
// Phase: Game Over
// ---------------------------------------------------------------------------

@(private = "file")
update_game_over :: proc(dt: f32) {
	if raylib.IsKeyPressed(.ENTER) || raylib.IsKeyPressed(.KP_ENTER) {
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

	raylib.DrawRectangle(0, 0, SCREEN_WIDTH, SCREEN_HEIGHT, raylib.Color{0, 0, 0, 180})

	title : cstring = gs.player.hp <= 0 ? "YOU DIED" : "BLOOD DEPLETED"
	title_w := raylib.MeasureText(title, 20)
	raylib.DrawText(title, (SCREEN_WIDTH - title_w) / 2, SCREEN_HEIGHT / 2 - 20, 20, raylib.Color{0xFF, 0x33, 0x33, 0xFF})

	sub : cstring = "Press ENTER to play again"
	sub_w := raylib.MeasureText(sub, 10)
	raylib.DrawText(sub, (SCREEN_WIDTH - sub_w) / 2, SCREEN_HEIGHT / 2 + 10, 10, raylib.WHITE)
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

			if cell.symbol == '.' || cell.symbol == 's' || cell.symbol == 'b' || cell.symbol == 'g' || cell.symbol == 'd' {
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
