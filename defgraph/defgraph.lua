-- DefGraph v5.0
-- This module contains functions to create a world map as a shape of a graph and the ability
-- to manipulate it at any time, easily see debug drawing of this graph and move and rotate
-- game objects inside of this graph with utilizing auto pathfinder.

local M = {}

math.randomseed(os.time() - os.clock() * 1000)

----------------------------------------------------------------------
-- Shared math / helpers
----------------------------------------------------------------------

local sqrt  = math.sqrt
local abs   = math.abs
local huge  = math.huge
local atan2 = math.atan2

local function default(value, fallback)
    if value == nil then return fallback end
    return value
end

local function distance(source, destination)
    local dx = source.x - destination.x
    local dy = source.y - destination.y
    return sqrt(dx * dx + dy * dy)
end

local function heap_push(heap, node_id, dist)
    local i = #heap + 1
    heap[i] = { id = node_id, dist = dist }

    while i > 1 do
        local p = math.floor(i / 2)
        if heap[p].dist <= heap[i].dist then break end
        heap[p], heap[i] = heap[i], heap[p]
        i = p
    end
end

local function heap_pop(heap)
    local n = #heap
    if n == 0 then return nil, nil end

    local root = heap[1]
    local last = heap[n]
    heap[n] = nil

    if n > 1 then
        heap[1] = last
        local i = 1
        while true do
            local l = i * 2
            local r = l + 1
            local smallest = i

            if l <= #heap and heap[l].dist < heap[smallest].dist then
                smallest = l
            end
            if r <= #heap and heap[r].dist < heap[smallest].dist then
                smallest = r
            end
            if smallest == i then break end

            heap[i], heap[smallest] = heap[smallest], heap[i]
            i = smallest
        end
    end

    return root.id, root.dist
end

----------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------
local DEFAULT_ROUTE_LANE_OFFSET = 10

local NODETYPE = {
    SINGLE       = hash("defgraph_nodetype_single"),
    DEADEND      = hash("defgraph_nodetype_deadend"),
    INTERSECTION = hash("defgraph_nodetype_intersection")
}

M.ROUTETYPE = {
    ONETIME = hash("defgraph_routetype_onetime"),
    SHUFFLE = hash("defgraph_routetype_shuffle"),
    CYCLE   = hash("defgraph_routetype_cycle")
}

M.CollisionBehavior = {
    SuperCautious = hash("defgraph_collision_behavior_super_cautious"),
    Cautious      = hash("defgraph_collision_behavior_cautious"),
    Balanced      = hash("defgraph_collision_behavior_balanced"),
    Reactive      = hash("defgraph_collision_behavior_reactive"),
    SuperReactive = hash("defgraph_collision_behavior_super_reactive")
}

local COLLISION_BEHAVIOR_PRESETS = {
    [M.CollisionBehavior.SuperCautious] = {
        lookahead_min           = 0.40,
        lookahead_max           = 0.80,
        lookahead_speed_factor  = 0.035,

        predictive_scale        = 0.55,
        reactive_scale          = 0.32,

        predictive_slow         = 0.95,
        reactive_slow           = 0.85,

        queue_spacing_factor    = 1.9,
        queue_slow              = 0.97,

        path_recentering        = 0.65,

        dir_smoothing           = 0.32,
        speed_smoothing         = 0.26,

        -- NEW:
        density_radius_factor   = 3.0,   -- radius * 3
        density_slow_factor     = 0.50,  -- strong slowdown
    },

    [M.CollisionBehavior.Cautious] = {
        lookahead_min           = 0.32,
        lookahead_max           = 0.70,
        lookahead_speed_factor  = 0.028,

        predictive_scale        = 0.50,
        reactive_scale          = 0.28,

        predictive_slow         = 0.92,
        reactive_slow           = 0.82,

        queue_spacing_factor    = 1.7,
        queue_slow              = 0.95,

        path_recentering        = 0.55,

        dir_smoothing           = 0.26,
        speed_smoothing         = 0.22,

        density_radius_factor   = 2.8,
        density_slow_factor     = 0.40,
    },

    [M.CollisionBehavior.Balanced] = {
        lookahead_min           = 0.25,
        lookahead_max           = 0.60,
        lookahead_speed_factor  = 0.02,

        predictive_scale        = 0.45,
        reactive_scale          = 0.25,

        predictive_slow         = 0.90,
        reactive_slow           = 0.80,

        queue_spacing_factor    = 1.5,
        queue_slow              = 0.95,

        path_recentering        = 0.50,

        dir_smoothing           = 0.22,
        speed_smoothing         = 0.18,

        density_radius_factor   = 2.5,
        density_slow_factor     = 0.30,
    },

    [M.CollisionBehavior.Reactive] = {
        lookahead_min           = 0.20,
        lookahead_max           = 0.50,
        lookahead_speed_factor  = 0.015,

        predictive_scale        = 0.40,
        reactive_scale          = 0.30,

        predictive_slow         = 0.85,
        reactive_slow           = 0.75,

        queue_spacing_factor    = 1.3,
        queue_slow              = 0.90,

        path_recentering        = 0.40,

        dir_smoothing           = 0.18,
        speed_smoothing         = 0.14,

        density_radius_factor   = 2.2,
        density_slow_factor     = 0.20,
    },

    [M.CollisionBehavior.SuperReactive] = {
        lookahead_min           = 0.15,
        lookahead_max           = 0.40,
        lookahead_speed_factor  = 0.01,

        predictive_scale        = 0.35,
        reactive_scale          = 0.35,

        predictive_slow         = 0.80,
        reactive_slow           = 0.70,

        queue_spacing_factor    = 1.2,
        queue_slow              = 0.85,

        path_recentering        = 0.30,

        dir_smoothing           = 0.12,
        speed_smoothing         = 0.10,

        density_radius_factor   = 2.0,
        density_slow_factor     = 0.10,  -- barely slows down
    },
}

----------------------------------------------------------------------
-- PlayerConfig
----------------------------------------------------------------------

local PlayerConfig = {}
PlayerConfig.__index = PlayerConfig

local PLAYER_DEFAULTS = {
    gameobject_threshold = 2,
    allow_enter_on_route = true,

    path_curve_tightness = 4,
    path_curve_roundness = 3,
    path_curve_max_distance_from_corner = 10,

    collision_enabled = false,
    collision_radius  = 6,
    collision_groups  = nil,
    collision_behavior = M.CollisionBehavior.Balanced
}

function PlayerConfig.new(options)
    options = options or {}

    local self = {
        gameobject_threshold = default(options.gameobject_threshold, PLAYER_DEFAULTS.gameobject_threshold),
        allow_enter_on_route = default(options.allow_enter_on_route, PLAYER_DEFAULTS.allow_enter_on_route),
        path_curve_tightness = default(options.path_curve_tightness, PLAYER_DEFAULTS.path_curve_tightness),
        path_curve_roundness = default(options.path_curve_roundness, PLAYER_DEFAULTS.path_curve_roundness),
        path_curve_max_distance_from_corner = default(options.path_curve_max_distance_from_corner, PLAYER_DEFAULTS.path_curve_max_distance_from_corner),
        collision_enabled = default(options.collision_enabled, PLAYER_DEFAULTS.collision_enabled),
        collision_radius  = default(options.collision_radius, PLAYER_DEFAULTS.collision_radius),
        collision_groups  = default(options.collision_groups, PLAYER_DEFAULTS.collision_groups),
        collision_behavior = default(options.collision_behavior, PLAYER_DEFAULTS.collision_behavior)
    }

    return setmetatable(self, PlayerConfig)
end

function PlayerConfig:validate()
    -- existing numeric validations
    assert(type(self.gameobject_threshold) == "number",
        "PlayerConfig: gameobject_threshold must be a number")

    assert(type(self.path_curve_tightness) == "number",
        "PlayerConfig: path_curve_tightness must be a number")

    assert(type(self.path_curve_roundness) == "number",
        "PlayerConfig: path_curve_roundness must be a number")

    assert(type(self.path_curve_max_distance_from_corner) == "number",
        "PlayerConfig: path_curve_max_distance_from_corner must be a number")

    -- existing boolean validation
    assert(type(self.allow_enter_on_route) == "boolean",
        "PlayerConfig: allow_enter_on_route must be a boolean")

    -- NEW collision validations
    assert(type(self.collision_enabled) == "boolean",
        "PlayerConfig: collision_enabled must be a boolean")

    assert(type(self.collision_radius) == "number",
        "PlayerConfig: collision_radius must be a number")

    assert(self.collision_groups == nil or type(self.collision_groups) == "table",
        "PlayerConfig: collision_groups must be nil or a list of group names")

    if self.collision_groups ~= nil then
        for i, group in ipairs(self.collision_groups) do
            assert(type(group) == "string",
                "PlayerConfig: collision_groups must contain strings")
        end
    end

    assert(COLLISION_BEHAVIOR_PRESETS[self.collision_behavior],
        "PlayerConfig: Invalid collision_behavior preset")

    -- existing range checks
    assert(self.gameobject_threshold >= 0,
        "PlayerConfig: gameobject_threshold must be >= 0")

    assert(self.path_curve_tightness >= 0,
        "PlayerConfig: path_curve_tightness must be >= 0")

    assert(self.path_curve_roundness >= 0,
        "PlayerConfig: path_curve_roundness must be >= 0")

    assert(self.path_curve_max_distance_from_corner >= 0,
        "PlayerConfig: path_curve_max_distance_from_corner must be >= 0")

    assert(self.collision_radius >= 0,
        "PlayerConfig: collision_radius must be >= 0")

    return true
end


-- debug drawing defaults (shared)
local debug_node_color          = vmath.vector4(1, 0, 1, 1)
local debug_two_way_route_color = vmath.vector4(0, 1, 0, 1)
local debug_one_way_route_color = vmath.vector4(0, 1, 1, 1)
local debug_draw_scale          = 5

----------------------------------------------------------------------
-- Classes
----------------------------------------------------------------------

----------------------------------------------------------------------
-- Node class
----------------------------------------------------------------------
local Node = {}
Node.__index = Node

function Node.new(id, key, position, nodetype)
    return setmetatable({
        id        = id,
        key       = key,
        position  = position,
        type      = nodetype,
        neighbor_id = {},   -- existing neighbor structure
        groups    = {},   -- node groups: { group_name = true }
    }, Node)
end

local Map   = {}
Map.__index = Map

-- Internal hidden map state (private, not exposed on Map object)
local map_state = setmetatable({}, {__mode = 'k'})

local function get_map_state(self)
    local state = map_state[self]
    assert(state, 'Invalid Map object')
    return state
end

local function set_map_state(self, state)
    map_state[self] = state
end

