-- defgraph/defgraph.lua
-- DefGraph v5.0 - Main public entry point
-- This module contains functions to create a world map as a shape of a graph and the ability
-- to manipulate it at any time, easily see debug drawing of this graph and move and rotate
-- game objects inside of this graph with utilizing auto pathfinder.

-- Initialize random seed once when the module is loaded
math.randomseed(os.time() - os.clock() * 1000)

local M = {}

-- Load all internal modules
local constants = require("defgraph.constants")
local config = require("defgraph.config")
local map = require("defgraph.map")
local player = require("defgraph.player")

-- ==================== PUBLIC API ====================

-- Public constants
M.ROUTETYPE         = constants.ROUTETYPE
M.CollisionBehavior = constants.CollisionBehavior

-- Public classes
M.Map               = map.Map
M.Player            = player.Player
M.PlayerConfig      = config.PlayerConfig

-- Map factory functions
M.create_map        = map.create_map
M.get_map           = map.get_map
M.create_or_get_map = map.create_or_get_map
M.has_map           = map.has_map
M.remove_map        = map.remove_map

return M