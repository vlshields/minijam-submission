package game

import raylib "vendor:raylib"

// ---------------------------------------------------------------------------
// Gamepad constants
// ---------------------------------------------------------------------------

GAMEPAD_ID     :: 0
STICK_DEADZONE :: f32(0.25)

// ---------------------------------------------------------------------------
// Gamepad mapping (remappable)
// ---------------------------------------------------------------------------

Gamepad_Mapping :: struct {
	jump:             raylib.GamepadButton,
	dash:             raylib.GamepadButton,
	attack:           raylib.GamepadButton,
	scythe_secondary: raylib.GamepadButton,
	companion_toggle: raylib.GamepadButton,
	companion_summon: raylib.GamepadButton,
}

DEFAULT_GAMEPAD_MAPPING :: Gamepad_Mapping{
	jump             = .RIGHT_FACE_DOWN,
	dash             = .RIGHT_FACE_RIGHT,
	attack           = .RIGHT_FACE_LEFT,
	scythe_secondary = .RIGHT_FACE_UP,
	companion_toggle = .RIGHT_TRIGGER_1,
	companion_summon = .LEFT_TRIGGER_2,
}

active_gamepad_mapping: Gamepad_Mapping = DEFAULT_GAMEPAD_MAPPING

REMAPPABLE_ACTION_COUNT :: 6

REMAPPABLE_ACTION_NAMES := [REMAPPABLE_ACTION_COUNT]cstring{
	"Jump",
	"Dash",
	"Quick Attack",
	"Secondary Scythe Attack",
	"Companion (select)",
	"Companion (summon)",
}

REMAPPABLE_BUTTONS :: [8]raylib.GamepadButton{
	.RIGHT_FACE_DOWN, .RIGHT_FACE_RIGHT,
	.RIGHT_FACE_LEFT, .RIGHT_FACE_UP,
	.LEFT_TRIGGER_1,  .RIGHT_TRIGGER_1,
	.LEFT_TRIGGER_2,  .RIGHT_TRIGGER_2,
}

gamepad_button_name :: proc(button: raylib.GamepadButton) -> cstring {
	#partial switch button {
	case .RIGHT_FACE_DOWN:  return "A"
	case .RIGHT_FACE_RIGHT: return "B"
	case .RIGHT_FACE_LEFT:  return "X"
	case .RIGHT_FACE_UP:    return "Y"
	case .LEFT_TRIGGER_1:   return "LB"
	case .RIGHT_TRIGGER_1:  return "RB"
	case .LEFT_TRIGGER_2:   return "LT"
	case .RIGHT_TRIGGER_2:  return "RT"
	}
	return "???"
}

get_gamepad_binding :: proc(action_index: int) -> raylib.GamepadButton {
	switch action_index {
	case 0: return active_gamepad_mapping.jump
	case 1: return active_gamepad_mapping.dash
	case 2: return active_gamepad_mapping.attack
	case 3: return active_gamepad_mapping.scythe_secondary
	case 4: return active_gamepad_mapping.companion_toggle
	case 5: return active_gamepad_mapping.companion_summon
	}
	return .UNKNOWN
}

apply_gamepad_binding :: proc(action_index: int, button: raylib.GamepadButton) {
	old_button := get_gamepad_binding(action_index)

	// If another action already uses this button, swap it to our old button.
	for i in 0 ..< REMAPPABLE_ACTION_COUNT {
		if i != action_index && get_gamepad_binding(i) == button {
			set_gamepad_binding(i, old_button)
			break
		}
	}

	set_gamepad_binding(action_index, button)
}

set_gamepad_binding :: proc(action_index: int, button: raylib.GamepadButton) {
	switch action_index {
	case 0: active_gamepad_mapping.jump             = button
	case 1: active_gamepad_mapping.dash             = button
	case 2: active_gamepad_mapping.attack           = button
	case 3: active_gamepad_mapping.scythe_secondary = button
	case 4: active_gamepad_mapping.companion_toggle = button
	case 5: active_gamepad_mapping.companion_summon = button
	}
}

// ---------------------------------------------------------------------------
// Companion selection (gamepad only — keyboard uses R/F directly)
// ---------------------------------------------------------------------------

Selected_Companion :: enum {
	Scythe,
	Fangs,
}

selected_companion: Selected_Companion = .Scythe

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

gamepad_active :: proc() -> bool {
	return raylib.IsGamepadAvailable(GAMEPAD_ID)
}

// ---------------------------------------------------------------------------
// Gameplay input
// ---------------------------------------------------------------------------

input_move_left :: proc() -> bool {
	if raylib.IsKeyDown(.A) || raylib.IsKeyDown(.LEFT) {
		return true
	}
	if gamepad_active() && raylib.GetGamepadAxisMovement(GAMEPAD_ID, .LEFT_X) < -STICK_DEADZONE {
		return true
	}
	return false
}

