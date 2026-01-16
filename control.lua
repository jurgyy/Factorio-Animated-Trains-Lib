local floor = math.floor

local rotationframes = 128
local animationframes = 8
local frames_per_circle = animationframes/(math.pi * 2)

---@alias unit_number integer
---@alias surface_index integer

---@class TrainRecord
---@field previous_frame_angle number
---@field frame integer
---@field animations LuaRenderObject[]? Array of all possible animation sheets the locomotive can use
---@field active_sheet integer? Currently active sheet index
---@field prev_direction integer? Previously used direction index

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

local configs = require("global/config_loader")

local LOCOMOTIVE_STOCK = {
	-- "Decapod_locomotive"
}

local locos = {}

for name, config in pairs(configs) do
    table.insert(LOCOMOTIVE_STOCK, name)
		locos[name] = true
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

			local dm = math.max(dx, dy)
			local max_dist_sq = 2 * dm * dm
			local max_dist = math.sqrt(max_dist_sq)

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

---@type table<string, table<integer, table<integer, {integer, integer}>>>
local sheet_indices = {}
for name, config in pairs(configs) do
  local spritterLua = config.layers[1].spritter_table
  local frames_per_sheet = spritterLua.line_length * spritterLua.lines_per_file

  local sheet = {}
  local sheet_number = 0
  local index = 0
  for direction = 0, rotationframes - 1  do
    sheet[direction] = {}

    for frame = 0, animationframes - 1 do
      sheet[direction][frame] = { sheet_number, index }
      index = index + 1

      if index >= frames_per_sheet then
        sheet_number = sheet_number + 1
        index = 0
      end
    end
  end
  sheet_indices[name] = sheet
end

---@param train_record TrainRecord
---@param locomotive LuaEntity
local function create_sheets(train_record, locomotive)
  local config = configs[locomotive.name]
	train_record.animations = {}
	for sheet = 0, config.layers[1].spritter_table.file_count - 1 do
		-- draw_animation{animation=…, orientation?=…, x_scale?=…, y_scale?=…, tint?=…, render_layer?=…, animation_speed?=…, animation_offset?=…, orientation_target?=…, use_target_orientation?=…, oriented_offset?=…, target=…, surface=…, time_to_live?=…, blink_interval?=…, forces?=…, players?=…, visible?=…, only_in_alt_mode?=…, render_mode?=…}
		local animation = rendering.draw_animation{
			animation = "atl-" .. config.name .. "-" .. sheet,
			orientation = 0,
			render_layer = "above-inserters",
			target = locomotive,
			surface = locomotive.surface,
			animation_offset = 0,
			animation_speed = 0,
			visible = false
		}
		train_record.animations[sheet] = animation
	end
end

---@param locomotives table<unit_number, LuaEntity>
local function draw_locomotives(locomotives)
	local known_trains = storage.locomotives
	for unit_number, locomotive in pairs(locomotives) do
		local train_record = known_trains[unit_number]

		if not train_record then
			train_record = {previous_frame_angle = 0, frame = -1}
			known_trains[unit_number] = train_record
		end

		if not locomotive.valid then
			known_trains[unit_number] = nil
			goto continue
		end

		if not train_record.animations then
			create_sheets(train_record, locomotive)
		end
		
		local speed = locomotive.speed
		-- Different frame speed depending on the locomotive's speed to make it look nicer at lower speeds
		--game.print("Speed ".. unit_number ..": " .. speed, {sound = defines.print_sound.never})
		speed = speed < 1 and speed * 6 or speed * 5
		
		local direction = floor(locomotive.orientation * rotationframes)
		
		local angle_delta = (speed / 6.28) * frames_per_circle
		local next_frame_angle = (train_record.previous_frame_angle or 0) + angle_delta
		local frame_angle = next_frame_angle % animationframes
		
		local frame = floor(frame_angle)
		local prev_frame = train_record.frame

		train_record.previous_frame_angle = frame_angle
		if direction == train_record.prev_direction and prev_frame == frame then
			goto continue
		end
		train_record.prev_direction = direction
		train_record.frame = frame
		
		local sheet_info = sheet_indices[locomotive.name][direction][frame]
		local sheet_number = sheet_info[1]
		local index = sheet_info[2]
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
	draw_locomotives(visible_locos)
end)