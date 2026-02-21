# Reshadeck Flow Specification

This document defines the strict, state-machine-like flow for the Reshadeck backend. It serves as actionable instructions to build a robust, bug-free, and deterministic event-handling system.

## Core Concepts

1. **State Ownership**: The backend daemon is the *sole owner* of state. The UI simply reflects what the backend provides and dispatches events to the backend. The UI should *never* attempt to manage state locally.
2. **Crash Circuit Breaker**: The `master_switch` is the ultimate safeguard. If `master_switch = false`, NO shaders are loaded, ever.
3. **Singleton Crash Monitor**: There is exactly ONE active background crash detection task (`asyncio.Task`) at any given time. If a new event requires crash monitoring, the existing task MUST be cancelled before starting a new one.

---

## 1. State Variables (Backend Memory)
* `master_switch` (boolean)
* `active_shader` (string or "None")
* `shader_parameters` (dict)
* `crash_detected` (boolean)
* `per_game_mode` (boolean)
* `current_appid` (string)

---

## 2. Event Handlers

### Event A: `on_plugin_load()`
**Triggered by:** Decky Loader starting the plugin.
1. Load config from persistent storage into memory.
2. *Startup Canary Check*: If `master_switch` is `true` AND `active_shader != "None"`:
   * Check for `gamescope` coredumps generated in the last 5 minutes.
   * If found: 
     * Set `master_switch = false`.
     * Set `crash_detected = true`.
     * Save config to disk.
3. If `master_switch` is `true` AND `active_shader != "None"`:
   * Execute `apply_shader(active_shader, shader_parameters)`.

### Event B: `on_master_switch_changed(is_enabled)`
**Triggered by:** User toggling the Master Switch in the UI.
1. Cancel any active crash detection tasks.
2. Set `crash_detected = false`.
3. Set `master_switch = is_enabled`.
4. If `is_enabled == false`:
   * Execute `apply_shader("None")`.
5. If `is_enabled == true` AND `active_shader != "None"`:
   * Trigger the `Crash Detection Subroutine`.
   * Execute `apply_shader(active_shader, shader_parameters)`.
6. Save config to disk.

### Event C: `on_active_app_changed(appid)`
**Triggered by:** User opening a game, switching games, or returning to SteamOS.
1. Cancel any pending debounce tasks (from rapid parameter changes).
2. Set `current_appid = appid`.
3. If `master_switch == false`:
   * Halt execution (do nothing).
4. Check persistent storage for a profile matching `appid`.
5. If a profile exists for this `appid`:
   * Load the per-game profile into memory (`active_shader`, `shader_parameters`).
6. Else:
   * Load the global profile into memory (`active_shader`, `shader_parameters`).
7. Execute `apply_shader(active_shader, shader_parameters)`.

### Event D: `on_ui_opened()`
**Triggered by:** User opening the Reshadeck Decky menu.
1. If a profile exists for the `current_appid`:
   * Load the per-game profile into memory.
2. Else:
   * Load the global profile into memory.
3. *Note: As long as the `master_switch` allows, re-apply the shader to ensure the UI and backend match. This forcefully syncs visual state with backend state.*
4. Execute `apply_shader(active_shader, shader_parameters)`.
5. Send current memory state down to the UI.

### Event E: `on_shader_changed(new_shader)`
**Triggered by:** User selecting a new underlying shader package from the UI dropdown.
1. Cancel any active crash detection tasks.
2. Update `active_shader = new_shader` in memory.
3. Save config to disk immediately.
4. If `master_switch == false`:
   * Halt execution (do nothing).
5. Trigger the `Crash Detection Subroutine`.
6. Execute `apply_shader(active_shader, shader_parameters)`.

### Event F: `on_parameters_changed(new_parameters)`
**Triggered by:** User dragging a slider or toggling a boolean in the UI.
1. Update `shader_parameters` in memory immediately.
2. Cancel any pending `apply_debounced` task.
3. Schedule `apply_debounced` task to run in **1.0 seconds**.

#### Sub-task: `apply_debounced()`
1. Cancel any active crash detection tasks.
2. Save config to disk immediately.
3. If `master_switch == false`:
   * Halt execution (do nothing).
4. Trigger the `Crash Detection Subroutine`.
5. Execute `apply_shader(active_shader, shader_parameters, parameters_only=true)`. *(Note: Pass a flag `parameters_only=true` if your shell script can optimize purely parameter-based re-applications without deleting/rebuilding base files)*.

---

## 3. Worker Subroutines

### Subroutine: `Crash Detection Subroutine`
**Nature:** A managed `asyncio.Task` that lives for precisely 60 seconds (1 minute).
1. Store current timestamp as `start_time`.
2. Loop indefinitely until 60 seconds have elapsed from `start_time`:
   * Sleep for 2.0 seconds.
   * Look in `/var/lib/systemd/coredump/` for `core.gamescope-wl.*.zst`.
   * If a dump exists AND its modified timestamp is `> start_time`:
     * Set `master_switch = false`.
     * Set `crash_detected = true`.
     * Save config to disk immediately.
     * Execute `apply_shader("None")`.
     * Exit subroutine (`return`).
3. Exit cleanly after 60 seconds.

---

## Agent Refactoring Checklist & Implementation Advice
When an agent reviews the existing Python code (`main.py`) to align it with this flow, they should:
* **Factor out `apply_shader`:** The `apply_shader` method should be a pure, dumb function that takes `target_shader` and `params` and shells out to `set_shader.sh`. It should NOT contain logical checks for whether it *should* run; the Event Handlers (A through F) determine *if* it should run.
* **Consolidate State Transitions:** Event handlers should be the *only* places where `save_config()` is invoked. Do not litter `save_config()` deep within utility methods.
* **Task Management:** Create explicit class-level variables (e.g., `Plugin._active_crash_monitor_task` and `Plugin._debounce_task`) to securely hold references to running tasks, allowing you to unambiguously call `.cancel()` on them.
* **Debounce Implementation:** Python's `asyncio.sleep()` is perfect for debouncing. Simply cancel the existing task and spawn a new one that starts with `await asyncio.sleep(1.0)`.