input_move_right :: proc() -> bool {
	if raylib.IsKeyDown(.D) || raylib.IsKeyDown(.RIGHT) {
		return true
	}
	if gamepad_active() && raylib.GetGamepadAxisMovement(GAMEPAD_ID, .LEFT_X) > STICK_DEADZONE {
		return true
	}
	return false
}

input_jump :: proc() -> bool {
	if raylib.IsKeyPressed(.W) || raylib.IsKeyPressed(.UP) {
		return true
	}
	if gamepad_active() && raylib.IsGamepadButtonPressed(GAMEPAD_ID, active_gamepad_mapping.jump) {
		return true
	}
	return false
}

input_dash :: proc() -> bool {
	if raylib.IsKeyPressed(.SPACE) {
		return true
	}
	if gamepad_active() && raylib.IsGamepadButtonPressed(GAMEPAD_ID, active_gamepad_mapping.dash) {
		return true
	}
	return false
}

input_attack :: proc() -> bool {
	if raylib.IsKeyPressed(.J) || raylib.IsMouseButtonPressed(.LEFT) {
		return true
	}
	if gamepad_active() && raylib.IsGamepadButtonPressed(GAMEPAD_ID, active_gamepad_mapping.attack) {
		return true
	}
	return false
}

input_scythe_secondary :: proc() -> bool {
	if raylib.IsKeyPressed(.K) || raylib.IsMouseButtonPressed(.RIGHT) {
		return true
	}
	if gamepad_active() && raylib.IsGamepadButtonPressed(GAMEPAD_ID, active_gamepad_mapping.scythe_secondary) {
		return true
	}
	return false
}

input_summon_scythe :: proc() -> bool {
	return raylib.IsKeyPressed(.R)
}

input_summon_fangs :: proc() -> bool {
	return raylib.IsKeyPressed(.F)
}

input_companion_toggle :: proc() -> bool {
	return gamepad_active() && raylib.IsGamepadButtonPressed(GAMEPAD_ID, active_gamepad_mapping.companion_toggle)
}

input_companion_summon :: proc() -> bool {
	return gamepad_active() && raylib.IsGamepadButtonPressed(GAMEPAD_ID, active_gamepad_mapping.companion_summon)
}

// ---------------------------------------------------------------------------
// Menu / UI input
// ---------------------------------------------------------------------------

input_menu_up :: proc() -> bool {
	if raylib.IsKeyPressed(.UP) || raylib.IsKeyPressed(.W) {
		return true
	}
	if gamepad_active() && raylib.IsGamepadButtonPressed(GAMEPAD_ID, .LEFT_FACE_UP) {
		return true
	}
	return false
}

input_menu_down :: proc() -> bool {
	if raylib.IsKeyPressed(.DOWN) || raylib.IsKeyPressed(.S) {
		return true
	}
	if gamepad_active() && raylib.IsGamepadButtonPressed(GAMEPAD_ID, .LEFT_FACE_DOWN) {
		return true
	}
	return false
}

input_menu_left :: proc() -> bool {
	if raylib.IsKeyPressed(.LEFT) || raylib.IsKeyPressed(.A) {
		return true
	}
	if gamepad_active() && raylib.IsGamepadButtonPressed(GAMEPAD_ID, .LEFT_FACE_LEFT) {
		return true
	}
	return false
}

input_menu_right :: proc() -> bool {
	if raylib.IsKeyPressed(.RIGHT) || raylib.IsKeyPressed(.D) {
		return true
	}
	if gamepad_active() && raylib.IsGamepadButtonPressed(GAMEPAD_ID, .LEFT_FACE_RIGHT) {
		return true
	}
	return false
}

input_confirm :: proc() -> bool {
	if raylib.IsKeyPressed(.ENTER) || raylib.IsKeyPressed(.KP_ENTER) {
		return true
	}
	if gamepad_active() && raylib.IsGamepadButtonPressed(GAMEPAD_ID, .RIGHT_FACE_DOWN) {
		return true
	}
	return false
}

input_back :: proc() -> bool {
	if raylib.IsKeyPressed(.ESCAPE) {
		return true
	}
	if gamepad_active() && raylib.IsGamepadButtonPressed(GAMEPAD_ID, .RIGHT_FACE_RIGHT) {
		return true
	}
	return false
}

input_pause :: proc() -> bool {
	if raylib.IsKeyPressed(.ESCAPE) {
		return true
	}
	if gamepad_active() && raylib.IsGamepadButtonPressed(GAMEPAD_ID, .MIDDLE_RIGHT) {
		return true
	}
	return false
}
