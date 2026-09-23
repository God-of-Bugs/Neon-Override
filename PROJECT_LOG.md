# PROJECT LOG — "All new 3d games"

> **PROJECT MANAGEMENT WORKFLOW (ACTIVE)**
>
> **READ RULE:** Before writing or modifying ANY code, the agent MUST read this file
> first to understand the current architecture. Never make assumptions.
>
> **WRITE RULE:** After every successfully implemented feature, bug fix, or project
> structure change, this file MUST be updated to reflect the new state.
>
> Last updated: after the Enemy Wave Spawner System implementation and animation fix session (2025-01).

---

## 1. Project Overview

- **Engine:** Godot 4.7.1 (GL Compatibility renderer, D3D12 on Windows, Jolt Physics)
- **Main scene:** `res://MainWorld.tscn`
- **Genre:** 3D third-person arena survival — red capsule enemies chase and melee
  the player; the player fights back with a melee ray-cast attack.
- **Input actions** (defined in `project.godot`):
  - `ui_left/right/up/down` — WASD / arrows (used for movement)
  - `jump` — Space
  - `attack` — Left mouse button or `F`
  - `ui_cancel` — ESC (toggles mouse capture)

---

## 2. File Inventory

| File | Purpose |
|---|---|
| `res://MainWorld.tscn` | Main level: environment, CSG arena (floor + 4 obstacles), NavigationRegion3D, UIManager, Player, EnemySpawner |
| `res://MainWorld` script: `main_world.gd` | Wires player → HUD (`health_changed` → `update_health`) |
| `res://Player.tscn` | Player scene: Knight.glb model (scale 1.5), capsule collider, CameraPivot → SpringArm3D (3 m) → Camera3D (FOV 75) |
| `res://player.gd` | Player health, movement, mouse-look, melee attack, death |
| `res://Enemy.tscn` | Enemy scene: CharacterBody3D root, Rogue.glb model (scale 0.25), CollisionShape3D (CapsuleShape3D, radius 0.4, height 1.8, Y=0.9), NavigationAgent3D, AnimationPlayer (running/idle/punch), HitSparks (GPUParticles3D), HitSound (AudioStreamPlayer3D) |
| `res://enemy.gd` | Enemy AI: nav-agent chase, attack logic, health, hit feedback, animation control via `find_child("AnimationPlayer")` |
| `res://enemy_spawner.gd` | Timer-based Enemy Wave Spawner: `@export var enemy_scene: PackedScene`, `@export var max_enemies: int = 5`, `@export var spawn_interval: float = 3.0`, spawns enemies at random offsets around the spawner |
| `res://UIManager.tscn` | HUD: HealthBar (ProgressBar, max 100), GameOverPanel (Label + RestartButton), GameOverSound, DamageOverlay (full-screen ColorRect) |
| `res://ui_manager.gd` | HUD logic: health mirror, damage flash tween, game-over reveal, restart |
| `res://nav_region.gd` | **NOT currently attached** to any node — bakes the navmesh from CSG geometry at runtime and saves `res://navmesh.tres` (kept for future use) |
| `res://navmesh.tres` | Saved NavigationMesh covering the arena (vertices at y=0.5, ±24.5 extents) |

---

## 3. Architecture & Exact Mechanics

### Player (`player.gd`, class `Player`)
- **Movement:** `SPEED = 5.0` m/s, relative to facing; WASD/arrows via
  `Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")`.
- **Mouse-look:** whole body rotates on Y (`rotate_y(-event.relative.x * 0.005)`);
  only the CameraPivot pitches on X, clamped to ±1.0 rad. ESC toggles mouse capture.