function Map.__newindex(self, key, value)
    error('Cannot set Map.' .. tostring(key) .. ' (Map internal state is read-only)')
end

local Player   = {}
Player.__index = Player

----------------------------------------------------------------------
-- Map Registry
----------------------------------------------------------------------

local map_registry = {}

function M.create_map(key)
    assert(key, "Map key required")
    assert(not map_registry[key], "Map with this key already exists")

    local map = M.Map.new()
    map_registry[key] = map
    return map
end

function M.get_map(key)
    return map_registry[key]
end

function M.create_or_get_map(key)
    if not map_registry[key] then
        map_registry[key] = M.Map.new()
    end
    return map_registry[key]
end

function M.has_map(key)
    return map_registry[key] ~= nil
end

function M.remove_map(key)
    local map = map_registry[key]
    if not map then return end

    -- Optional: destroy map internals
    if map.destroy then
        map:destroy()
    end

    map_registry[key] = nil
end

----------------------------------------------------------------------
-- Map constructor
----------------------------------------------------------------------
function Map.new()
    local map = setmetatable({}, Map)
    local state = {
        -- graph data
        map_node_list    = {}, -- [node_id] = Node
        map_route_list   = {}, -- [from_id][to_id] = { a,b,c,distance,ab_len2,inv_ab_len }
        pathfinder_cache = {}, -- [from_id][to_id] = { distance, path[], node_versions[], route_versions[] }

        -- node registry / groups
        node_registry   = {},  -- key -> Node
        nodes_by_group  = {},  -- group -> { node_id = true }

        -- players
        players         = {},  -- player registry
        players_by_group = {}, -- player group -> { key -> player }

        -- versioning
        node_version   = {},   -- [node_id] = int
        route_version  = {},   -- [from_id][to_id] = int

        map_node_id_iter = 0,  -- node id iterator
        player_id_iter   = 0,  -- player id iterator
    }
    set_map_state(map, state)
    return map
end

----------------------------------------------------------------------
-- Map: node registry and groups
----------------------------------------------------------------------

function Map:get_node_by_id(id)
    return get_map_state(self).map_node_list[id]
end

function Map:get_node_by_key(key)
    return get_map_state(self).node_registry[key]
end

function Map:add_node_to_group(node_id, group)
    local node = get_map_state(self).map_node_list[node_id]
    if not node then return false end

    if node.groups[group] then
        return false
    end

    node.groups[group] = true
    get_map_state(self).nodes_by_group[group] = get_map_state(self).nodes_by_group[group] or {}
    get_map_state(self).nodes_by_group[group][node_id] = true

    return true
end

function Map:remove_node_from_group(node_id, group)
    local node = get_map_state(self).map_node_list[node_id]
    if not node then return end

    if node.groups[group] then
        node.groups[group] = nil
    end

    local g = get_map_state(self).nodes_by_group[group]
    if g then
        g[node_id] = nil
        if next(g) == nil then
            get_map_state(self).nodes_by_group[group] = nil
        end
    end
end

