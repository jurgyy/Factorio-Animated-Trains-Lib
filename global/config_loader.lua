---@alias atl_entity_built_data_type "atl-entity-built-config"

---@type atl_data_type
local rolling_stock_data_type = "atl-config"
local rolling_stock_config_cache = nil

---@type atl_entity_built_data_type
local entity_built_config_type = "atl-entity-built-config"
local entity_built_config_cache = nil

---@class AnimatedTrainsEntityBuiltConfigModData : data.ModData
---@field data_type atl_entity_built_data_type
---@field data AnimatedTrainsEntityBuiltConfig

---@class LuaAnimatedTrainsEntityBuiltConfigModData : LuaModData
---@field data_type atl_entity_built_data_type
---@field data AnimatedTrainsEntityBuiltConfig

---@class AnimatedTrainsEntityBuiltConfig
---@field remote_interface string Remote interface to call when an entity is built
---@field remote_function string Remote function to call
---@field entities string[] List of entity names that the remote function will be called on

---@return table<string, AnimatedTrainsConfig>
local function get_rolling_stock_config()
  if rolling_stock_config_cache then return rolling_stock_config_cache end
  rolling_stock_config_cache = {}
  
  local iterator = nil
  if script then
    iterator = prototypes.mod_data
  else
    iterator = data.raw["mod-data"]
  end
  
  if not iterator then
    log("No mod-data prototypes found")
    return {}
  end

  for _, prototype in pairs(iterator) do
    if prototype.data_type == rolling_stock_data_type then
      local data = prototype.data
      rolling_stock_config_cache[data.name] = data
    end
  end

  return rolling_stock_config_cache
end

---@return table<string, {remote_interface: string, remote_function: string}[]>
local function get_entity_built_config()
  if entity_built_config_cache then return entity_built_config_cache end
  entity_built_config_cache = {}
  
  local iterator = nil
  if script then
    iterator = prototypes.mod_data
  else
    iterator = data.raw["mod-data"]
  end
  
  if not iterator then
    log("No mod-data prototypes found")
    return {}
  end

  for _, prototype in pairs(iterator) do
    if prototype.data_type == entity_built_config_type then
      ---@type AnimatedTrainsEntityBuiltConfig
      local config = prototype.data
      for _, entity in pairs(config.entities) do
        if not entity_built_config_cache[entity] then
          entity_built_config_cache[entity] = {}
        end
        table.insert(entity_built_config_cache[entity], {
          remote_interface = config.remote_interface,
          remote_function = config.remote_function
        })
      end
    end
  end
  return entity_built_config_cache
end

return {
  get_rolling_stock_config = get_rolling_stock_config,
  get_entity_built_config = get_entity_built_config
}