- **Health:** `MAX_HEALTH = 100`, `var current_health`, `signal health_changed(value: int)`.
- **Jump:** `JUMP_VELOCITY = 4.5` on the `jump` action, only when `is_on_floor()`.
- **Melee attack (`_try_attack`):**
  - Trigger: `attack` action (LMB / F), cooldown `ATTACK_COOLDOWN = 0.5` s
  - Ray origin: `global_position + (0, 1, 0)`; direction: horizontal component of
    camera forward (`-camera.global_transform.basis.z`, Y zeroed, normalized)
  - Ray length `ATTACK_RANGE = 2.5` m, `collision_mask = 4` (enemies only), excludes self RID
  - Damage `ATTACK_DAMAGE = 15`; calls `take_damage()` on whatever the ray hits
- **Damage in (`take_damage`):** subtracts, emits `health_changed`, triggers
  `flash_damage()` on the `ui_manager` group node; at ≤ 0 calls `_die()`.
- **Death:** `is_dead = true` → movement/input frozen, `show_game_over()` on the
  `ui_manager` group node (panel + mouse released).
- **Group:** adds itself to `"player"` group in `_ready()` (enemies find it by group).

### Enemy (`enemy.gd`, class `Enemy`)
- **Chase:** `NavigationAgent3D` retargets the player every physics frame;
  `SPEED = 4.5` m/s (slower than player's 5.0). Moves ONLY via
  `agent.set_velocity()` → `velocity_computed` callback → `move_and_slide()`
  (avoidance enabled, so enemies steer around each other).
- **Attack:** `_process` checks distance < `ATTACK_RANGE = 1.5` m (origin-to-origin),
  cooldown `attack_cooldown = 1.0` s, damage `attack_damage = 10`,
  calls `player.take_damage(10)`. Cooldown ticks even out of range.
- **Health:** `MAX_HEALTH = 30` → dies to 2 player hits (15 × 2).
- **On damage:** hit sparks particles burst, hit sound plays, "punch" animation.
- **Animations (procedural, in Enemy.tscn):** `idle` (slow bob, loop),
  `running` (fast bob, loop), `punch` (forward lunge of the body mesh, no loop).
- **Collision:** layer 4 (so the player attack ray with mask 4 hits only enemies),
  mask 1 (floor).
- **Group:** `"enemies"`.

### Enemy Wave Spawner System (`enemy_spawner.gd`, class `Node3D`)
- **Root node:** `EnemySpawner` (Node3D) in `res://MainWorld.tscn`, positioned at (−22.5, 1.2, 7.9).
- **Export variables:** `@export var enemy_scene: PackedScene`, `@export var max_enemies: int = 5`, `@export var spawn_interval: float = 3.0`.
- **Timer:** `Timer` child node with `autostart = true`, `wait_time = spawn_interval`. On `timeout`, calls `_spawn_enemy()`.
- **Spawn logic:** `_spawn_enemy()` instantiates `enemy_scene`, places it at `global_position + Vector3(randf_range(-3, 3), 0, randf_range(-3, 3))`, then adds it to `get_tree().current_scene`.
- **Wave tracking:** `enemies_spawned` counter increments each spawn; stops spawning at `max_enemies`. Prints `"Saare enemies aa chuke hain! Wave Complete."` when done.
- **Safety:** Guards against null `enemy_scene` with a print error message.
- **Scene references:** `res://Enemy.tscn` is assigned to `enemy_scene` via the Inspector panel in `res://MainWorld.tscn`.

### UI (`ui_manager.gd`, class `UIManager`, group `"ui_manager"`)
- `update_health(value)` → ProgressBar (max 100, green fill).
- `flash_damage()` → DamageOverlay flashes `Color(0.5, 0, 0, 0.4)` and tweens to alpha 0 over 0.2 s.
- `show_game_over()` → GameOverPanel visible, GameOverSound plays, mouse released.
- Restart button → `get_tree().reload_current_scene()`.
- `MainWorld._ready()` connects `player.health_changed → ui_manager.update_health`
  and sets the bar once at start.

### World (`MainWorld.tscn`)
- CSG floor 50×50×1 (top at y=0, `use_collision`), 4 CSG box obstacles with collision.
- `navmesh.tres` loaded on the NavigationRegion3D; `nav_region.gd` exists but is
  currently NOT attached to the region node.
- Enemies spawn at (8, 0.2, 8), (−6, 0.2, −12), (12, 0.2, −6); player at origin facing −Z.

---

## 4. Bug Fixes Applied (Verified)

1. **Camera FOV 179° → 75°** (`Player.tscn`). At 179° everything at gameplay
   distances rendered invisibly tiny; the world looked empty.
2. **DamageOverlay ate all mouse events** (`ui_manager.gd`). The full-screen
   ColorRect's default `mouse_filter = STOP` consumed mouse motion before the
   player's `_unhandled_input`, silently breaking mouse-look. Fixed with
   `damage_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE` in `_ready()`.
3. **Enemy2 spawned inside Obstacle1's footprint** (old spawn (−8, −8) vs obstacle
   x∈[−12,−8], z∈[−10,−6]) so the navmesh projection failed and it never moved.
   Moved to (−6, 0.2, −12).
