-- defgraph/defgraph.lua
-- DefGraph v5.0 - Main public entry point
-- This module contains functions to create a world map as a shape of a graph and the ability
-- to manipulate it at any time, easily see debug drawing of this graph and move and rotate
-- game objects inside of this graph with utilizing auto pathfinder.

-- Initialize random seed once when the module is loaded
math.randomseed(os.time() - os.clock() * 1000)

local M = {}

-- Load all internal modules
local constants_module   = require("defgraph.constants")
local config_module      = require("defgraph.config")
local map_module         = require("defgraph.map")
local player_module      = require("defgraph.player")

-- ==================== PUBLIC API ====================

-- Public constants
M.ROUTETYPE         = constants_module.ROUTETYPE
M.CollisionBehavior = constants_module.CollisionBehavior

-- Public classes
M.Map               = map_module.Map
M.Player            = player_module.Player
M.PlayerConfig      = config_module.PlayerConfig

-- Map factory functions
M.create_map        = map_module.create_map
M.get_map           = map_module.get_map
M.create_or_get_map = map_module.create_or_get_map
M.has_map           = map_module.has_map
M.remove_map        = map_module.remove_map

return M