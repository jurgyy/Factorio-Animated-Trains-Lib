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

local function handle_source_loco_built(event, entity, atl_name)
  if not prototypes.entity[atl_name] then return end

  local surface = entity.surface
  ---@type LuaSurface.create_entity_param.locomotive | LuaSurface.create_entity_param.cargo_wagon
  local entity_data = {
    name = atl_name,
    position = entity.position,
    direction = entity.direction,
    force = entity.force,
    raise_built = true,
    create_build_effect_smoke = false,
    orientation = entity.orientation,
    enable_logistics_while_moving = entity.enable_logistics_while_moving,
    grid = entity.grid,
    color = entity.color,
    copy_color_from_train_stop = entity.copy_color_from_train_stop
  }
  local source_entity_name = entity.name
  entity.destroy()

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
  game.print("Entity built event triggered for entity: " .. event.entity.name)
  local entity = event.entity
  if not entity or not entity.valid then return end

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

-- TODO fix ghost built trains
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