4. **Stale scripts**: an earlier attempt to rewrite `player.gd`/`main_world.gd` was
   rejected ("file already exists") leaving the old versions on disk — enemies
   couldn't find the player (no `"player"` group, no `take_damage`). Rewritten via
   targeted edits; root cause of the original "enemies stand still" symptom.
5. **Enemy speed comment** corrected (player is 5.0, not 6.0).
6. **Game-over Restart button non-functional** (`ui_manager.gd`):
   The `restart_button.pressed` signal was never connected (no `[connection]`
   in `UIManager.tscn`, no `.connect()` in `_ready()`). Fixed by adding
   `@onready var restart_button: Button = $GameOverPanel/RestartButton` and
   `restart_button.pressed.connect(_on_restart_button_pressed)` in `_ready()`.
   Also set `UIManager.process_mode = Node.PROCESS_MODE_ALWAYS`, and added
   `get_tree().paused = true` in `show_game_over()` and
   `get_tree().paused = false` + `reload_current_scene()` in
   `_on_restart_button_pressed()` so the game pauses behind the panel and
   the restart correctly reloads the scene.
7. **Camera in front of player** (`Player.tscn`): SpringArm3D/Camera3D
   transforms placed the camera directly in front of the knight. Replaced
   with identity basis + `(0.6, 0.5, 2.8)` local position so the camera
   sits BEHIND the player (~2.8 m offset) looking toward −Z — classic third-person.
8. **Player model does not face movement** (`player.gd`): added
    `@onready var model: Node3D = $Model` and, in `_physics_process`, a
    `lerp_angle` that smoothly rotates `$Model` to face the movement direction.
    Also fixed a Z-inversion bug: `Vector3(input_dir.x, 0, input_dir.y)`
    pushed the player backward; corrected to `Vector3(input_dir.x, 0,
    -input_dir.y)` so `W` moves toward −Z (forward). `MODEL_FORWARD_OFFSET`
    set to `π` so the model shows its back to the camera while walking forward.
9. **EnemySpawner invisible and unselectable in 3D viewport** (`res://MainWorld.tscn`): EnemySpawner was a bare `Node3D` with no children — no visual representation to click or see in the 3D viewport. Fixed by adding a `MeshInstance3D` child (`SpawnGizmo`) with a `BoxMesh` (0.6×0.6×0.6) and a bright orange-red `StandardMaterial3D` (emissive glow) as a child. Now clearly visible and selectable.
10. **Enemy.tscn deleted — recreated from scratch** (`res://Enemy.tscn`): The `Enemy.tscn` scene file was accidentally deleted, and the enemy was incorrectly placed inline inside `MainWorld.tscn`. Recreated `res://Enemy.tscn` with proper structure: `CharacterBody3D` root (script: `enemy.gd`), `CollisionShape3D` with `CapsuleShape3D` (radius 0.4, height 1.8, Y=0.9), `NavigationAgent3D`, `HitSparks` (`GPUParticles3D`), `HitSound` (`AudioStreamPlayer3D`), `AnimationPlayer`, and `Rogue.glb` model instance (scale 0.25). Linked via `PackedScene` ext-resource in `MainWorld.tscn`'s `EnemySpawner.enemy_scene` export.
11. **AnimationPlayer null / "Animation not found" crash** (`enemy.gd`, `res://Enemy.tscn`): The `Rogue.glb` model (KayKit Adventurers) contains a `Skeleton3D` but **no `AnimationPlayer` node** — animations are not embedded as AnimationPlayer-compatible clips. `enemy.gd` calls `anim_player.play("running")`, `anim_player.play("idle")`, `anim_player.play("punch")` which crashed with `Animation not found: running`. Fixed by adding three `Animation` sub-resources (`Animation_running`, `Animation_idle`, `Animation_punch`) to the `AnimationPlayer` in `Enemy.tscn`, each with `name` matching the strings used in `enemy.gd`. The `find_child("AnimationPlayer", true, false)` lookup correctly finds the node.
12. **Stale GLB ext-resources removed from MainWorld.tscn**: After extracting the enemy into its own `.tscn`, the inline `enemy.gd` and `Rogue.glb` ext-resource declarations and the unused `CapsuleShape3D_4encw` sub-resource were removed from `MainWorld.tscn` to prevent duplicate resource conflicts.

