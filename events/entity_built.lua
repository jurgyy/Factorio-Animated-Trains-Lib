local config_loader = require("global/config_loader")
local entity_built_configs = config_loader.get_entity_built_config()
local rolling_stock_config = config_loader.get_rolling_stock_config()

local name_to_atl_name = {}
local atl_name_to_name = {}
for entity_name, _ in pairs(rolling_stock_config) do
  local atl_name = entity_name .. "-ATL"
  name_to_atl_name[entity_name] = atl_name
  atl_name_to_name[atl_name] = entity_name
end

local function call_remote_built_events(source_entity_name, event)
  local remotes = entity_built_configs[source_entity_name]
  if remotes then
    for _, remote_interface in pairs(remotes) do
      remote.call(remote_interface.remote_interface, remote_interface.remote_function, event)
    end
  end
end

---@param event EventData.on_built_entity
---@param entity LuaEntity
---@param atl_name string
local function handle_source_loco_built(event, entity, atl_name)
  if not prototypes.entity[atl_name] then return end

  local surface = entity.surface

  local fast_replace = surface.can_fast_replace{
    name = atl_name,
    position = entity.position,
    direction = entity.direction,
    force = entity.force
  }

  ---@type LuaSurface.create_entity_param.locomotive | LuaSurface.create_entity_param.cargo_wagon
  local entity_data = {
    name = atl_name,
    position = entity.position,
    direction = entity.direction,
    force = entity.force,
    raise_built = false, -- Will be called manually after the entity is created
    fast_replace = true,
    create_build_effect_smoke = false,
    orientation = entity.orientation,
    enable_logistics_while_moving = entity.enable_logistics_while_moving,
    grid = entity.grid,
    color = entity.color,
    copy_color_from_train_stop = entity.copy_color_from_train_stop,
    --player = event.player_index, -- If set will give the player the item back
    spill = false
  }
  local source_entity_name = entity.name

  local new_entity = surface.create_entity(entity_data)
  if not new_entity then
    game.print("Failed to create entity: " .. atl_name)
    return
  end

  event.entity = new_entity
  call_remote_built_events(source_entity_name, event)
end

local entity_built = {}

---@param event EventData.on_built_entity
entity_built.on_built_entity = function(event)
  local entity = event.entity
  if not entity or not entity.valid then return end

  game.print("Entity built event triggered for entity: " .. event.entity.name, {skip=defines.print_skip.never, sound = defines.print_sound.never})

  local atl_name = name_to_atl_name[entity.name]
  local source_name = atl_name_to_name[entity.name]
  if source_name then
    -- ATL entity built
    call_remote_built_events(source_name, event)
  elseif atl_name then
    -- Source entity built
    handle_source_loco_built(event, entity, atl_name)
  end
end

-- ---@param event EventData.script_raised_built
-- entity_built.script_raised_built = function(event)
-- end

entity_built.on_robot_built_entity = entity_built.on_built_entity
entity_built.script_raised_built = entity_built.on_built_entity

entity_built.on_built_entity_filter = {
  -- {filter = "name", name = "entity-ghost"},
  -- {filter = "type", type = "entity-ghost", mode = "and"},
  -- {filter = "ghost_type", type = "locomotive", mode = "and"},

  -- {filter = "name", name = "entity-ghost", mode = "or"},
  -- {filter = "type", type = "entity-ghost", mode = "and"},
  -- {filter = "ghost_type", type = "cargo-wagon", mode = "and"},

  {filter = "type", type = "locomotive", mode = "or"},
  {filter = "type", type = "cargo-wagon", mode = "or"},
}

entity_built.on_robot_built_entity_filter = entity_built.on_built_entity_filter
entity_built.script_built_filter = entity_built.on_built_entity_filter

return entity_built