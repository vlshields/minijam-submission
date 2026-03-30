package game

import raylib "vendor:raylib"

// ---------------------------------------------------------------------------
// Gamepad constants
// ---------------------------------------------------------------------------

GAMEPAD_ID     :: 0
STICK_DEADZONE :: f32(0.25)

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
	if gamepad_active() && raylib.IsGamepadButtonPressed(GAMEPAD_ID, .RIGHT_FACE_DOWN) {
		return true
	}
	return false
}

input_dash :: proc() -> bool {
	if raylib.IsKeyPressed(.SPACE) {
		return true
	}
	if gamepad_active() && raylib.IsGamepadButtonPressed(GAMEPAD_ID, .RIGHT_FACE_RIGHT) {
		return true
	}
	return false
}

input_attack :: proc() -> bool {
	if raylib.IsKeyPressed(.J) || raylib.IsMouseButtonPressed(.LEFT) {
		return true
	}
	if gamepad_active() && raylib.IsGamepadButtonPressed(GAMEPAD_ID, .RIGHT_FACE_LEFT) {
		return true
	}
	return false
}

input_scythe_secondary :: proc() -> bool {
	if raylib.IsKeyPressed(.K) || raylib.IsMouseButtonPressed(.RIGHT) {
		return true
	}
	if gamepad_active() && raylib.IsGamepadButtonPressed(GAMEPAD_ID, .RIGHT_FACE_UP) {
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
	return gamepad_active() && raylib.IsGamepadButtonPressed(GAMEPAD_ID, .RIGHT_TRIGGER_1)
}

input_companion_summon :: proc() -> bool {
	return gamepad_active() && raylib.IsGamepadButtonPressed(GAMEPAD_ID, .LEFT_TRIGGER_2)
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
