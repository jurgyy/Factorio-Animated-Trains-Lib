---@alias atl_data_type "atl-config"

---@class AnimatedTrainsConfigModData : data.ModData
---@field data_type atl_data_type
---@field data AnimatedTrainsConfig

---@class LuaAnimatedTrainsConfigModData : LuaModData
---@field data_type atl_data_type
---@field data AnimatedTrainsConfig

---@class AnimatedTrainsConfig
---@field name string Name of the train entity this config applies to
---@field layers AnimatedTrainsLayer[] Different render layers that make up the animation
---@field animation_speed_multiplier number? Multiplier for the animation speed, default is 1
---@field frames_per_rotation integer Number of frames per rotation axis

---@class AnimatedTrainsLayer
---@field file_path string File path of the sprite sheets without the extension and suffixed with "-<number>" for multiple files
---@field spritter_table SpritterOutput
---@field draw_as_shadow boolean
---@field draw_as_glow boolean
---@field draw_as_light boolean

---@class SpritterOutput Lua Table that the spritter sprite sheet tool generates - https://github.com/fgardt/factorio-spritter
---@field spritter integer[] Spritter version
---@field file_count integer Number of files the animations are split across
---@field line_length integer Columns of sprites per file
---@field lines_per_file integer Rows of sprites per file
---@field sprite_count integer Total number of frames across the entire animation
---@field height integer Width of each individual sprite frame
---@field width integer Height of each individual sprite frame
---@field shift number[] Shift of the sprite, index 1 is the x axis, index 2 is the y axis
---@field scale number Scale of the sprite

--------

local configs = require("global/config_loader").get_rolling_stock_config()

for name, config in pairs(configs) do
  local spritter_lua = config.layers[1].spritter_table
  local frames_last_sheet = spritter_lua.sprite_count % (spritter_lua.line_length * spritter_lua.lines_per_file)
  
  local frame_count = spritter_lua.line_length * spritter_lua.lines_per_file
  for sheet = 0, spritter_lua.file_count - 1 do
    if frames_last_sheet ~= 0 and sheet == spritter_lua.file_count - 1 then
      frame_count = frames_last_sheet
    end
    
    local layers = {}
    for _, layer in pairs(config.layers) do
      local path = layer.file_path .. "-" .. sheet
      layers[#layers + 1] = {
        filename = path .. ".png",
        height = layer.spritter_table.height,
        width = layer.spritter_table.width,
        scale = layer.spritter_table.scale,
        shift = layer.spritter_table.shift,
        frame_count = frame_count,
        line_length = layer.spritter_table.line_length,
        lines_per_file = layer.spritter_table.lines_per_file,
        draw_as_shadow = layer.draw_as_shadow,
        draw_as_glow = layer.draw_as_glow,
        draw_as_light = layer.draw_as_light,
        usage = "train"
      }
    end

    data:extend({{
      type = "animation",
      name = "atl-" .. name .. "-" .. sheet,
      layers = layers
    }})
  end

  ---@type data.RollingStockPrototype
  local entity = data.raw["locomotive"][name] or data.raw["cargo-wagon"][name]
  if not entity then
    error("Animated Trains: Could not find entity '" .. name .. "' to apply animated train config to.")
  end
  local item = data.raw["item-with-entity-data"][name]
  if not item then
    error("Animated Trains: Could not find item-with-entity-data '" .. name .. "' to apply animated train config to.")
  end

  log("Creating ATL copy of entity '" .. name .. "'")
  local copy = table.deepcopy(entity)
  copy.name = name .. "-ATL"
  copy.localised_name = copy.localised_name or {"entity-name." .. entity.name }
  copy.localised_description = copy.localised_description or (entity.localised_description and {"entity-description." .. entity.name }) or nil
  copy.pictures = nil
  copy.factoriopedia_alternative = name
  copy.hidden_in_factoriopedia = true
  copy.hidden = false
  copy.placeable_by = { item = item.name, count = 1 }
  ---@diagnostic disable-next-line: assign-type-mismatch
  data:extend({copy})
end