---

## 5. Verification Status (live in-game runs)

- ✅ Enemies acquire the player via the `"player"` group, path-find across the
  arena, reach point-blank melee range (avoidance callbacks firing ~60/s).
- ✅ Enemy attacks drain the player's health (10 per hit, per enemy).
- ✅ Health bar mirrors health; red damage flash tween works.
- ✅ At 0 HP: GAME OVER panel + RESTART button appear; RESTART reloads the scene.
- ✅ Player attack: verified via logged swing/hit data — hits register
  (`hit=Enemy2` twice → 30/30 HP → killed; aimed swing after mouse-turn hit
  `Enemy3`). Kill removes the enemy from the tree.
- ✅ Mouse-look verified rotating the player (post DamageOverlay fix).
- ✅ Restart button works (panel appears on death, RESTART unpauses
  and reloads the scene — fresh enemies, second death logged).
- ✅ Camera is now BEHIND the player (knight's back visible while
  walking forward; enemies visible ahead of the knight).
- ✅ Player model rotates to face the movement direction (back of
  knight visible while walking); Z-inversion in the movement vector
  corrected so W pushes toward −Z.
- ✅ Player melee attack lands (console logged 15-damage hits on
  enemy capsules ahead of the player).
- ✅ No runtime errors in clean runs; all temporary debug logging/files removed
  (`_enemy_debug.log`, `_attack_debug.log` deleted).
- ✅ **Enemy Wave Spawner System works**: Timer triggers enemy spawns at
   random offsets around the EnemySpawner; `enemy_scene` correctly references
   `res://Enemy.tscn`; `max_enemies` cap and `spawn_interval` timer both function.
- ✅ **AnimationPlayer animations resolve correctly**: `anim_player.play("running")`,
   `anim_player.play("idle")`, and `anim_player.play("punch")` no longer crash
   — all three `Animation` sub-resources exist in `Enemy.tscn` with exact string
   matches to `enemy.gd`.
- ✅ **3D viewport gizmo visible**: `SpawnGizmo` (orange box mesh) makes
   `EnemySpawner` clearly selectable and positionable in the 3D viewport.
- ✅ **Scene structure clean**: `MainWorld.tscn` no longer contains stale
   inline enemy nodes; `res://Enemy.tscn` is a proper PackedScene reference.

Known gaps / not yet built:
- `HitSound` and `GameOverSound` nodes are wired but have **no audio streams**.
- No score/kill counter, no win condition beyond the `max_enemies` cap.
- `nav_region.gd` not attached (navmesh relies on the saved `navmesh.tres`).
- Attack hit-sparks (GPUParticles3D burst) are subtle and easy to
  miss at capture time; the material flash confirms hits land.
- Enemy animations are currently empty clips (no keyframe data);
  animations play but show no visual movement. Future work: replace
  with rigged animation data or procedural animation tracks.
