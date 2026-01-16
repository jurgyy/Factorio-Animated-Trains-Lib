---@type atl_data_type
local data_type = "atl-config"

local config_cache = {}

---@return table<string, AnimatedTrainsConfig>
local function get_all_configs()
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
    if prototype.data_type == data_type then
      local data = prototype.data --[[@as AnimatedTrainsConfig]]
      config_cache[data.name] = data
    end
  end
  return config_cache
end

return get_all_configs()