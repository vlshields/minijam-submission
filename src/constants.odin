package game

SCREEN_WIDTH  :: 640
SCREEN_HEIGHT :: 360
TILE_SIZE     :: 16
TARGET_FPS    :: 60

PLAYER_SPEED   :: 120.0
GRAVITY        :: 500.0
JUMP_VELOCITY  :: -220.0
MAX_FALL_SPEED :: 400.0
MAX_JUMPS      :: 2

PLAYER_HITBOX_W :: 8
PLAYER_HITBOX_H :: 14

SPRITE_SRC_SIZE :: 16
SPRITE_DST_SIZE :: 16

ANIM_FRAME_TIME :: 0.172

DASH_SPEED         :: 800.0
DASH_DURATION      :: 0.15
DASH_COOLDOWN      :: 0.5
MAX_DASH_PARTICLES :: 64

// Downward dash
DASH_DOWN_SPEED    :: 900.0
DASH_IMPACT_SIZE   :: 32
DASH_IMPACT_DAMAGE :: 32.0
DASH_IMPACT_FPS    :: 18.0

COMPANION_SRC_SIZE   :: 32
COMPANION_OFFSET_X   :: 14.0
COMPANION_OFFSET_Y   :: 0.0
COMPANION_LERP_SPEED :: 10.0

COMPANION_ATTACK_COOLDOWN :: .3
COMPANION_ONESHOT_FPS     :: 12.0
COMPANION_DAMAGE          :: 41.0

// Blood scythe
SCYTHE_SRC_SIZE        :: 32
SCYTHE_OFFSET_X        :: 14.0
SCYTHE_OFFSET_Y        :: 0.0
SCYTHE_LERP_SPEED      :: 10.0
SCYTHE_ATTACK_COOLDOWN :: 0.0
SCYTHE_ONESHOT_FPS     :: 18.0
SCYTHE_DAMAGE          :: 31.0

// Player combat
PLAYER_MAX_HP :: 120.0

// Enemy – fireball
ENEMY_SRC_SIZE         :: 16
ENEMY_HITBOX_W         :: 12
ENEMY_HITBOX_H         :: 12
ENEMY_HP               :: 21.0
ENEMY_DAMAGE           :: 18.0
ENEMY_SPEED            :: 130.0
ENEMY_ATTACK_COOLDOWN  :: 4.0
ENEMY_ANIM_FPS         :: 12.0
MAX_ENEMIES            :: 32

// Enemy – flamewarden
FW_SRC_SIZE            :: 16
FW_HITBOX_W            :: 12
FW_HITBOX_H            :: 14
FW_HP                  :: 35.0
FW_FLAME_DAMAGE        :: 21.0
FW_PATROL_SPEED        :: 40.0
FW_ATTACK_COOLDOWN     :: 2.5
FW_ANIM_FPS            :: 10.0
FW_FLAME_LOOP_DURATION :: 1.0
FW_FLAME_TRACK_SPEED   :: 80.0 // pixels/sec flame chases player
FW_FLAME_SRC_W         :: 16
FW_FLAME_SRC_H         :: 32
MAX_FLAMEWARDENS       :: 16

// Quick attack
QUICK_ATTACK_SRC_SIZE     :: 32
QUICK_ATTACK_FPS          :: 12.0
QUICK_ATTACK_DAMAGE       :: 18.0
QUICK_ATTACK_COOLDOWN     :: 0.0
QUICK_ATTACK_CHAIN_WINDOW :: 3
QUICK_ATTACK_HIT_FRAME    :: 3

// Enemy – devil
DEVIL_SRC_SIZE         :: 16
DEVIL_DRAW_SIZE        :: 12
DEVIL_HITBOX_W         :: 12
DEVIL_HITBOX_H         :: 14
DEVIL_HP               :: 30.0
DEVIL_DAMAGE           :: 13.0
DEVIL_SPEED            :: 60.0
DEVIL_ATTACK_RANGE     :: 32.0
DEVIL_ATTACK_COOLDOWN  :: 2.0
DEVIL_ANIM_FPS         :: 10.0
DEVIL_BOLT_SRC_SIZE        :: 32
DEVIL_RANGED_ATTACK_RANGE  :: 240.0
DEVIL_RANGED_BOLT_SPEED    :: 400.0
MAX_DEVILS                 :: 16

// Moloch (Boss)
ED_SRC_SIZE              :: 16
ED_HITBOX_W              :: 12
ED_HITBOX_H              :: 14
ED_HP                    :: 800.0
ED_SPEED                 :: 85.0
ED_ANIM_FPS              :: 10.0
ED_BREATH_RANGE          :: 28.0
ED_BREATH_DAMAGE         :: 22.0
ED_BREATH_COOLDOWN       :: 1.5
ED_BREATH_LOOP_DURATION  :: 0.8
ED_BREATH_SRC_SIZE       :: 32
ED_METEOR_DAMAGE         :: 35.0
ED_METEOR_INTERVAL       :: 1.5
ED_METEOR_SRC_SIZE       :: 32
ED_METEOR_FALL_SPEED     :: 180.0
ED_METEOR_SPAWN_HEIGHT   :: 300.0
ED_MAGMA_DAMAGE          :: 18.0
ED_MAGMA_INTERVAL        :: 5.0
ED_MAGMA_SRC_SIZE        :: 32
ED_MAGMA_LOOP_DURATION   :: 1.5
ED_TELEPORT_THRESHOLD    :: 100.0
ED_TELEPORT_DURATION     :: 0.5
ED_DAMAGE_WINDOW         :: 1.0
ED_MAX_METEORS           :: 4
ED_MAX_MAGMA             :: 3
ED_MAX_TELEPORT_POINTS   :: 16
ED_BP_KILL               :: 50

// Damage flash
DAMAGE_FLASH_DURATION  :: 0.15

// Screenshake (combat)
SCREENSHAKE_DURATION  :: 0.1
SCREENSHAKE_MAGNITUDE :: 1.5

// Audio
FOOTSTEP_INTERVAL :: 0.3

// Blood points
BP_STARTING         :: 50
BP_DRAIN_INTERVAL   :: 2.0
BP_FLAMEBALL_KILL   :: 1
BP_DEVIL_KILL       :: 3
BP_FLAMEWARDEN_KILL :: 5
BP_MIN_CARRY        :: 25

// Rounds (scripted)
ROUND_COUNT :: 5
ROUND_DURATIONS : [ROUND_COUNT]f32 : {17.0, 30.0, 50.0, 60.0, 0.0}
ROUND_MAPS : [ROUND_COUNT]string : {
	"assets/maps/main_area_first.map",
	"assets/maps/level2.map",
	"assets/maps/level3.map",
	"assets/maps/level4.map",
	"assets/maps/level_final.map",
}

// Parallax background
PARALLAX_LAYER_COUNT :: 3
// Speeds indexed by spritesheet row: 0=sky, 1=buildings, 2=stars
PARALLAX_SPEEDS : [PARALLAX_LAYER_COUNT]f32 : {0.02, 0.2, 0.08}
// Back-to-front draw order: sky, stars, buildings
PARALLAX_DRAW_ORDER : [PARALLAX_LAYER_COUNT]int : {0, 2, 1}

