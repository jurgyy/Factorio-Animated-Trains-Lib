local entity_built_configs = require("global/config_loader").get_entity_built_config()

local entity_built = {}

---@param event EventData.on_built_entity
entity_built.on_built_entity = function(event)
  game.print("Entity built event triggered for entity: " .. event.entity.name)
  local entity = event.entity
  if not entity or not entity.valid then return end

  local name = entity.name .. "-ATL"
  if not prototypes.entity[name] then return end

  local surface = entity.surface
  ---@type LuaSurface.create_entity_param.locomotive | LuaSurface.create_entity_param.cargo_wagon
  local entity_data = {
    name = name,
    position = entity.position,
    direction = entity.direction,
    force = entity.force,
    raise_built = true,
    create_build_effect_smoke = false,
  }
  local entity_name = entity.name  
  entity.destroy()

  local new_entity = surface.create_entity(entity_data)
  if not new_entity then
    game.print("Failed to create entity: " .. name)
    return
  end

  event.entity = new_entity
  local remotes = entity_built_configs[entity_name]
  if remotes then
    for _, remote_interface in pairs(remotes) do
      remote.call(remote_interface.remote_interface, remote_interface.remote_function, event)
    end
  end
end

entity_built.on_robot_built_entity = entity_built.on_built_entity

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

return entity_built