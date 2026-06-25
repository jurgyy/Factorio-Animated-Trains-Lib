local ceil = math.ceil
local floor = math.floor
local abs = math.abs
local max = math.max
local sqrt = math.sqrt

local rotationframes = 128

---@alias unit_number integer
---@alias surface_index integer

---@class TrainRecord
---@field frame integer
---@field frame_progress number         -- fractional progress within current frame [0,1)
---@field ticks_until_update integer?   -- how many ticks can be skipped before the frame might change
---@field animations LuaRenderObject[]? Array of all possible animation sheets the locomotive can use
---@field active_sheet integer? Currently active sheet index
---@field prev_direction integer? Previously used direction index
---@field animation_speed_multiplier number? Multiplier for animation speed based on locomotive speed
---@field config AnimatedTrainsConfig   -- cached config for this locomotive
---@field sheets_numbers table                  -- cached sheet number for this locomotive
---@field sheets_offsets table                  -- cached sheet offset for this locomotive
---@field frames_per_rotation integer
---@field frame_factor number         -- frames_per_rotation / four_pi_squared

---@class Frustum
---@field x number x position of the player
---@field y number y position of the player
---@field max_dist number Maximum distance the screen can reach (diagonal)
---@field max_dist_sq number Precomputed square of max_dist. Can be more efficient to use this value for distance comparisons.
---@field debug_rect BoundingBox? Bounding box of the frustum for debug drawing

script.on_init(function()
	---@type table<unit_number, TrainRecord>
	storage.locomotives = {}
end)

local configs = require("global/config_loader").get_rolling_stock_config()

local LOCOMOTIVE_STOCK = {
	-- "Decapod_locomotive"
}

local locos = {}
---@type table<string, AnimatedTrainsConfig>
local entity_to_config = {}
for name, config in pairs(configs) do
    table.insert(LOCOMOTIVE_STOCK, name .. "-ATL")
		locos[name .. "-ATL"] = true
		entity_to_config[name .. "-ATL"] = config
end

local CAHCE_UPDATE_INTERVAL = 20
local frustums_cache = {}
local frustums_cache_tick = -1
local visible_locos_cache = {}
local frustum_margin = 1.1

local CARRIAGE_SIZE = 7 -- approx length + gap

local function draw_bbox(top, left, bottom, right, surface)
	rendering.draw_rectangle{
		color = {r = 0, g = 1, b = 0, a = 0.5},
		width = 2,
		filled = false,
		left_top = {left, top},
		right_bottom = {right, bottom},
		surface = surface,
		time_to_live = CAHCE_UPDATE_INTERVAL,
		draw_on_ground = false
	}
end

local RED = {r = 1, g = 0, b = 0, a = 0.5}
local GREEN = {r = 0, g = 1, b = 0, a = 0.5}
local BLUE = {r = 0, g = 0, b = 1, a = 0.5}

local function draw_dot(x, y, surface, color, text)
	rendering.draw_circle{
		color = color,
		radius = 1,
		filled = true,
		target = {x, y},
		surface = surface,
		time_to_live = CAHCE_UPDATE_INTERVAL,
		draw_on_ground = false
	}
	if text then
		rendering.draw_text{
			text = text,
			target = {x - 1, y - .75},
			surface = surface,
			time_to_live = CAHCE_UPDATE_INTERVAL,
			color = {r = 1, g = 1, b = 1, a = 1},
			scale = 2,
			draw_on_ground = false
		}
	end
end



---Get per surface an array of all frustums: The coordinates of their screens
---@return table<surface_index, Frustum[]>
local function get_players_frustums()
	local players_by_surface = {}
	local pixel_per_tile = 32 -- Should be 32, but greater for debug purposes so we can see "off-screen"

	for _, player in pairs(game.connected_players) do
		if player.character then
			local position = player.position
			-- TODO cache all the fixed values per player
			local zoom = player.zoom
			if zoom < 0.4 then
				-- Max zoom level before screen turns into radar view. Doesn't need to render
				-- TODO is there a way a mod could change this value?
				goto continue
			end
			local screen_width = player.display_resolution.width
			local screen_height = player.display_resolution.height

			local half_width = screen_width / 2 / pixel_per_tile / zoom
			local half_height = screen_height / 2 / pixel_per_tile / zoom
			local margin_width = half_width * (frustum_margin - 1)
			local margin_height = half_height * (frustum_margin - 1)

			local dx = half_width + margin_width
			local dy = half_height + margin_height

			local dm = max(dx, dy)
			local max_dist_sq = 2 * dm * dm
			local max_dist = sqrt(max_dist_sq)

			local surface_index = player.surface.index
			local arr = players_by_surface[surface_index]
			if not arr then
				arr = {}
				players_by_surface[surface_index] = arr
			end

			arr[#arr + 1] = {
				x = position.x,
				y = position.y,
				max_dist_sq = max_dist_sq,
				max_dist = max_dist,
				debug_rect = {
					left = position.x - dm,
					top = position.y - dm,
					right = position.x + dm,
					bottom = position.y + dm
				}
			}

			-- draw_bbox( -- Debug
			-- 	position.y - dm,
			-- 	position.x - dm,
			-- 	position.y + dm,
			-- 	position.x + dm,
			-- 	player.surface
			-- )
		end
		::continue::
	end
	return players_by_surface
