# PROJECT LOG — "All new 3d games"

> **PROJECT MANAGEMENT WORKFLOW (ACTIVE)**
>
> **READ RULE:** Before writing or modifying ANY code, the agent MUST read this file
> first to understand the current architecture. Never make assumptions.
>
> **WRITE RULE:** After every successfully implemented feature, bug fix, or project
> structure change, this file MUST be updated to reflect the new state.
>
> Last updated: after the third-person / UI restart / model-rotation fix session.

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
| `res://MainWorld.tscn` | Main level: environment, CSG arena (floor + 4 obstacles), NavigationRegion3D, UIManager, Player, Enemy1-3 |
| `res://MainWorld` script: `main_world.gd` | Wires player to HUD (`health_changed` to `update_health`) |
| `res://Player.tscn` | Player scene: Knight.glb model (scale 1.5), capsule collider, CameraPivot to SpringArm3D (3 m) to Camera3D (FOV 75) |
| `res://player.gd` | Player health, movement, mouse-look, melee attack, death, model rotation |
| `res://Enemy.tscn` | Enemy scene: red capsule body, NavigationAgent3D (avoidance ON), AnimationPlayer (idle/running/punch), HitSparks (GPUParticles3D), HitSound (AudioStreamPlayer3D), collision_layer=4 |
| `res://enemy.gd` | Enemy AI: nav-agent chase, attack logic, health, hit feedback |
| `res://UIManager.tscn` | HUD: HealthBar (ProgressBar, max 100), GameOverPanel (Label + RestartButton), GameOverSound, DamageOverlay (full-screen ColorRect) |
| `res://ui_manager.gd` | HUD logic: health mirror, damage flash tween, game-over reveal, restart |
| `res://nav_region.gd` | **NOT currently attached** to any node — bakes the navmesh from CSG geometry at runtime and saves `res://navmesh.tres` (kept for future use) |
| `res://navmesh.tres` | Saved NavigationMesh covering the arena (vertices at y=0.5, plusmn24.5 extents) |

---

## 3. Architecture and Exact Mechanics

### Player (`player.gd`, class `Player`)
- **Movement:** `SPEED = 5.0` m/s, relative to facing; WASD/arrows via
  `Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")`.
  **Fixed Z-inversion:** `Vector3(input_dir.x, 0, -input_dir.y)` so `W`
  pushes toward -Z (forward).
- **Mouse-look:** whole body rotates on Y (`rotate_y(-event.relative.x * 0.005)`);
  only the CameraPivot pitches on X, clamped to plusmn1.0 rad. ESC toggles mouse capture.
- **Health:** `MAX_HEALTH = 100`, `var current_health`, `signal health_changed(value: int)`.
- **Jump:** `JUMP_VELOCITY = 4.5` on the `jump` action, only when `is_on_floor()`.
- **Melee attack (`_try_attack`):**
  - Trigger: `attack` action (LMB / F), cooldown `ATTACK_COOLDOWN = 0.5` s
  - Ray origin: `global_position + (0, 1, 0)`; direction: horizontal component of
    camera forward (`-camera.global_transform.basis.z`, Y zeroed, normalized)
  - Ray length `ATTACK_RANGE = 2.5` m, `collision_mask = 4` (enemies only), excludes self RID
  - Damage `ATTACK_DAMAGE = 15`; calls `take_damage()` on whatever the ray hits
- **Damage in (`take_damage`):** subtracts, emits `health_changed`, triggers
  `flash_damage()` on the `ui_manager` group node; at 0 HP calls `_die()`.
- **Death:** `is_dead = true` to movement/input frozen, `show_game_over()` on the
  `ui_manager` group node (panel plus mouse released).
- **Group:** adds itself to `"player"` group in `_ready()` (enemies find it by group).
- **Model rotation:** `@onready var model: Node3D = $Model`; in `_physics_process`
  a `lerp_angle` smoothly rotates `$Model` to face the movement direction.
  `MODEL_FORWARD_OFFSET = PI` so the model shows its back to the behind-the-camera
  view while walking forward (classic third-person).

### Enemy (`enemy.gd`, class `Enemy`)
- **Chase:** `NavigationAgent3D` retargets the player every physics frame;
  `SPEED = 4.5` m/s (slower than player's 5.0). Moves ONLY via
  `agent.set_velocity()` to `velocity_computed` callback to `move_and_slide()`
  (avoidance enabled, so enemies steer around each other).
- **Attack:** `_process` checks distance lt `ATTACK_RANGE = 1.5` m (origin-to-origin),
  cooldown `attack_cooldown = 1.0` s, damage `attack_damage = 10`,
  calls `player.take_damage(10)`. Cooldown ticks even out of range.
- **Health:** `MAX_HEALTH = 30` to dies to 2 player hits (15 times 2).
- **On damage:** hit sparks particles burst, hit sound plays, "punch" animation.
- **Animations (procedural, in Enemy.tscn):** `idle` (slow bob, loop),
  `running` (fast bob, loop), `punch` (forward lunge of the body mesh, no loop).
- **Collision:** layer 4 (so the player attack ray with mask 4 hits only enemies),
  mask 1 (floor).
- **Group:** `"enemies"`.

### UI (`ui_manager.gd`, class `UIManager`, group `"ui_manager"`)
- `update_health(value)` to ProgressBar (max 100, green fill).
- `flash_damage()` to DamageOverlay flashes `Color(0.5, 0, 0, 0.4)` and tweens to alpha 0 over 0.2 s.
- `show_game_over()` to GameOverPanel visible, GameOverSound plays, mouse released,
  `get_tree().paused = true`.
- Restart button to `_on_restart_button_pressed` unpauses (`get_tree().paused = false`)
  and reloads the scene (`get_tree().reload_current_scene()`).
- `restart_button.pressed` signal connected in `_ready()`; `process_mode = Node.PROCESS_MODE_ALWAYS`
  so the panel and button keep processing while the tree is paused.
- `damage_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE` and
  `health_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE` in `_ready()`.
- `MainWorld._ready()` connects `player.health_changed` to `ui_manager.update_health`
  and sets the bar once at start.

### World (`MainWorld.tscn`)
- CSG floor 50x50x1 (top at y=0, `use_collision`), 4 CSG box obstacles with collision.
- `navmesh.tres` loaded on the NavigationRegion3D; `nav_region.gd` exists but is
  currently NOT attached to the region node.
- Enemies spawn at (8, 0.2, 8), (-6, 0.2, -12), (12, 0.2, -6); player at origin facing -Z.

---

## 4. Bug Fixes Applied (Verified)

1. **Camera FOV 179 to 75** (`Player.tscn`). At 179 everything at gameplay
   distances rendered invisibly tiny; the world looked empty.
2. **DamageOverlay ate all mouse events** (`ui_manager.gd`). The full-screen
   ColorRect's default `mouse_filter = STOP` consumed mouse motion before the
   player's `_unhandled_input`, silently breaking mouse-look. Fixed with
   `damage_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE` in `_ready()`.
3. **Enemy2 spawned inside Obstacle1's footprint** (old spawn (-8, -8) vs obstacle
   x in [-12,-8], z in [-10,-6]) so the navmesh projection failed and it never moved.
   Moved to (-6, 0.2, -12).
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
   `get_tree().paused = false` plus `reload_current_scene()` in
   `_on_restart_button_pressed()` so the game pauses behind the panel and
   the restart correctly reloads the scene.
7. 
