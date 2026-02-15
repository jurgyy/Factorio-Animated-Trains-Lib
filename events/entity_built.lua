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
    raise_built = false,
    create_build_effect_smoke = false,
  }
  
  entity.destroy()

  local surface = surface.create_entity(entity_data)

  -- if entity.name:find("%-ATL$") then
  --   entity.hidden = false
  -- end
end

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

return entity_built