end

---@param players_by_surface table<surface_index, Frustum[]>
---@return table<unit_number, LuaEntity>
local function get_visible_locomotives(players_by_surface)
	local visible_locos = {}

	for surface_index, players in pairs(players_by_surface) do
		local n_players = #players
		if n_players == 0 then goto continue end

		-- TODO possible optimization: Trains that are already visible for one player are still checked for the next player

		local trains = game.train_manager.get_trains{stock = LOCOMOTIVE_STOCK, surface = surface_index}
		if not trains then goto continue end

		local n_trains = #trains
		if n_trains == 0 then goto continue end

		for ti = 1, n_trains do
			local train = trains[ti]

			local carriages = train.carriages
			local n_carriages = #carriages

			local first_pos = carriages[1].position
			local train_extent = n_carriages * CARRIAGE_SIZE

			local skip_for_all_players = true
			for pi = 1, n_players do
				local player = players[pi]
				local dx = player.x - first_pos.x
				local dy = player.y - first_pos.y
				local dist_sq = dx * dx + dy * dy
				local threshold = player.max_dist + train_extent
				if dist_sq <= threshold * threshold then
					-- this train could intersect a player's view, do more detailed check
					skip_for_all_players = false
					break
				else
					--draw_dot(first_pos.x, first_pos.y, surface_index, BLUE, string.format("%.1f", dist_sq)) -- Debug
				end
			end
			if skip_for_all_players then goto continue_train end

			for _, locomotive in pairs(train.carriages) do
				if not locos[locomotive.name] then goto continue_carriage end
				--for _, locomotive in pairs(loco_list) do
					local lx = locomotive.position.x
					local ly = locomotive.position.y
					for _, p in pairs(players) do
						local dx = p.x - lx
						local dy = p.y - ly
						local d = dx * dx + dy * dy
						if d <= p.max_dist_sq then
							visible_locos[locomotive.unit_number] = locomotive
							--draw_dot(lx, ly, surface_index, GREEN, string.format("%.1f", d)) -- Debug
							break
						else
							--draw_dot(lx, ly, surface_index, RED, string.format("%.1f", d)) -- Debug
						end
					end
				--end
				::continue_carriage::
			end
			::continue_train::
		end
		::continue::
	end
	return visible_locos
end

---@type table<string, table<integer, table<integer, integer>>>
local sheet_indices_numbers = {}
---@type table<string, table<integer, table<integer, integer>>>
local sheet_indices_offsets = {}
for name, config in pairs(entity_to_config) do
  local spritterLua = config.layers[1].spritter_table
  local frames_per_sheet = spritterLua.line_length * spritterLua.lines_per_file

  local sheet_numbers = {}
  local sheet_offsets = {}
  local sheet_number = 0
  local index = 0
  for direction = 0, rotationframes - 1  do
    sheet_numbers[direction] = {}
    sheet_offsets[direction] = {}

    for frame = 0, config.frames_per_rotation - 1 do
      sheet_numbers[direction][frame] = sheet_number
			sheet_offsets[direction][frame] = index
      index = index + 1

      if index >= frames_per_sheet then
        sheet_number = sheet_number + 1
        index = 0
      end
    end
  end
  sheet_indices_numbers[name] = sheet_numbers
  sheet_indices_offsets[name] = sheet_offsets
end

---@param train_record TrainRecord
---@param locomotive LuaEntity
local function create_sheets(train_record, locomotive)
	local config = train_record.config
	train_record.animations = {}
	
	for sheet = 0, config.layers[1].spritter_table.file_count - 1 do
		local animation = rendering.draw_animation{
			animation = "atl-" .. config.name .. "-" .. sheet,
			orientation = 0,
			render_layer = "object",
			target = locomotive,
			surface = locomotive.surface,
			animation_offset = 0,
			animation_speed = 0,
			visible = false
		}
		train_record.animations[sheet] = animation
	end
end

---@param frame_progress number   -- fractional progress in [0,1)
---@param abs_frame_delta number  -- absolute number of frames advanced per tick
---@return integer
local function compute_ticks_until_update(frame_progress, abs_frame_delta)
	if abs_frame_delta <= 0 then
		return 0
	end

	local remaining = 1 - frame_progress
	local ticks = ceil(remaining / abs_frame_delta) - 1
	if ticks < 0 then
		return 0
	end
	return ticks
end