function Map:get_nodes_in_group(group)
    local g = get_map_state(self).nodes_by_group[group]
    if not g then return {} end

    local list = {}
    for node_id in pairs(g) do
        list[#list + 1] = get_map_state(self).map_node_list[node_id]
    end
    return list
end

function Map:remove_node_by_key(key)
    assert(key, "You must provide a node key")

    local node = get_map_state(self).node_registry[key]
    assert(node, ("Unknown node key %s"):format(tostring(key)))

    -- Delegate to the main removal function
    self:remove_node(node.id)
end

function Map:remove_nodes_in_group(group)
    assert(group, "You must provide a group name")

    local g = get_map_state(self).nodes_by_group[group]
    if not g then return end

    -- Copy node IDs first to avoid modifying the table while iterating
    local ids = {}
    for node_id in pairs(g) do
        ids[#ids + 1] = node_id
    end

    -- Remove each node using the canonical removal function
    for i = 1, #ids do
        self:remove_node(ids[i])
    end

    -- Remove the group entry itself
    get_map_state(self).nodes_by_group[group] = nil
end

function Map:get_player(key)
    return get_map_state(self).players[key]
end

function Map:remove_player(key)
    local player = get_map_state(self).players[key]
    if not player then return end

    -- Remove from all groups
    if player.groups then
        for group in pairs(player.groups) do
            local g = get_map_state(self).players_by_group[group]
            if g then g[key] = nil end
        end
    end

    -- Destroy player
    if player.destroy then
        player:destroy()
    end

    get_map_state(self).players[key] = nil
end

function Map:get_players_in_group(group)
    local g = get_map_state(self).players_by_group[group]
    if not g then return {} end

    local list = {}
    for key in pairs(g) do
        list[#list + 1] = get_map_state(self).players[key]
    end
    return list
end

function Map:remove_players_in_group(group)
    local g = get_map_state(self).players_by_group[group]
    if not g then return end

    for key in pairs(g) do
        self:remove_player(key)
    end

    get_map_state(self).players_by_group[group] = nil
end

function Map:add_player_to_group(key, group)
    local player = get_map_state(self).players[key]
    assert(player, "Player not found: " .. tostring(key))

    -- Already in group? Do nothing
    if player.groups[group] then
        return false
    end

    -- Create group table if missing
    get_map_state(self).players_by_group[group] = get_map_state(self).players_by_group[group] or {}

    -- Add player to group
    get_map_state(self).players_by_group[group][key] = true
    player.groups[group] = true

    return true
end

function Map:remove_player_from_group(key, group)
    local player = get_map_state(self).players[key]
    if not player then return end

    if player.groups[group] then
        player.groups[group] = nil
    end

    local g = get_map_state(self).players_by_group[group]
    if g then
        g[key] = nil
        if next(g) == nil then
            get_map_state(self).players_by_group[group] = nil
        end
    end
end

function Map:destroy()
    -- destroy players
    for key, player in pairs(get_map_state(self).players) do
        if player.destroy then
            player:destroy()
        end
        get_map_state(self).players[key] = nil
    end

    -- clear player groups
    for group, list in pairs(get_map_state(self).players_by_group) do
        get_map_state(self).players_by_group[group] = nil
    end

    -- clear nodes
    for id, node in pairs(get_map_state(self).map_node_list) do
        get_map_state(self).map_node_list[id] = nil
    end

    get_map_state(self).node_registry  = {}
    get_map_state(self).nodes_by_group = {}

    -- clear map internals
    get_map_state(self).map_route_list   = {}
    get_map_state(self).pathfinder_cache = {}
    get_map_state(self).node_version     = {}
    get_map_state(self).route_version    = {}

    self._destroyed = true

    -- remove hidden state fully
    map_state[self] = nil
end


function Map:is_player_in_group(key, group)
    local player = get_map_state(self).players[key]
    if not player then
        return false
    end

    -- player.groups is a set: { groupName = true }
    return player.groups and player.groups[group] == true
end

function Map:debug_draw_group(group, color, show_projection, show_dirs, show_snap)
    local g = get_map_state(self).players_by_group[group]
    if not g then return end

    for key in pairs(g) do
        local player = get_map_state(self).players[key]
        if player then
            player:debug_draw(color, show_projection, show_dirs, show_snap)
        end
    end
end

function Map:debug_draw_groups(groups, color, show_projection, show_dirs, show_snap)
    local visited = {}

    for i = 1, #groups do
        local group = groups[i]
        local g = get_map_state(self).players_by_group[group]

        if g then
            for key in pairs(g) do
                if not visited[key] then
                    visited[key] = true
                    local player = get_map_state(self).players[key]
                    if player then
                        player:debug_draw(color, show_projection, show_dirs, show_snap)
                    end
                end
            end
        end
    end
end

----------------------------------------------------------------------
-- Map: versioning helpers
----------------------------------------------------------------------

function Map:bump_node_version(node_id)
    local nv = get_map_state(self).node_version
    nv[node_id] = (nv[node_id] or 0) + 1
end

function Map:bump_route_version(from_id, to_id)
    local rv = get_map_state(self).route_version
    local row = rv[from_id]
    if not row then
        row = {}
        rv[from_id] = row
    end
    row[to_id] = (row[to_id] or 0) + 1
end

function Map:compute_path_version(node_ids)
    local maxv = 0
    local nv = get_map_state(self).node_version
    local rv = get_map_state(self).route_version

    for i = 1, #node_ids do
        local id = node_ids[i]
        local v = nv[id] or 0
        if v > maxv then maxv = v end
    end

    for i = 1, #node_ids - 1 do
        local a = node_ids[i]
        local b = node_ids[i + 1]
        local row = rv[a]
        local v = row and row[b] or 0
        if v > maxv then maxv = v end
    end

    return maxv
end

function Map:is_path_cache_valid(cache)
    local ids = cache.path
    local nv  = cache.node_versions
    local rv  = cache.route_versions

    local current_nv = get_map_state(self).node_version
    local current_rv = get_map_state(self).route_version

    for i = 1, #ids do
        if (current_nv[ids[i]] or 0) ~= (nv[i] or 0) then
            return false
        end
    end

    for i = 1, #ids - 1 do
        local a = ids[i]
        local b = ids[i + 1]
        local row = current_rv[a]
        local v = row and row[b] or 0
        if v ~= (rv[i] or 0) then
            return false
        end
    end

    return true
end

----------------------------------------------------------------------
-- Map modification
----------------------------------------------------------------------

function Map:update_node_position(node_id, position)
    assert(node_id, "You must provide a node id")
    assert(position, "You must provide a position")
    local map_node_list = get_map_state(self).map_node_list
    assert(map_node_list[node_id], ("Unknown node id %s"):format(tostring(node_id)))

    map_node_list[node_id].position = vmath.vector3(position.x, position.y, 0)
    local neighbors = map_node_list[node_id].neighbor_id
    local map_route_list = get_map_state(self).map_route_list

    for i = 1, #neighbors do
        local a_id = node_id
        local b_id = neighbors[i]

        for _ = 1, 2 do
            local from_pos = map_node_list[a_id].position
            local to_pos   = map_node_list[b_id].position

            local a, b, c
            if from_pos.x ~= to_pos.x then
                a = (from_pos.y - to_pos.y) / (to_pos.x - from_pos.x)
                b = 1
                c = ((from_pos.x * to_pos.y) - (to_pos.x * from_pos.y)) / (to_pos.x - from_pos.x)
            else
                a = 1
                b = 0
                c = -from_pos.x
            end

            local ab_len2    = a * a + b * b
            local inv_ab_len = 1 / sqrt(ab_len2)

            local routes_from = map_route_list[a_id]
            if routes_from and routes_from[b_id] then
                routes_from[b_id] = {
                    a          = a,
                    b          = b,
                    c          = c,
                    distance   = distance(from_pos, to_pos),
                    ab_len2    = ab_len2,
                    inv_ab_len = inv_ab_len,
                }
                self:bump_route_version(a_id, b_id)
            end

            a_id, b_id = b_id, a_id
        end
    end

    self:bump_node_version(node_id)
end

local function map_update_node_type(map, node_id)
    local map_node_list = get_map_state(map).map_node_list
    local neighbors = map_node_list[node_id].neighbor_id
    local n = #neighbors
    if n == 0 then
        map_node_list[node_id].type = NODETYPE.SINGLE
    elseif n == 1 then
        map_node_list[node_id].type = NODETYPE.DEADEND
    else
        map_node_list[node_id].type = NODETYPE.INTERSECTION
    end
end

local function map_add_oneway_route(map, source_id, destination_id, route_info, lane_count, lane_offset)
    local state         = get_map_state(map)
    local map_node_list = state.map_node_list
    local map_route_list = state.map_route_list

    local routes_from = map_route_list[source_id]
    if not routes_from then
        routes_from = {}
        map_route_list[source_id] = routes_from
    end

    lane_count  = lane_count or 1
    if lane_count < 1 then lane_count = 1 end
    lane_offset = lane_offset or DEFAULT_ROUTE_LANE_OFFSET

    -- If route already exists, update lane info and return
    if routes_from[destination_id] then
        local r = routes_from[destination_id]
        r.lane_count  = lane_count
        r.lane_offset = lane_offset
        map:bump_route_version(source_id, destination_id)
        return r
    end

    -- Build new route info if not provided
    if not route_info then
        local from_pos = map_node_list[source_id].position
        local to_pos   = map_node_list[destination_id].position

        local a, b, c
        if from_pos.x ~= to_pos.x then
            a = (from_pos.y - to_pos.y) / (to_pos.x - from_pos.x)
            b = 1
            c = ((from_pos.x * to_pos.y) - (to_pos.x * from_pos.y)) / (to_pos.x - from_pos.x)
        else
            a = 1
            b = 0
            c = -from_pos.x
        end

        local ab_len2    = a * a + b * b
        local inv_ab_len = 1 / math.sqrt(ab_len2)

        route_info = {
            a          = a,
            b          = b,
            c          = c,
            distance   = distance(from_pos, to_pos),
            ab_len2    = ab_len2,
            inv_ab_len = inv_ab_len,
            lane_count = lane_count,
            lane_offset = lane_offset,
        }
    else
        -- Reused route_info (two-way), ensure lane info is set
        route_info.lane_count  = lane_count
        route_info.lane_offset = lane_offset
    end

    routes_from[destination_id] = route_info

    -- Update neighbor lists
    local src_neighbors = map_node_list[source_id].neighbor_id
    local dst_neighbors = map_node_list[destination_id].neighbor_id

    local found = false
    for i = 1, #src_neighbors do
        if src_neighbors[i] == destination_id then
            found = true
            break
        end
    end
    if not found then
        src_neighbors[#src_neighbors + 1] = destination_id
    end

    found = false
    for i = 1, #dst_neighbors do
        if dst_neighbors[i] == source_id then
            found = true
            break
        end
    end
    if not found then
        dst_neighbors[#dst_neighbors + 1] = source_id
    end

    map:bump_route_version(source_id, destination_id)
    return route_info
end

local function map_remove_oneway_route(map, source_id, destination_id)
    local map_node_list  = get_map_state(map).map_node_list
    local map_route_list = get_map_state(map).map_route_list

    local routes_from = map_route_list[source_id]
    if not routes_from then return end

    routes_from[destination_id] = nil
    if next(routes_from) == nil then
        map_route_list[source_id] = nil
    end

    local routes_to = map_route_list[destination_id]
    if not (routes_to and routes_to[source_id]) then
        local dst_neighbors = map_node_list[destination_id].neighbor_id
        for i = 1, #dst_neighbors do
            if dst_neighbors[i] == source_id then
                table.remove(dst_neighbors, i)
                break
            end
        end

        local src_neighbors = map_node_list[source_id].neighbor_id
        for i = 1, #src_neighbors do
            if src_neighbors[i] == destination_id then
                table.remove(src_neighbors, i)
                break
            end
        end
    end

    map:bump_route_version(source_id, destination_id)
end

----------------------------------------------------------------------
-- Map: node creation
----------------------------------------------------------------------
function Map:create_node(position, key, groups)
    -- key is optional
    if key ~= nil then
        assert(type(key) == "string" or type(key) == "userdata",
            "Map:create_node: key must be a string or hash")
    end

    -- required vector3
    assert(position and type(position) == "userdata",
        "Map:create_node: position must be a vmath.vector3")

    -- optional groups
    if groups ~= nil then
        assert(type(groups) == "table",
            "Map:create_node: groups must be a list of strings")
        for i = 1, #groups do
            assert(type(groups[i]) == "string",
                "Map:create_node: group names must be strings")
        end
    end

    ------------------------------------------------------------------
    -- Generate node id
    ------------------------------------------------------------------
    get_map_state(self).map_node_id_iter = get_map_state(self).map_node_id_iter + 1
    local id = get_map_state(self).map_node_id_iter

    ------------------------------------------------------------------
    -- Auto-generate key if missing
    ------------------------------------------------------------------
    if key == nil then
        key = "defgraph_default_node_key_" .. tostring(id)
    end

    ------------------------------------------------------------------
    -- Create node object
    ------------------------------------------------------------------
    local node = Node.new(id, key, position, NODETYPE.SINGLE)

    ------------------------------------------------------------------
    -- Register node
    ------------------------------------------------------------------
    get_map_state(self).map_node_list[id] = node
    get_map_state(self).node_registry[key] = node

    ------------------------------------------------------------------
    -- Assign groups
    ------------------------------------------------------------------
    if groups then
        for i = 1, #groups do
            local group = groups[i]
            node.groups[group] = true

            get_map_state(self).nodes_by_group[group] = get_map_state(self).nodes_by_group[group] or {}
            get_map_state(self).nodes_by_group[group][id] = true
        end
    end

    ------------------------------------------------------------------
    -- Version bump
    ------------------------------------------------------------------
    self:bump_node_version(id)

    return id
end

function Map:create_node_xy(x, y, key, groups)
    assert(type(x) == "number" and type(y) == "number",
        "Map:create_node_xy: x and y must be numbers")

    local position = vmath.vector3(x, y, 0)

    return self:create_node(position, key, groups)
end


function Map:add_node(position)
    assert(position, "You must provide a position")

    get_map_state(self).map_node_id_iter = get_map_state(self).map_node_id_iter + 1
    local node_id = get_map_state(self).map_node_id_iter

    get_map_state(self).map_node_list[node_id] = {
        position    = vmath.vector3(position.x, position.y, 0),
        type        = NODETYPE.SINGLE,
        neighbor_id = {},
    }

    self:bump_node_version(node_id)
    return node_id
end

function Map:add_route(source_id, destination_id, is_one_way, lane_count, lane_offset)
    assert(source_id, "You must provide a source id")
    assert(destination_id, "You must provide a destination id")

    local map_node_list = get_map_state(self).map_node_list
    assert(map_node_list[source_id], ("Unknown source id %s"):format(tostring(source_id)))
    assert(map_node_list[destination_id], ("Unknown destination id %s"):format(tostring(destination_id)))

    if source_id == destination_id then
        return
    end

    -- defaults
    lane_count  = lane_count or 1
    if lane_count < 1 then lane_count = 1 end
    lane_offset = lane_offset or DEFAULT_ROUTE_LANE_OFFSET

    -- create forward route
    local route_info = map_add_oneway_route(self, source_id, destination_id, nil, lane_count, lane_offset)

    -- create reverse route if not one-way
    if not is_one_way then
        map_add_oneway_route(self, destination_id, source_id, route_info, lane_count, lane_offset)
    end

    map_update_node_type(self, source_id)
    map_update_node_type(self, destination_id)

    self:bump_node_version(source_id)
    self:bump_node_version(destination_id)
end

function Map:remove_route(source_id, destination_id, is_remove_one_way)
    assert(source_id, "You must provide a source id")
    assert(destination_id, "You must provide a destination id")
    local map_node_list = get_map_state(self).map_node_list
    assert(map_node_list[source_id], ("Unknown source id %s"):format(tostring(source_id)))
    assert(map_node_list[destination_id], ("Unknown destination id %s"):format(tostring(destination_id)))

    if source_id == destination_id then return end

    map_remove_oneway_route(self, source_id, destination_id)
    if not is_remove_one_way then
        map_remove_oneway_route(self, destination_id, source_id)
    end

    map_update_node_type(self, source_id)
    map_update_node_type(self, destination_id)

    self:bump_node_version(source_id)
    self:bump_node_version(destination_id)
end

function Map:remove_node(node_id)
    assert(node_id, "You must provide a node id")

    local map_node_list  = get_map_state(self).map_node_list
    local map_route_list = get_map_state(self).map_route_list

    local node = map_node_list[node_id]
    assert(node, ("Unknown node id %s"):format(tostring(node_id)))

    ------------------------------------------------------------------
    -- 1. Remove from all node groups
    ------------------------------------------------------------------
    if node.groups then
        for group in pairs(node.groups) do
            local g = get_map_state(self).nodes_by_group[group]
            if g then
                g[node_id] = nil
                if next(g) == nil then
                    get_map_state(self).nodes_by_group[group] = nil
                end
            end
        end
    end

    ------------------------------------------------------------------
    -- 2. Remove from node registry
    ------------------------------------------------------------------
    if node.key then
        get_map_state(self).node_registry[node.key] = nil
    end

    ------------------------------------------------------------------
    -- 3. Remove all routes touching this node
    ------------------------------------------------------------------
    local to_remove = {}

    for from_id, routes in pairs(map_route_list) do
        for to_id in pairs(routes) do
            if from_id == node_id or to_id == node_id then
                to_remove[#to_remove + 1] = { from_id = from_id, to_id = to_id }
            end
        end
    end

    for i = 1, #to_remove do
        local from_id = to_remove[i].from_id
        local to_id   = to_remove[i].to_id

        map_remove_oneway_route(self, from_id, to_id)

        if map_node_list[from_id] then map_update_node_type(self, from_id) end
        if map_node_list[to_id]   then map_update_node_type(self, to_id)   end

        self:bump_node_version(from_id)
        self:bump_node_version(to_id)
    end

    ------------------------------------------------------------------
    -- 4. Remove the node itself
    ------------------------------------------------------------------
    map_node_list[node_id] = nil
    self:bump_node_version(node_id)

    ------------------------------------------------------------------
    -- 5. Clear pathfinder cache (paths may contain this node)
    ------------------------------------------------------------------
    get_map_state(self).pathfinder_cache = {}
end

----------------------------------------------------------------------
-- Nearest route
----------------------------------------------------------------------

function Map:calculate_to_nearest_route(position)
    local map_node_list  = get_map_state(self).map_node_list
    local map_route_list = get_map_state(self).map_route_list

    local min_from, min_to
    local min_x, min_y
    local min_dist = huge

    local visited = {}

    for from_id, routes in pairs(map_route_list) do
        for to_id, route in pairs(routes) do
            local row = visited[from_id]
            if not (row and row[to_id]) then
                local from_pos = map_node_list[from_id].position
                local to_pos   = map_node_list[to_id].position

                local near_x, near_y
                local is_between

                if from_pos.x ~= to_pos.x then
                    local ab_len2 = route.ab_len2 or (route.a * route.a + route.b * route.b)
                    route.ab_len2 = ab_len2
                    local bx_ax   = (route.b * position.x) - (route.a * position.y)

                    near_x = (route.b * bx_ax - route.a * route.c) / ab_len2
                    near_y = (route.a * (-route.b * position.x + route.a * position.y) - route.b * route.c) / ab_len2
                else
                    near_x = from_pos.x
                    near_y = position.y
                end

                if abs(to_pos.x - from_pos.x) >= abs(to_pos.y - from_pos.y) then
                    if to_pos.x > from_pos.x then
                        is_between = (from_pos.x <= near_x and near_x <= to_pos.x)
                    else
                        is_between = (to_pos.x <= near_x and near_x <= from_pos.x)
                    end
                else
                    if to_pos.y > from_pos.y then
                        is_between = (from_pos.y <= near_y and near_y <= to_pos.y)
                    else
                        is_between = (to_pos.y <= near_y and near_y <= from_pos.y)
                    end
                end

                local dist
                if is_between then
                    local inv_len = route.inv_ab_len
                    if not inv_len then
                        local ab_len2 = route.ab_len2 or (route.a * route.a + route.b * route.b)
                        inv_len = 1 / sqrt(ab_len2)
                        route.ab_len2    = ab_len2
                        route.inv_ab_len = inv_len
                    end
                    dist = abs(route.a * position.x + route.b * position.y + route.c) * inv_len
                else
                    local d1 = distance(position, from_pos)
                    local d2 = distance(position, to_pos)
                    dist = (d1 < d2) and d1 or d2
                end

                if dist < min_dist then
                    min_dist = dist
                    if is_between then
                        min_x, min_y = near_x, near_y
                    else
                        if distance(position, from_pos) < distance(position, to_pos) then
                            min_x, min_y = from_pos.x, from_pos.y
                        else
                            min_x, min_y = to_pos.x, to_pos.y
                        end
                    end
                    min_from, min_to = from_id, to_id
                end

                if not row then
                    row = {}
                    visited[from_id] = row
                end
                row[to_id] = true

                -- also mark reverse to avoid recomputing the same undirected segment
                local rev = visited[to_id]
                if not rev then
                    rev = {}
                    visited[to_id] = rev
                end
                rev[from_id] = true
            end
        end
    end

    if min_dist == huge then
        return nil
    end

    return {
        position_on_route = vmath.vector3(min_x, min_y, 0),
        distance          = min_dist,
        route_from_id     = min_from,
        route_to_id       = min_to,
    }
end
local function compute_lane_center_offset(lane_index, lane_count, lane_offset)
    if lane_count <= 1 then
        return 0
    end
    -- lane_offset is distance between lane centers
    local center = (lane_count + 1) * 0.5
    return (lane_index - center) * lane_offset
end

local function ensure_player_lane_state(self_player, route_info)
    -- Initialize lane index if needed
    if not self_player._lane_index or self_player._lane_index < 1 or self_player._lane_index > (route_info.lane_count or 1) then
        local lc = route_info.lane_count or 1
        if lc <= 1 then
            self_player._lane_index = 1
        else
            -- deterministic initial lane based on id
            self_player._lane_index = (self_player.id % lc) + 1
        end
    end

    local lane_count  = route_info.lane_count or 1
    local lane_offset = route_info.lane_offset or DEFAULT_ROUTE_LANE_OFFSET
    local target = compute_lane_center_offset(self_player._lane_index, lane_count, lane_offset)

    if self_player._lane_target_offset == nil then
        self_player._lane_target_offset = target
    else
        self_player._lane_target_offset = target
    end

    if self_player._lane_current_offset == nil then
        self_player._lane_current_offset = self_player._lane_target_offset
    end

    if self_player._lane_switch_cooldown == nil then
        self_player._lane_switch_cooldown = 0
    end
end

local function apply_soft_lane_offset(self_player)
    local current = self_player._lane_current_offset or 0
    local target  = self_player._lane_target_offset or 0
    local factor  = 0.15  -- soft switching factor per update

    local new = current + (target - current) * factor
    self_player._lane_current_offset = new
    return new
end

local function compute_lane_switch_cooldown(speed, lane_count)
    local base       = 20.0   -- base in "ticks"
    local speed_fac  = 0.05   -- more speed → less cooldown
    local lane_fac   = 0.25   -- more lanes → less cooldown

    local denom = 1 + speed * speed_fac
    denom = denom * (1 + (lane_count - 1) * lane_fac)

    local ticks = base / denom
    if ticks < 5 then ticks = 5 end
    return ticks
end

local function compute_lane_pressure_for_index(state, lane_index, route_info)
    -- Simple lane pressure: count players whose lane_index == lane_index
    local players = state.players
    local count = 0
    for _, p in pairs(players) do
        if p._lane_index == lane_index then
            count = count + 1
        end
    end
    return count
end

local function attempt_lane_switch(map, self_player, route_info, blocked_ahead, slower_ahead, speed)
    local lane_count = route_info.lane_count or 1
    if lane_count <= 1 then
        return
    end

    if not blocked_ahead and not slower_ahead then
        return
    end

    if self_player._lane_switch_cooldown and self_player._lane_switch_cooldown > 0 then
        return
    end

    local state = get_map_state(map)
    local current_lane = self_player._lane_index or 1

    local best_lane = current_lane
    local best_pressure = compute_lane_pressure_for_index(state, current_lane, route_info)

    -- check adjacent lanes
    for delta = -1, 1 do
        if delta ~= 0 then
            local candidate = current_lane + delta
            if candidate >= 1 and candidate <= lane_count then
                local pressure = compute_lane_pressure_for_index(state, candidate, route_info)
                if pressure < best_pressure then
                    best_pressure = pressure
                    best_lane = candidate
                end
            end
        end
    end

    if best_lane ~= current_lane then
        self_player._lane_index = best_lane
        local lc  = route_info.lane_count or 1
        local lof = route_info.lane_offset or DEFAULT_ROUTE_LANE_OFFSET
        self_player._lane_target_offset = compute_lane_center_offset(best_lane, lc, lof)
        self_player._lane_switch_cooldown = compute_lane_switch_cooldown(speed, lc)
    end
end

----------------------------------------------------------------------
-- Pathfinding
----------------------------------------------------------------------
function Map:calculate_path(start_id, finish_id)
    local map_node_list  = get_map_state(self).map_node_list
    local map_route_list = get_map_state(self).map_route_list

    local previous  = {}
    local distances = {}
    local visited   = {}
    local heap      = {}

    for node_id in pairs(map_node_list) do
        distances[node_id] = huge
    end

    distances[start_id] = 0
    heap_push(heap, start_id, 0)

    while true do
        local current, current_dist = heap_pop(heap)
        if not current then
            return nil
        end

        if current_dist == huge then
            return nil
        end

        if not visited[current] then
            visited[current] = true

            if current == finish_id then
                local path  = {}
                local total = 0
                local node  = finish_id

                while previous[node] do
                    path[1] = { id = node, distance = total }
                    local prev  = previous[node]
                    local route = map_route_list[prev] and map_route_list[prev][node]
                    if not route then return nil end
                    total = total + route.distance
                    node  = prev
                    table.insert(path, 1, { id = node, distance = total })
                end

                if #path == 0 then
                    path[1] = { id = node, distance = total }
                end

                return path
            end

            local neighbors = map_route_list[current]
            if neighbors then
                for to_id, route in pairs(neighbors) do
                    local alt = current_dist + route.distance
                    if alt < distances[to_id] then
                        distances[to_id] = alt
                        previous[to_id]  = current
                        heap_push(heap, to_id, alt)
                    end
                end
            end
        end
    end
end

function Map:fetch_path(from_id, to_id)
    local pathfinder_cache = get_map_state(self).pathfinder_cache

    if from_id == to_id then
        local ids = { from_id }
        local node_versions = { get_map_state(self).node_version[from_id] or 0 }
        local route_versions = {}
        return {
            distance       = 0,
            path           = ids,
            node_versions  = node_versions,
            route_versions = route_versions,
        }
    end

    local row = pathfinder_cache[from_id]
    if row then
        local cache = row[to_id]
        if cache and self:is_path_cache_valid(cache) then
            return cache
        end
    end

    local path_nodes = self:calculate_path(from_id, to_id)
    if not path_nodes or #path_nodes == 0 then
        return nil
    end

    -- Build route from start to finish once
    local route = {}
    local route_count = #path_nodes
    for i = 1, route_count do
        route[i] = path_nodes[i].id
    end

    -- Ensure row exists for from_id
    row = pathfinder_cache[from_id]
    if not row then
        row = {}
        pathfinder_cache[from_id] = row
    end

    -- For each node with non-zero distance, cache subpath to 'to_id'
    for index = route_count, 1, -1 do
        local node = path_nodes[index]
        if node.distance ~= 0 then
            local nid = node.id

            local cache_row = pathfinder_cache[nid]
            if not cache_row then
                cache_row = {}
                pathfinder_cache[nid] = cache_row
            end

            -- Copy subpath [index .. route_count] into a fresh array
            local sub_len = route_count - index + 1
            local node_ids = {}
            for j = 1, sub_len do
                node_ids[j] = route[index + j - 1]
            end

            local node_versions = {}
            local route_versions = {}

            for j = 1, sub_len do
                local id = node_ids[j]
                node_versions[j] = get_map_state(self).node_version[id] or 0
            end

            for j = 1, sub_len - 1 do
                local a = node_ids[j]
                local b = node_ids[j + 1]
                local rv_row = get_map_state(self).route_version[a]
                route_versions[j] = rv_row and rv_row[b] or 0
            end

            cache_row[to_id] = {
                distance       = node.distance,
                path           = node_ids,
                node_versions  = node_versions,
                route_versions = route_versions,
            }
        end
    end

    return pathfinder_cache[from_id][to_id]
end

----------------------------------------------------------------------
-- Path curvature
----------------------------------------------------------------------
local function process_path_curvature(before, current, after, roundness,
                                      path_curve_tightness,
                                      path_curve_max_distance_from_corner,
                                      out_list)
    out_list = out_list or {}

    local Q_before = (path_curve_tightness - 1) / path_curve_tightness * before +
                     current / path_curve_tightness
    local R_before = before / path_curve_tightness +
                     (path_curve_tightness - 1) / path_curve_tightness * current
    local Q_after  = (path_curve_tightness - 1) / path_curve_tightness * current +
                     after / path_curve_tightness
    local R_after  = current / path_curve_tightness +
                     (path_curve_tightness - 1) / path_curve_tightness * after

    -- NEW: guard zero-length segments and reuse distances
    local bc_dist = distance(before, current)
    local ca_dist = distance(current, after)

    if bc_dist > 0 then
        if distance(Q_before, before) > path_curve_max_distance_from_corner then
            Q_before = vmath.lerp(path_curve_max_distance_from_corner / bc_dist, before, current)
        end
        if distance(R_before, current) > path_curve_max_distance_from_corner then
            R_before = vmath.lerp(path_curve_max_distance_from_corner / bc_dist, current, before)
        end
    end

    if ca_dist > 0 then
        if distance(Q_after, current) > path_curve_max_distance_from_corner then
            Q_after = vmath.lerp(path_curve_max_distance_from_corner / ca_dist, current, after)
        end
        if distance(R_after, after) > path_curve_max_distance_from_corner then
            R_after = vmath.lerp(path_curve_max_distance_from_corner / ca_dist, after, current)
        end
    end

    if roundness ~= 1 then
        process_path_curvature(Q_before, R_before, Q_after, roundness - 1,
                               path_curve_tightness,
                               path_curve_max_distance_from_corner,
                               out_list)
        process_path_curvature(R_before, Q_after, R_after, roundness - 1,
                               path_curve_tightness,
                               path_curve_max_distance_from_corner,
                               out_list)
        return out_list, Q_before, R_after
    else
        out_list[#out_list + 1] = R_before
        out_list[#out_list + 1] = Q_after
        return out_list, Q_before, R_after
    end
end

----------------------------------------------------------------------
-- Movement initialization
----------------------------------------------------------------------
function Map:move_internal_initialize(source_position, move_data)
    local near_result = self:calculate_to_nearest_route(source_position)
    if not near_result or #move_data.destination_list == 0 then
        move_data.path_index = 0
        local path = move_data.path
        for i = 1, #path do path[i] = nil end
        move_data.path_node_ids = {}
        move_data.path_version  = 0
        return move_data
    end

    local state          = get_map_state(self)
    local map_route_list = state.map_route_list
    local map_node_list  = state.map_node_list

    local from_path, to_path

    if map_route_list[near_result.route_to_id] and map_route_list[near_result.route_to_id][near_result.route_from_id] then
        from_path = self:fetch_path(
            near_result.route_from_id,
            move_data.destination_list[move_data.destination_index]
        )
    end
    if map_route_list[near_result.route_from_id] and map_route_list[near_result.route_from_id][near_result.route_to_id] then
        to_path = self:fetch_path(
            near_result.route_to_id,
            move_data.destination_list[move_data.destination_index]
        )
    end

    local position_list = {}
    local node_ids_list = {}

    -- source position is already a value, but copy for safety/consistency
    position_list[1] = vmath.vector3(source_position.x, source_position.y, source_position.z)
    local pos_count = 1

    if (near_result.distance > move_data.config.gameobject_threshold + 1)
        and move_data.config.allow_enter_on_route then
        pos_count = pos_count + 1
        local p = near_result.position_on_route
        position_list[pos_count] = vmath.vector3(p.x, p.y, p.z)
    end

    if from_path or to_path then
        local from_distance = math.huge
        local to_distance   = math.huge

        local from_node_pos = map_node_list[near_result.route_from_id].position
        local to_node_pos   = map_node_list[near_result.route_to_id].position

        if from_path then
            from_distance = from_path.distance + distance(source_position, from_node_pos)
        end
        if to_path then
            to_distance = to_path.distance + distance(source_position, to_node_pos)
        end

        if from_distance <= to_distance then
            pos_count = pos_count + 1
            do
                local p = from_node_pos
                position_list[pos_count] = vmath.vector3(p.x, p.y, p.z)
            end
            node_ids_list[#node_ids_list + 1] = near_result.route_from_id

            local fp = from_path.path
            -- skip first node (same as from_node_pos)
            for i = 2, #fp do
                pos_count = pos_count + 1
                local np = map_node_list[fp[i]].position
                position_list[pos_count] = vmath.vector3(np.x, np.y, np.z)
                node_ids_list[#node_ids_list + 1] = fp[i]
            end
        else
            pos_count = pos_count + 1
            do
                local p = to_node_pos
                position_list[pos_count] = vmath.vector3(p.x, p.y, p.z)
            end
            node_ids_list[#node_ids_list + 1] = near_result.route_to_id

            local tp = to_path.path
            -- skip first node (same as to_node_pos)
            for i = 2, #tp do
                pos_count = pos_count + 1
                local np = map_node_list[tp[i]].position
                position_list[pos_count] = vmath.vector3(np.x, np.y, np.z)
                node_ids_list[#node_ids_list + 1] = tp[i]
            end
        end
    end

    ----------------------------------------------------------------------
    -- Lane assignment + lateral offset per segment (before curvature)
    ----------------------------------------------------------------------
    if pos_count > 1 and #node_ids_list > 0 then
        -- Use the first route to initialize lane state
        local first_from  = node_ids_list[1]
        local first_to    = node_ids_list[2] or node_ids_list[1]
        local routes_from = map_route_list[first_from]
        local route_info  = routes_from and routes_from[first_to]

        if route_info then
            ensure_player_lane_state(move_data, route_info)
            local lane_current_offset = apply_soft_lane_offset(move_data)

            if lane_current_offset ~= 0 then
                local node_index = 1
                for i = 1, pos_count - 1 do
                    local p1 = position_list[i]
                    local p2 = position_list[i + 1]

                    local dx = p2.x - p1.x
                    local dy = p2.y - p1.y
                    local len = math.sqrt(dx * dx + dy * dy)

                    if len > 0 then
                        local id1 = node_ids_list[node_index]
                        local id2 = node_ids_list[node_index + 1]

                        local rinfo = nil
                        if id1 and id2 then
                            local rf = map_route_list[id1]
                            rinfo = rf and rf[id2]
                        end

                        local lc  = (rinfo and rinfo.lane_count)  or (route_info.lane_count or 1)
                        local lof = (rinfo and rinfo.lane_offset) or (route_info.lane_offset or DEFAULT_ROUTE_LANE_OFFSET)

                        local lane_center = compute_lane_center_offset(move_data._lane_index or 1, lc, lof)
                        local offset = lane_center

                        local nx = -dy / len
                        local ny =  dx / len

                        p1.x = p1.x + nx * offset
                        p1.y = p1.y + ny * offset
                        p2.x = p2.x + nx * offset
                        p2.y = p2.y + ny * offset

                        if rinfo then
                            node_index = node_index + 1
                        end
                    end
                end
            end
        end
    end

    ----------------------------------------------------------------------
    -- Curvature generation
    ----------------------------------------------------------------------
    local path = move_data.path
    for i = 1, #path do path[i] = nil end

    if move_data.config.path_curve_roundness ~= 0 and pos_count > 2 then
        path[1] = position_list[1]
        local path_count = 1

        for i = 2, pos_count - 1 do
            local curve_temp = move_data._curve_temp or {}
            move_data._curve_temp = curve_temp
            for k = 1, #curve_temp do curve_temp[k] = nil end

            local partial_position_list, Q_before, R_after =
                process_path_curvature(
                    position_list[i - 1],
                    position_list[i],
                    position_list[i + 1],
                    move_data.config.path_curve_roundness,
                    move_data.config.path_curve_tightness,
                    move_data.config.path_curve_max_distance_from_corner,
                    curve_temp
                )

            if i == 2 then
                path_count = path_count + 1
                path[path_count] = Q_before
            end

            for k = 1, #partial_position_list do
                path_count = path_count + 1
                path[path_count] = partial_position_list[k]
            end

            if i == pos_count - 1 then
                path_count = path_count + 1
                path[path_count] = R_after
            end
        end

        path[#path + 1] = position_list[pos_count]
    else
        for i = 1, pos_count do
            path[i] = position_list[i]
        end
    end

    move_data.path_index    = 1
    move_data.path_node_ids = node_ids_list
    move_data.path_version  = self:compute_path_version(node_ids_list)

    return move_data
end

----------------------------------------------------------------------
-- Player update (map-bound)
----------------------------------------------------------------------
function Map:player_update(self_player, speed)
    assert(self_player, "You must provide defgraph move data")

    local state = get_map_state(self)
    local path       = self_player.path
    local path_index = self_player.path_index

    ----------------------------------------------------------------------
    -- Path invalidation
    ----------------------------------------------------------------------
    if path_index ~= 0 then
        local ids = self_player.path_node_ids
        if ids and #ids > 0 then
            if self:compute_path_version(ids) ~= self_player.path_version then
                self_player = self:move_internal_initialize(self_player.current_position, self_player)
                path = self_player.path
                path_index = self_player.path_index
            end
        end
    end

    ----------------------------------------------------------------------
    -- Rotation smoothing helper
    ----------------------------------------------------------------------
    local rotation = nil
    local function apply_rotation_smoothing(dir_x, dir_y)
        if not self_player.initial_angle then
            return nil
        end

        local behavior_id = self_player.config.collision_behavior or M.CollisionBehavior.Balanced
        local preset = COLLISION_BEHAVIOR_PRESETS[behavior_id]

        local cf = self_player.current_face_vector
        local rx = cf.x + (dir_x - cf.x) * preset.dir_smoothing
        local ry = cf.y + (dir_y - cf.y) * preset.dir_smoothing

        local angle = math.atan2(ry, rx)
        local prev_angle = self_player._prev_angle or angle
        local diff = angle - prev_angle

        if diff > 3.14159 then diff = diff - 6.28318 end
        if diff < -3.14159 then diff = diff + 6.28318 end

        angle = prev_angle + diff * 0.25
        self_player._prev_angle = angle

        self_player.current_face_vector.x = rx
        self_player.current_face_vector.y = ry

        return vmath.quat_rotation_z(angle - self_player.initial_angle)
    end

    ----------------------------------------------------------------------
    -- No path
    ----------------------------------------------------------------------
    if path_index == 0 then
        if self_player.initial_angle then
            local cf = self_player.current_face_vector
            rotation = apply_rotation_smoothing(cf.x, cf.y)
        end

        return {
            position       = self_player.current_position,
            rotation       = rotation,
            is_reached     = false,
            destination_id = self_player.destination_list[self_player.destination_index],
        }
    end

    ----------------------------------------------------------------------
    -- Movement loop
    ----------------------------------------------------------------------
    local threshold = self_player.config.gameobject_threshold + 1
    local threshold_sq = threshold * threshold

    local last_index = #path
    local map_node_list = state.map_node_list

    for i = path_index, last_index do
        local target = path[i]

        local vx = target.x - self_player.current_position.x
        local vy = target.y - self_player.current_position.y
        local dist_sq = vx*vx + vy*vy

        if dist_sq > threshold_sq then
            self_player.path_index = i

            local inv_len = 1 / math.sqrt(dist_sq)
            local base_dir_x = vx * inv_len
            local base_dir_y = vy * inv_len

            ------------------------------------------------------------------
            -- Unified lane + collision engine
            ------------------------------------------------------------------
            local dir_x, dir_y = base_dir_x, base_dir_y

            local behavior_id = self_player.config.collision_behavior or M.CollisionBehavior.Balanced
            local preset = COLLISION_BEHAVIOR_PRESETS[behavior_id]

            local px = self_player.current_position.x
            local py = self_player.current_position.y

            local blocked_ahead = false
            local slower_ahead  = false

            local base_radius = self_player.config.collision_radius or 0
            local my_group    = self_player.config.collision_groups or nil

            local lane_offset = DEFAULT_ROUTE_LANE_OFFSET
            local lane_count  = 1
            local route_info  = nil

            do
                local ids = self_player.path_node_ids
                if ids and #ids >= 2 then
                    local from_id = ids[1]
                    local to_id   = ids[2]
                    local routes_from = state.map_route_list[from_id]
                    route_info  = routes_from and routes_from[to_id]
                    if route_info then
                        lane_offset = route_info.lane_offset or DEFAULT_ROUTE_LANE_OFFSET
                        lane_count  = route_info.lane_count or 1
                    end
                end
            end

            ------------------------------------------------------------------
            -- Lane state ONLY (no recentering yet)
            ------------------------------------------------------------------
            if route_info then
                ensure_player_lane_state(self_player, route_info)
            end

            ------------------------------------------------------------------
            -- Collision disabled → skip avoidance
            ------------------------------------------------------------------
            if self_player.config.collision_enabled then

                local players = state.players

                local predictive_force_x = 0
                local predictive_force_y = 0
                local reactive_force_x   = 0
                local reactive_force_y   = 0

                local density_count = 0

                for _, other in pairs(players) do
                    if other ~= self_player then

                        ------------------------------------------------------------------
                        -- GROUP FILTER (list vs list)
                        ------------------------------------------------------------------
                        local other_group_list = other.config and other.config.collision_groups
                        local group_ok = false

                        if my_group == nil then
                            group_ok = true
                        elseif other_group_list then
                            for gi = 1, #my_group do
                                local g = my_group[gi]
                                for gj = 1, #other_group_list do
                                    if other_group_list[gj] == g then
                                        group_ok = true
                                        break
                                    end
                                end
                                if group_ok then break end
                            end
                        end

                        if group_ok then

                            local ox = other.current_position.x
                            local oy = other.current_position.y

                            local dx = ox - px
                            local dy = oy - py
                            local odist_sq = dx*dx + dy*dy

                            if odist_sq > 0 then
                                local my_lane    = self_player._lane_index or 1
                                local other_lane = other._lane_index or 1
                                local lane_delta = math.abs(my_lane - other_lane)

                                local effective_radius = base_radius + lane_delta * lane_offset
                                effective_radius = effective_radius * preset.density_radius_factor
                                local effective_radius_sq = effective_radius * effective_radius

                                if odist_sq < effective_radius_sq then
                                    density_count = density_count + 1

                                    local dot = dx * dir_x + dy * dir_y
                                    local is_single_lane = (lane_count == 1)

                                    if is_single_lane or dot > 0 then
                                        local odist = math.sqrt(odist_sq)

                                        local lookahead = preset.lookahead_min +
                                            (preset.lookahead_max - preset.lookahead_min) *
                                            math.min(1, speed * preset.lookahead_speed_factor)

                                        local predictive_zone = effective_radius * lookahead
                                        local reactive_zone   = effective_radius * (lookahead * 0.5)

                                        local ndx = dx / odist
                                        local ndy = dy / odist

                                        if odist < reactive_zone then
                                            blocked_ahead = true
                                            reactive_force_x = reactive_force_x - ndx * preset.reactive_scale
                                            reactive_force_y = reactive_force_y - ndy * preset.reactive_scale

                                            if other._last_speed and other._last_speed < speed then
                                                slower_ahead = true
                                            end

                                        elseif odist < predictive_zone then
                                            blocked_ahead = true
                                            predictive_force_x = predictive_force_x - ndx * preset.predictive_scale
                                            predictive_force_y = predictive_force_y - ndy * preset.predictive_scale
                                        end
                                    end
                                end
                            end
                        end
                    end
                end

                ------------------------------------------------------------------
                -- Density slowdown
                ------------------------------------------------------------------
                if density_count > 0 then
                    local density_factor = 1 - math.min(1, density_count * preset.density_slow_factor * 0.1)
                    speed = speed * density_factor
                end

                ------------------------------------------------------------------
                -- Queueing (Q1)
                ------------------------------------------------------------------
                if blocked_ahead then
                    speed = speed * preset.queue_slow
                end

                ------------------------------------------------------------------
                -- Combine steering (F2)
                ------------------------------------------------------------------
                local base_weight = math.max(0, 1 - preset.predictive_scale - preset.reactive_scale)
                local final_x = base_dir_x * base_weight + predictive_force_x + reactive_force_x
                local final_y = base_dir_y * base_weight + predictive_force_y + reactive_force_y

                local flen = math.sqrt(final_x*final_x + final_y*final_y)
                if flen > 0 then
                    final_x = final_x / flen
                    final_y = final_y / flen
                else
                    final_x = base_dir_x
                    final_y = base_dir_y
                end

                dir_x = final_x
                dir_y = final_y

                ------------------------------------------------------------------
                -- Lane switching
                ------------------------------------------------------------------
                if blocked_ahead and route_info then
                    attempt_lane_switch(self, self_player, route_info, blocked_ahead, slower_ahead, speed)
                    self_player._lane_just_switched = true
                end

                ------------------------------------------------------------------
                -- Speed smoothing
                ------------------------------------------------------------------
                if self_player._last_speed then
                    speed = self_player._last_speed + (speed - self_player._last_speed) * preset.speed_smoothing
                end
            end

            ------------------------------------------------------------------
            -- LANE RECENTERING (STRUCTURAL CHANGE)
            -- Only recenter when NOT avoiding
            ------------------------------------------------------------------
            if route_info then
                if not blocked_ahead then
                    if self_player._lane_just_switched then
                        local lc  = route_info.lane_count or 1
                        local lof = route_info.lane_offset or DEFAULT_ROUTE_LANE_OFFSET
                        local center = compute_lane_center_offset(self_player._lane_index or 1, lc, lof)

                        self_player._lane_target_offset =
                            self_player._lane_target_offset +
                            (center - self_player._lane_target_offset) * preset.path_recentering

                        self_player._lane_just_switched = false
                    end
                end

                local lane_current_offset = apply_soft_lane_offset(self_player)

                if lane_current_offset ~= 0 then
                    local nx = -dir_y
                    local ny =  dir_x
                    local nlen = math.sqrt(nx*nx + ny*ny)
                    if nlen > 0 then
                        nx = nx / nlen
                        ny = ny / nlen
                        px = px + nx * lane_current_offset
                        py = py + ny * lane_current_offset
                    end
                end
            end

            ------------------------------------------------------------------
            -- Rotation smoothing
            ------------------------------------------------------------------
            if self_player.initial_angle then
                rotation = apply_rotation_smoothing(dir_x, dir_y)
            end

            ------------------------------------------------------------------
            -- Move player
            ------------------------------------------------------------------
            local new_x = self_player.current_position.x + dir_x * speed
            local new_y = self_player.current_position.y + dir_y * speed

            self_player.current_position.x = new_x
            self_player.current_position.y = new_y

            self_player._last_dir_x = dir_x
            self_player._last_dir_y = dir_y
            self_player._last_speed = speed

            return {
                position       = vmath.vector3(new_x, new_y, 0),
                rotation       = rotation,
                is_reached     = false,
                destination_id = self_player.destination_list[self_player.destination_index],
            }
        end

        ----------------------------------------------------------------------
        -- Destination reached
        ----------------------------------------------------------------------
        if i == last_index then
            local dest_id  = self_player.destination_list[self_player.destination_index]
            local dest_pos = map_node_list[dest_id].position

            local dx = self_player.current_position.x - dest_pos.x
            local dy = self_player.current_position.y - dest_pos.y
            local is_reached = (dx*dx + dy*dy <= threshold_sq)

            if self_player.initial_angle then
                local cf = self_player.current_face_vector
                rotation = apply_rotation_smoothing(cf.x, cf.y)
            end

            if is_reached then
                local count = #self_player.destination_list
                local rt = self_player.route_type

                if rt == M.ROUTETYPE.ONETIME then
                    if self_player.destination_index < count then
                        self_player.destination_index = self_player.destination_index + 1
                        self_player = self:move_internal_initialize(self_player.current_position, self_player)
                    end

                elseif rt == M.ROUTETYPE.SHUFFLE then
                    if count > 1 then
                        local new_id = self_player.destination_index
                        repeat
                            new_id = math.random(count)
                        until new_id ~= self_player.destination_index
                        self_player.destination_index = new_id
                        self_player = self:move_internal_initialize(self_player.current_position, self_player)
                    end

                elseif rt == M.ROUTETYPE.CYCLE then
                    if self_player.destination_index < count then
                        self_player.destination_index = self_player.destination_index + 1
                    else
                        self_player.destination_index = 1
                    end
                    self_player = self:move_internal_initialize(self_player.current_position, self_player)
                end
            end

            return {
                position       = self_player.current_position,
                rotation       = rotation,
                is_reached     = is_reached,
                destination_id = dest_id,
            }
        end
    end
end

----------------------------------------------------------------------
-- Debug: map nodes
----------------------------------------------------------------------

function Map:debug_set_properties(node_color, two_way_route_color, one_way_route_color, draw_scale)
    debug_node_color          = default(node_color, debug_node_color)
    debug_two_way_route_color = default(two_way_route_color, debug_two_way_route_color)
    debug_one_way_route_color = default(one_way_route_color, debug_one_way_route_color)
    debug_draw_scale          = default(draw_scale, debug_draw_scale)
end

function Map:debug_draw_map_nodes(is_show_ids, is_show_meta)
    local s = debug_draw_scale

    local up     = vmath.vector3(0,  s, 0)
    local down   = vmath.vector3(0, -s, 0)
    local left   = vmath.vector3(-s, 0, 0)
    local right  = vmath.vector3( s, 0, 0)
    local diag   = vmath.vector3( s,  s, 0)
    local ndiag  = vmath.vector3(-s, -s, 0)

    -- FIX: Use fixed pixel offsets so text never overlaps
    local text_dy = vmath.vector3(0, -14, 0)    -- 14px down per line

    for node_id, node in pairs(get_map_state(self).map_node_list) do
        local p = node.position

        ------------------------------------------------------------------
        -- Draw node ID
        ------------------------------------------------------------------
        if is_show_ids then
            msg.post("@render:", "draw_text", {
                text = tostring(node_id),
                position = p + diag
            })
        end

        ------------------------------------------------------------------
        -- Draw node key + groups (stacked, fixed spacing)
        ------------------------------------------------------------------
        if is_show_meta then
            -- Key
            local key_text
            if node.key and type(node.key) == "string"
               and node.key:sub(1, 26) == "defgraph_default_node_key_" then
                key_text = "(no key)"
            else
                key_text = node.key and tostring(node.key) or "(no key)"
            end

            -- Groups
            local groups_text = "(no groups)"
            if node.groups and next(node.groups) ~= nil then
                local tmp = {}
                for g in pairs(node.groups) do
                    tmp[#tmp+1] = g
                end
                table.sort(tmp)
                groups_text = table.concat(tmp, ", ")
            end

            -- Draw key (first line)
            msg.post("@render:", "draw_text", {
                text = key_text,
                position = p + text_dy * 1
            })

            -- Draw groups (second line)
            msg.post("@render:", "draw_text", {
                text = groups_text,
                position = p + text_dy * 2
            })
        end

        ------------------------------------------------------------------
        -- Draw node shape
        ------------------------------------------------------------------
        if node.type == NODETYPE.SINGLE then
            msg.post("@render:", "draw_line", { start_point = p + up,    end_point = p + left,  color = debug_node_color })
            msg.post("@render:", "draw_line", { start_point = p + left,  end_point = p + right, color = debug_node_color })
            msg.post("@render:", "draw_line", { start_point = p + right, end_point = p + up,    color = debug_node_color })

        elseif node.type == NODETYPE.DEADEND then
            msg.post("@render:", "draw_line", { start_point = p + diag,  end_point = p + ndiag, color = debug_node_color })
            msg.post("@render:", "draw_line", { start_point = p + vmath.vector3(-s, s, 0), end_point = p + vmath.vector3(s, -s, 0), color = debug_node_color })

        elseif node.type == NODETYPE.INTERSECTION then
            msg.post("@render:", "draw_line", { start_point = p + left + up,    end_point = p + right + up,    color = debug_node_color })
            msg.post("@render:", "draw_line", { start_point = p + right + up,   end_point = p + right + down,  color = debug_node_color })
            msg.post("@render:", "draw_line", { start_point = p + right + down, end_point = p + left + down,   color = debug_node_color })
            msg.post("@render:", "draw_line", { start_point = p + left + down,  end_point = p + left + up,     color = debug_node_color })
        end
    end
end


function Map:debug_draw_map_routes()
    local arrow = 6
    local a1 = vmath.vector3( arrow,  arrow, 0)
    local a2 = vmath.vector3( arrow, -arrow, 0)
    local a3 = vmath.vector3(-arrow,  arrow, 0)
    local a4 = vmath.vector3(-arrow, -arrow, 0)

    local map_node_list  = get_map_state(self).map_node_list
    local map_route_list = get_map_state(self).map_route_list

    for from_id, routes in pairs(map_route_list) do
        local p1 = map_node_list[from_id].position

        for to_id in pairs(routes) do
            local p2 = map_node_list[to_id].position

            if map_route_list[to_id] and map_route_list[to_id][from_id] then
                msg.post("@render:", "draw_line", {
                    start_point = p1,
                    end_point   = p2,
                    color       = debug_two_way_route_color
                })
            else
                msg.post("@render:", "draw_line", {
                    start_point = p1,
                    end_point   = p2,
                    color       = debug_one_way_route_color
                })

                local arrow_pos = p1 * 0.2 + p2 * 0.8

                msg.post("@render:", "draw_line", { start_point = arrow_pos + a1, end_point = arrow_pos + a2, color = debug_one_way_route_color })
                msg.post("@render:", "draw_line", { start_point = arrow_pos + a3, end_point = arrow_pos + a4, color = debug_one_way_route_color })
                msg.post("@render:", "draw_line", { start_point = arrow_pos + a3, end_point = arrow_pos + a1, color = debug_one_way_route_color })
                msg.post("@render:", "draw_line", { start_point = arrow_pos + a4, end_point = arrow_pos + a2, color = debug_one_way_route_color })
            end
        end
    end
end

----------------------------------------------------------------------
-- Debug: player
----------------------------------------------------------------------
local function debug_draw_player(map, self_player, color, is_show_projection, is_show_directions, is_show_snap_radius, is_show_collision)
    assert(self_player, "You must provide movement data")
    assert(color, "You must provide a color")

    local path = self_player.path
    local start_i = self_player.path_index

    if is_show_snap_radius then
        local r = self_player.config.gameobject_threshold + 1
        local steps = 16
        local prev = nil

        for i = 0, steps do
            local angle = (i / steps) * 6.28318530718
            local p = self_player.current_position + vmath.vector3(math.cos(angle) * r, math.sin(angle) * r, 0)

            if prev then
                msg.post("@render:", "draw_line", {
                    start_point = prev,
                    end_point   = p,
                    color       = vmath.vector4(1, 0.5, 0, 1)
                })
            end
            prev = p
        end
    end

    if start_i == 0 then
        if is_show_projection then
            local result = map:calculate_to_nearest_route(self_player.current_position)
            if result then
                local proj = result.position_on_route
                local from_pos = get_map_state(map).map_node_list[result.route_from_id].position
                local to_pos   = get_map_state(map).map_node_list[result.route_to_id].position

                msg.post("@render:", "draw_line", {
                    start_point = from_pos,
                    end_point   = to_pos,
                    color       = vmath.vector4(1, 1, 0, 1)
                })

                msg.post("@render:", "draw_line", {
                    start_point = self_player.current_position,
                    end_point   = proj,
                    color       = vmath.vector4(1, 1, 0, 1)
                })

                local r = 4
                local steps = 10
                local prev = nil

                for i = 0, steps do
                    local angle = (i / steps) * 6.28318530718
                    local p = proj + vmath.vector3(math.cos(angle) * r, math.sin(angle) * r, 0)

                    if prev then
                        msg.post("@render:", "draw_line", {
                            start_point = prev,
                            end_point   = p,
                            color       = vmath.vector4(1, 1, 0, 1)
                        })
                    end
                    prev = p
                end
            end
        end
        return
    end

    local arrow_spacing = 40
    local dist_acc = 0

    for i = start_i, #path - 1 do
        local p1 = path[i]
        local p2 = path[i + 1]

        msg.post("@render:", "draw_line", {
            start_point = p1,
            end_point   = p2,
            color       = color
        })

        if is_show_directions then
            local seg = p2 - p1
            local seg_len = vmath.length(seg)

            if seg_len > 0.001 then
                local dir = seg / seg_len
                local perp = vmath.vector3(-dir.y, dir.x, 0)
                local arrow_size = 6

                local remaining = seg_len

                while remaining + dist_acc >= arrow_spacing do
                    local t = (arrow_spacing - dist_acc) / seg_len
                    local arrow_pos = p1 + seg * t

                    local tip  = arrow_pos + dir * arrow_size
                    local left = arrow_pos - dir * arrow_size + perp * arrow_size * 0.6
                    local right= arrow_pos - dir * arrow_size - perp * arrow_size * 0.6

                    msg.post("@render:", "draw_line", { start_point = left,  end_point = tip, color = color })
                    msg.post("@render:", "draw_line", { start_point = right, end_point = tip, color = color })

                    remaining = remaining - (arrow_spacing - dist_acc)
                    dist_acc = 0
                end

                dist_acc = dist_acc + remaining
            end
        end
    end

    if is_show_projection then
        local target = path[start_i]
        local dx = self_player.current_position.x - target.x
        local dy = self_player.current_position.y - target.y
        local dist_sq = dx*dx + dy*dy
        local threshold_sq = (self_player.config.gameobject_threshold + 1) * (self_player.config.gameobject_threshold + 1)

        if dist_sq > threshold_sq then
            local result = map:calculate_to_nearest_route(self_player.current_position)
            if result then
                local proj = result.position_on_route
                local from_pos = get_map_state(map).map_node_list[result.route_from_id].position
                local to_pos   = get_map_state(map).map_node_list[result.route_to_id].position

                msg.post("@render:", "draw_line", { start_point = from_pos, end_point = to_pos, color = vmath.vector4(1,1,0,1) })
                msg.post("@render:", "draw_line", { start_point = self_player.current_position, end_point = proj, color = vmath.vector4(1,1,0,1) })

                local r = 4
                local steps = 10
                local prev = nil

                for i = 0, steps do
                    local angle = (i / steps) * 6.28318530718
                    local p = proj + vmath.vector3(math.cos(angle) * r, math.sin(angle) * r, 0)

                    if prev then
                        msg.post("@render:", "draw_line", {
                            start_point = prev,
                            end_point   = p,
                            color       = vmath.vector4(1, 1, 0, 1)
                        })
                    end
                    prev = p
                end
            end
        end
    end

    if is_show_collision and self_player.config.collision_enabled then
        ----------------------------------------------------------
        -- 1. Draw collision radius
        ----------------------------------------------------------
        local steps = 20
        local radius = self_player.config.collision_radius
        local prev = nil

        for i = 0, steps do
            local a = (i / steps) * 6.28318
            local x = self_player.current_position.x + math.cos(a) * radius
            local y = self_player.current_position.y + math.sin(a) * radius
            local p = vmath.vector3(x, y, 0)

            if prev then
                msg.post("@render:", "draw_line", {
                    start_point = prev,
                    end_point   = p,
                    color       = vmath.vector4(1, 0.2, 0.2, 0.8)
                })
            end
            prev = p
        end

        ----------------------------------------------------------
        -- 1.5 Crowd pressure / density radius (NEW)
        ----------------------------------------------------------
        do
            local preset = COLLISION_BEHAVIOR_PRESETS[self_player.config.collision_behavior]
            if preset and self_player._debug_density then
                local density = self_player._debug_density
                if density > 0 then
                    local density_radius = radius * preset.density_radius_factor
                    local steps_d = 24
                    local prev_d = nil

                    -- Color: green (low) -> yellow -> red (high)
                    local r = density
                    local g = 1 - math.max(0, density - 0.3) * (1 / 0.7)
                    if g < 0 then g = 0 end
                    local b = 0.0
                    local a = 0.4 + density * 0.4

                    local col = vmath.vector4(r, g, b, a)

                    for i = 0, steps_d do
                        local ang = (i / steps_d) * 6.28318530718
                        local x = self_player.current_position.x + math.cos(ang) * density_radius
                        local y = self_player.current_position.y + math.sin(ang) * density_radius
                        local p = vmath.vector3(x, y, 0)

                        if prev_d then
                            msg.post("@render:", "draw_line", {
                                start_point = prev_d,
                                end_point   = p,
                                color       = col
                            })
                        end
                        prev_d = p
                    end
                end
            end
        end

        ----------------------------------------------------------
        -- 2. Draw predicted future position
        ----------------------------------------------------------
        if self_player._last_dir_x then
            local lookahead = 0.25
            local fx = self_player.current_position.x + self_player._last_dir_x * self_player._last_speed * lookahead
            local fy = self_player.current_position.y + self_player._last_dir_y * self_player._last_speed * lookahead

            msg.post("@render:", "draw_line", {
                start_point = self_player.current_position,
                end_point   = vmath.vector3(fx, fy, 0),
                color       = vmath.vector4(0.2, 0.6, 1, 1)
            })
        end

        ----------------------------------------------------------
        -- 3. Draw avoidance vector (if present)
        ----------------------------------------------------------
        if self_player._debug_avoid_x then
            local ax = self_player.current_position.x + self_player._debug_avoid_x * 20
            local ay = self_player.current_position.y + self_player._debug_avoid_y * 20

            msg.post("@render:", "draw_line", {
                start_point = self_player.current_position,
                end_point   = vmath.vector3(ax, ay, 0),
                color       = vmath.vector4(1, 0.8, 0.1, 1)
            })
        end

        ----------------------------------------------------------
        -- 4. Draw final movement direction
        ----------------------------------------------------------
        if self_player._debug_final_x then
            local fx = self_player.current_position.x + self_player._debug_final_x * 20
            local fy = self_player.current_position.y + self_player._debug_final_y * 20

            msg.post("@render:", "draw_line", {
                start_point = self_player.current_position,
                end_point   = vmath.vector3(fx, fy, 0),
                color       = vmath.vector4(0.1, 1, 0.3, 1)
            })
        end
    end
end

----------------------------------------------------------------------
-- Player class methods
----------------------------------------------------------------------

function Player:update(speed)
    return self.map:player_update(self, speed)
end

function Player:debug_draw(color, is_show_projection, is_show_directions, is_show_snap_radius, is_show_collision)
    return debug_draw_player(self.map, self, color, is_show_projection, is_show_directions, is_show_snap_radius, is_show_collision)
end

function Player:is_in_group(group)
    if not self.groups then
        return false
    end
    return self.groups[group] == true
end

function Player:set_gameobject_threshold(value)
    self.config.gameobject_threshold = value
end

function Player:set_allow_enter_on_route(value)
    self.config.allow_enter_on_route = value
end

function Player:set_curve_tightness(v)
    self.config.path_curve_tightness = v
end

function Player:set_curve_roundness(v)
    self.config.path_curve_roundness = v
end

function Player:set_curve_max_distance(v)
    self.config.path_curve_max_distance_from_corner = v
end


function Player:get_groups()
    local list = {}
    if self.groups then
        for group in pairs(self.groups) do
            list[#list + 1] = group
        end
    end
    return list
end

function Player:add_to_group(group)
    assert(self.map, "Player has no map assigned")

    -- Already in group? Do nothing
    if self.groups and self.groups[group] then
        return false   -- optional: return false to indicate "no change"
    end

    self.map:add_player_to_group(self.key, group)
    return true        -- optional: return true to indicate "added"
end

function Player:remove_from_group(group)
    assert(self.map, "Player has no map assigned")
    self.map:remove_player_from_group(self.key, group)
end

function Player:destroy()
    self.map = nil
    self.path = {}
    self.path_node_ids = {}
    self.current_face_vector = nil
    self._prev_angle = nil
    self.groups = nil

    -- scratch / debug fields (safe to clear)
    self._scratch_candidates = nil
    self._scratch_ids        = nil
    self._scratch_nv         = nil
    self._scratch_rv         = nil
end


----------------------------------------------------------------------
-- Player creation (Map method)
----------------------------------------------------------------------
function Map:normalize_destination_list(list)
    assert(type(list) == "table", "destination_list must be a table")

    for i = 1, #list do
        local ref = list[i]
        local t = type(ref)

        if t == "number" then
            -- already a node ID
            -- do nothing
        elseif t == "string" or t == "userdata" then
            -- treat as node key
            local node = get_map_state(self).node_registry[ref]
            assert(node, "Unknown node key in destination_list: " .. tostring(ref))
            list[i] = node.id
        elseif t == "table" and ref.id then
            -- node object
            list[i] = ref.id
        else
            error("Invalid destination reference at index " .. i)
        end
    end
end

function Map:get_nearest_node_from_groups(position, groups)
    assert(position and type(position) == "userdata",
        "get_nearest_node_from_groups: position must be a vmath.vector3")

    -- groups can be a single string or a list
    local group_list
    if type(groups) == "string" then
        group_list = { groups }
    else
        assert(type(groups) == "table",
            "get_nearest_node_from_groups: groups must be string or list of strings")
        group_list = groups
    end

    ----------------------------------------------------------------------
    -- Step 1: Find nearest route entry point from the given position
    ----------------------------------------------------------------------
    local near_result = self:calculate_to_nearest_route(position)
    if not near_result then
        return nil
    end

    local start_a = near_result.route_from_id
    local start_b = near_result.route_to_id

    ----------------------------------------------------------------------
    -- Step 2: Collect all candidate node IDs from the given groups
    ----------------------------------------------------------------------
    local candidates = {}

    for _, group in ipairs(group_list) do
        local g = get_map_state(self).nodes_by_group[group]
        if g then
            for node_id in pairs(g) do
                candidates[#candidates + 1] = node_id
            end
        end
    end

    if #candidates == 0 then
        return nil
    end

    ----------------------------------------------------------------------
    -- Step 3: For each candidate, compute shortest path distance
    --         from both possible entry nodes (start_a, start_b)
    ----------------------------------------------------------------------
    local best_node = nil
    local best_dist = math.huge

    for i = 1, #candidates do
        local target = candidates[i]

        -- Try path from start_a
        local path_a = self:fetch_path(start_a, target)
        if path_a then
            local dist = path_a.distance
                + distance(position, get_map_state(self).map_node_list[start_a].position)

            if dist < best_dist then
                best_dist = dist
                best_node = target
            end
        end

        -- Try path from start_b
        local path_b = self:fetch_path(start_b, target)
        if path_b then
            local dist = path_b.distance
                + distance(position, get_map_state(self).map_node_list[start_b].position)

            if dist < best_dist then
                best_dist = dist
                best_node = target
            end
        end
    end

    return best_node
end

function Map:get_random_node_from_groups(groups)
    assert(groups, "get_random_node_from_groups: groups required")

    -- Normalize input: allow single string or list
    local group_list
    if type(groups) == "string" then
        group_list = { groups }
    else
        assert(type(groups) == "table",
            "get_random_node_from_groups: groups must be string or list of strings")
        group_list = groups
    end

    ------------------------------------------------------------------
    -- Collect unique node IDs from all groups
    ------------------------------------------------------------------
    local collected = {}
    local count = 0

    for i = 1, #group_list do
        local group = group_list[i]
        local g = get_map_state(self).nodes_by_group[group]

        if g then
            for node_id in pairs(g) do
                if not collected[node_id] then
                    collected[node_id] = true
                    count = count + 1
                end
            end
        end
    end

    if count == 0 then
        return nil
    end

    ------------------------------------------------------------------
    -- Convert to array for random selection
    ------------------------------------------------------------------
    local list = {}
    local idx = 1
    for node_id in pairs(collected) do
        list[idx] = node_id
        idx = idx + 1
    end

    ------------------------------------------------------------------
    -- Pick random node
    ------------------------------------------------------------------
    local choice = list[math.random(#list)]
    return choice
end

function Map:create_player(key, groups, initial_position,
                           destination_list,
                           route_type,
                           initial_face_vector,
                           config)
    assert(key, "Player key required")
    assert(not get_map_state(self).players[key], "Player with this key already exists")
    assert(initial_position, "You must provide initial position")
    assert(destination_list, "You must provide a destination list")

    route_type = default(route_type, M.ROUTETYPE.ONETIME)

    -- If config is omitted or nil, create a default one
    if type(config) ~= "table" or getmetatable(config) ~= PlayerConfig then
        config = PlayerConfig.new()
    end

    config:validate()
    self:normalize_destination_list(destination_list)

    local destination_id = 1
    local dest_count     = #destination_list
    if route_type == M.ROUTETYPE.SHUFFLE and dest_count > 1 then
        destination_id = math.random(dest_count)
    end

    local initial_angle = nil
    if initial_face_vector then
        initial_angle = atan2(initial_face_vector.y, initial_face_vector.x)
    end

    local move_data = {
        map                                   = self,
        destination_list                      = destination_list,
        destination_index                     = destination_id,
        route_type                            = route_type,
        path_index                            = 0,
        path                                  = {},
        path_node_ids                         = {},
        path_version                          = 0,
 
        current_position                      = initial_position,
        current_face_vector                   = initial_face_vector,
        initial_angle                         = initial_angle,

        config = config
    }

    local player = setmetatable(move_data, Player)

    -- Assign unique id per map
    get_map_state(self).player_id_iter = get_map_state(self).player_id_iter + 1
    player.id = get_map_state(self).player_id_iter
    player.key = key

    -- Track by key
    get_map_state(self).players[key] = player

    -- Track groups
    player.groups = {}

    if groups then
        for _, group in ipairs(groups) do
            self:add_player_to_group(key, group)
        end
    end

    return self:move_internal_initialize(initial_position, move_data)
end

----------------------------------------------------------------------
-- Module exports
----------------------------------------------------------------------

M.Map      = Map
M.Player   = Player
M.NODETYPE = NODETYPE
M.PlayerConfig = PlayerConfig

return M