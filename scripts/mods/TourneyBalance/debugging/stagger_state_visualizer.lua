local mod = get_mod("TourneyBalance")

--[[

	Stagger State Visualizer

	Outlines enemies based on the sum of whichever stagger counts are enabled
	(real stagger count from blackboard.stagger, Mainstay's marked stagger count
	from the target's dummy_stagger buff):
		0        -> no outline
		1        -> green
		2        -> yellow
		above 2  -> red

]]

OutlineSettings.colors.tb_stagger_green = {
	pulsate = false,
	pulse_multiplier = 50,
	color = { 255, 0, 255, 0 }, -- alpha, r, g, b (green)
}
OutlineSettings.colors.tb_stagger_yellow = {
	pulsate = false,
	pulse_multiplier = 50,
	color = { 255, 255, 255, 0 }, -- alpha, r, g, b (yellow)
}
OutlineSettings.colors.tb_stagger_red = {
	pulsate = false,
	pulse_multiplier = 50,
	color = { 255, 255, 0, 0 }, -- alpha, r, g, b (red)
}
OutlineSettings.templates.tb_stagger_1 = {
	method = "ai_alive",
	priority = 50,
	outline_color = OutlineSettings.colors.tb_stagger_green,
	flag = OutlineSettings.flags.non_wall_occluded,
}
OutlineSettings.templates.tb_stagger_2 = {
	method = "ai_alive",
	priority = 50,
	outline_color = OutlineSettings.colors.tb_stagger_yellow,
	flag = OutlineSettings.flags.non_wall_occluded,
}
OutlineSettings.templates.tb_stagger_3 = {
	method = "ai_alive",
	priority = 50,
	outline_color = OutlineSettings.colors.tb_stagger_red,
	flag = OutlineSettings.flags.non_wall_occluded,
}
local STAGGER_OUTLINE_TEMPLATES = {
	[1] = OutlineSettings.templates.tb_stagger_1,
	[2] = OutlineSettings.templates.tb_stagger_2,
	[3] = OutlineSettings.templates.tb_stagger_3,
}

local function get_stagger_state(total)
	if not total or total <= 0 then
		return 0
	elseif total == 1 then
		return 1
	elseif total == 2 then
		return 2
	else
		return 3
	end
end

local function get_mainstay_count(unit)
	local target_buff_extension = ScriptUnit.has_extension(unit, "buff_system")

	if not target_buff_extension then
		return 0
	end

	return target_buff_extension:apply_buffs_to_value(0, "dummy_stagger")
end

-- unit -> { outline_id = ..., state = ... }
local outlined_units = {}

local function clear_outline(unit)
	local data = outlined_units[unit]

	if not data then
		return
	end

	if ALIVE[unit] then
		local outline_extension = ScriptUnit.has_extension(unit, "outline_system")

		if outline_extension then
			outline_extension:remove_outline(data.outline_id)
		end
	end

	outlined_units[unit] = nil
end

local function clear_all_outlines()
	for unit, _ in pairs(outlined_units) do
		clear_outline(unit)
	end
end

local function apply_stagger_outline(unit, state)
	local outline_extension = ScriptUnit.has_extension(unit, "outline_system")

	if not outline_extension then
		return
	end

	local data = outlined_units[unit]

	if not data then
		local outline_id = outline_extension:add_outline(STAGGER_OUTLINE_TEMPLATES[state])

		outlined_units[unit] = {
			outline_id = outline_id,
			state = state,
		}
	elseif data.state ~= state then
		outline_extension:update_outline(table.clone(STAGGER_OUTLINE_TEMPLATES[state]), data.outline_id)

		data.state = state
	end
end

local UPDATE_INTERVAL = 0.15
local next_update_t = 0

-- Note: this claims mod.update directly, which is normally owned by
-- performance_logging.lua (mod:hook_safe(IngameHud, "update", ...) did not fire
-- reliably here) - performance logging's own update loop no longer runs as a result.
mod.update = function (dt)
	if not mod:get("stagger_state_visualizer") then
		if next(outlined_units) then
			clear_all_outlines()
		end

		return
	end

	if not Managers.state or not Managers.state.game_mode then
		return
	end

	if not BLACKBOARDS then
		return
	end

	local t = Managers.time:time("game")

	if t < next_update_t then
		return
	end

	next_update_t = t + UPDATE_INTERVAL

	for unit, _ in pairs(outlined_units) do
		if not ALIVE[unit] or not BLACKBOARDS[unit] then
			clear_outline(unit)
		end
	end

	local include_real = mod:get("stagger_state_visualizer_include_real")
	local include_mainstay = mod:get("stagger_state_visualizer_include_mainstay")

	for unit, blackboard in pairs(BLACKBOARDS) do
		if ALIVE[unit] then
			local total = 0

			if include_real then
				total = total + (blackboard.stagger or 0)
			end

			if include_mainstay then
				total = total + get_mainstay_count(unit)
			end

			local state = get_stagger_state(total)

			if state == 0 then
				clear_outline(unit)
			else
				apply_stagger_outline(unit, state)
			end
		end
	end
end