local four_pi_squared = 4 * math.pi^2
---@param locomotives table<unit_number, LuaEntity>
local function draw_locomotives(locomotives)
	local known_trains = storage.locomotives

	for unit_number, locomotive in pairs(locomotives) do
		if not locomotive.valid then
			known_trains[unit_number] = nil
			goto continue
		end

		local train_record = known_trains[unit_number]
		if not train_record then
			local config = entity_to_config[locomotive.name]
			local frames_per_rotation = config.frames_per_rotation

			train_record = {
				frame = 0,
				frame_progress = 0,
				ticks_until_update = 0,
				skipped_ticks = 0,
				animation_speed_multiplier = config.animation_speed_multiplier or 1,
				prev_direction = nil,
				active_sheet = nil,

				config = config,
				sheets_numbers = sheet_indices_numbers[locomotive.name],
				sheets_offsets = sheet_indices_offsets[locomotive.name],

				frames_per_rotation = frames_per_rotation,
				frame_factor = frames_per_rotation / four_pi_squared,
			}
			known_trains[unit_number] = train_record
		end

		if not train_record.animations then
			create_sheets(train_record, locomotive)
		end

		local frames_per_rotation = train_record.frames_per_rotation

		local speed = locomotive.speed * train_record.animation_speed_multiplier
		local direction = floor(locomotive.orientation * rotationframes)
		local prev_direction = train_record.prev_direction

		if speed == 0 then
			train_record.ticks_until_update = nil
			train_record.skipped_ticks = 0

			if prev_direction == direction then
				goto continue
			end

			local frame = train_record.frame
			local sheet_number = train_record.sheets_numbers[direction][frame]
			local index = train_record.sheets_offsets[direction][frame]
			local animation = train_record.animations[sheet_number]

			animation.animation_offset = index

			local active_sheet = train_record.active_sheet
			if active_sheet ~= sheet_number then
				if active_sheet then
					train_record.animations[active_sheet].visible = false
				end
				animation.visible = true
				train_record.active_sheet = sheet_number
			end

			train_record.prev_direction = direction
			goto continue
		end

		local frame_delta = speed * train_record.frame_factor
		-- Above is the simplified version of:
		-- local frames_per_circle = config.frames_per_rotation/(math.pi * 2)
		-- local angle_delta = (speed / 6.28) * frames_per_circle

		-- Same direction and we know we cannot hit the next frame yet
		if prev_direction == direction then
			local ticks_until_update = train_record.ticks_until_update
			if ticks_until_update and ticks_until_update > 0 then
				train_record.ticks_until_update = ticks_until_update - 1
				train_record.skipped_ticks = train_record.skipped_ticks + 1
				goto continue
			end
		end

		-- Full update: apply skipped ticks + this tick
		local elapsed_ticks = train_record.skipped_ticks + 1
		train_record.skipped_ticks = 0

		local frame = train_record.frame
		local frame_progress = train_record.frame_progress + frame_delta * elapsed_ticks

		-- floor() works for positive and negative values, but we want frame_progress normalized to [0,1)
		local whole_frames = floor(frame_progress)
		frame_progress = frame_progress - whole_frames
		frame = (frame + whole_frames) % frames_per_rotation

		local frame_changed = (frame ~= train_record.frame)
		local direction_changed = (direction ~= prev_direction)

		train_record.frame = frame
		train_record.frame_progress = frame_progress
		train_record.prev_direction = direction
		train_record.ticks_until_update = compute_ticks_until_update(frame_progress, abs(frame_delta))

		if not frame_changed and not direction_changed then
			goto continue
		end

		local sheet_number = train_record.sheets_numbers[direction][frame]
		local index = train_record.sheets_offsets[direction][frame]
		local animation = train_record.animations[sheet_number]

		animation.animation_offset = index

		local active_sheet = train_record.active_sheet
		if active_sheet ~= sheet_number then
			if active_sheet then
				train_record.animations[active_sheet].visible = false
			end
			animation.visible = true
			train_record.active_sheet = sheet_number
		end

		::continue::
	end
end

local profiler = helpers.create_profiler(true)

---@param event EventData.on_tick
script.on_event(defines.events.on_tick, function(event)
	local frustums_by_surface
	local visible_locos = visible_locos_cache
	local tick = event.tick
	
	if (tick % CAHCE_UPDATE_INTERVAL) == 0 or frustums_cache_tick < 0 then
		frustums_by_surface = get_players_frustums()
		
		frustums_cache = frustums_by_surface
		frustums_cache_tick = tick
		
		visible_locos_cache = get_visible_locomotives(frustums_by_surface)
	end
	
	frustums_by_surface = frustums_cache
	visible_locos = visible_locos_cache
	
	profiler.reset()
	for i=1,1 do
		draw_locomotives(visible_locos)
	end
	profiler.stop()
	game.print( profiler )
end)


local entity_built = require("events/entity_built")
script.on_event(defines.events.on_built_entity, entity_built.on_built_entity, entity_built.on_built_entity_filter)
script.on_event(defines.events.on_robot_built_entity, entity_built.on_robot_built_entity, entity_built.on_robot_built_entity_filter)
script.on_event(defines.events.script_raised_built, entity_built.script_raised_built, entity_built.script_built_filter)
-- script.on_event(defines.events.script_raised_revive, entity_built.event, entity_built.filter)