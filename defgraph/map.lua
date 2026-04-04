-- defgraph/map.lua
-- Map class - node/route management, groups, versioning, player creation, etc.

local constants_module = require("defgraph.constants")
local pathfinding_module = require("defgraph.pathfinding")
local curvature_module   = require("defgraph.curvature")
local debug_module   = require("defgraph.debug")
local player_module = require("defgraph.player")
local config_module = require("defgraph.config")

-- Internal hidden map state
local map_state = setmetatable({}, {__mode = 'k'})

local function get_map_state(self)
    local state = map_state[self]
    assert(state, 'Invalid Map object')
    return state
end

local function set_map_state(self, state)
    map_state[self] = state
end

local Map = {}
Map.__index = Map

-- Protect Map from accidental field assignment
function Map.__newindex(self, key, value)
    error('Cannot set Map.' .. tostring(key) .. ' (Map internal state is read-only)')
end

-- ==================== Map Registry ====================

local map_registry = {}

function Map.create_map(key)
    assert(key, "Map key required")
    assert(not map_registry[key], "Map with this key already exists")
    local map = Map.new()
    map_registry[key] = map
    return map
end

function Map.get_map(key)
    return map_registry[key]
end

function Map.create_or_get_map(key)
    if not map_registry[key] then
        map_registry[key] = Map.new()
    end
    return map_registry[key]
end

function Map.has_map(key)
    return map_registry[key] ~= nil
end

function Map.remove_map(key)
    local map = map_registry[key]
    if not map then return end
    if map.destroy then map:destroy() end
    map_registry[key] = nil
end

-- ==================== Map Constructor ====================

function Map.new()
    local map = setmetatable({}, Map)
    local state = {
        -- graph data
        map_node_list    = {}, -- [node_id] = Node
        map_route_list   = {}, -- [from_id][to_id] = { a,b,c,distance,ab_len2,inv_ab_len } (route info)
        pathfinder_cache = {}, -- [from_id][to_id] = { distance, path[], node_versions[], route_versions[] } (cached path)
        collision_candidate_cache = {},   -- group -> list of players

        -- node registry / groups
        node_registry   = {},  -- key -> Node
        nodes_by_group  = {},  -- group -> { node_id = true }

        -- players
        players         = {},  -- key -> player
        players_by_group = {}, -- group -> { key -> true }

        -- versioning
        node_version   = {},   -- [node_id] = int
        route_version  = {},   -- [from_id][to_id] = int

        map_node_id_iter = 0,
        player_id_iter   = 0,
    }
    set_map_state(map, state)
    return map
end

-- ==================== Attach External Functions ====================

-- Pathfinding
Map.calculate_to_nearest_route = pathfinding_module.calculate_to_nearest_route
Map.calculate_path             = pathfinding_module.calculate_path
Map.fetch_path                 = pathfinding_module.fetch_path

-- Curvature & movement init
Map.move_internal_initialize   = curvature_module.move_internal_initialize

-- Debug
Map.debug_set_properties       = debug_module.debug_set_properties
Map.debug_draw_map_nodes       = debug_module.debug_draw_map_nodes
Map.debug_draw_map_routes      = debug_module.debug_draw_map_routes
Map.debug_draw_group           = debug_module.debug_draw_group
Map.debug_draw_groups          = debug_module.debug_draw_groups

-- Also expose get_map_state so other modules can use it
Map.get_map_state              = get_map_state

-- ==================== Internal Helpers ====================

function Map:invalidate_collision_cache(group)
    local state = get_map_state(self)
    if group then
        state.collision_candidate_cache[group] = nil
    else
        state.collision_candidate_cache = {}
    end
end

local function map_update_node_type(map, node_id)
    local state = get_map_state(map)
    local neighbors = state.map_node_list[node_id].neighbor_id
    local n = #neighbors
    if n == 0 then
        state.map_node_list[node_id].type = constants_module.NODETYPE.SINGLE
    elseif n == 1 then
        state.map_node_list[node_id].type = constants_module.NODETYPE.DEADEND
    else
        state.map_node_list[node_id].type = constants_module.NODETYPE.INTERSECTION
    end
end

local function map_add_oneway_route(map, source_id, destination_id, route_info)
    local state = get_map_state(map)
    local map_node_list  = state.map_node_list
    local map_route_list = state.map_route_list

    local routes_from = map_route_list[source_id]
    if not routes_from then
        routes_from = {}
        map_route_list[source_id] = routes_from
    end

    if not routes_from[destination_id] then
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

            routes_from[destination_id] = {
                a          = a,
                b          = b,
                c          = c,
                distance   = constants_module.distance(from_pos, to_pos),
                ab_len2    = ab_len2,
                inv_ab_len = inv_ab_len,
            }
        else
            routes_from[destination_id] = route_info
        end

        if not route_info then
            local src_neighbors = map_node_list[source_id].neighbor_id
            local dst_neighbors = map_node_list[destination_id].neighbor_id

            local found = false
            for i = 1, #src_neighbors do
                if src_neighbors[i] == destination_id then found = true break end
            end
            if not found then
                src_neighbors[#src_neighbors + 1] = destination_id
            end

            found = false
            for i = 1, #dst_neighbors do
                if dst_neighbors[i] == source_id then found = true break end
            end
            if not found then
                dst_neighbors[#dst_neighbors + 1] = source_id
            end
        end
    end

    map:bump_route_version(source_id, destination_id)
    return routes_from[destination_id]
end

local function map_remove_oneway_route(map, source_id, destination_id)
    local state = get_map_state(map)
    local map_node_list  = state.map_node_list
    local map_route_list = state.map_route_list

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

-- ==================== Node & Route Management ====================

function Map:get_node_by_id(id)
    return get_map_state(self).map_node_list[id]
end

function Map:get_node_by_key(key)
    return get_map_state(self).node_registry[key]
end

function Map:add_node_to_group(node_id, group)
    local state = get_map_state(self)
    local node = state.map_node_list[node_id]
    if not node then return false end

    if node.groups[group] then return false end

    node.groups[group] = true
    state.nodes_by_group[group] = state.nodes_by_group[group] or {}
    state.nodes_by_group[group][node_id] = true

    return true
end

function Map:remove_node_from_group(node_id, group)
    local state = get_map_state(self)
    local node = state.map_node_list[node_id]
    if not node then return end

    if node.groups[group] then
        node.groups[group] = nil
    end

    local g = state.nodes_by_group[group]
    if g then
        g[node_id] = nil
        if next(g) == nil then
            state.nodes_by_group[group] = nil
        end
    end
end

function Map:get_nodes_in_group(group)
    local state = get_map_state(self)
    local g = state.nodes_by_group[group]
    if not g then return {} end

    local list = {}
    for node_id in pairs(g) do
        list[#list + 1] = state.map_node_list[node_id]
    end
    return list
end

function Map:remove_node_by_key(key)
    assert(key, "You must provide a node key")
    local state = get_map_state(self)
    local node = state.node_registry[key]
    assert(node, ("Unknown node key %s"):format(tostring(key)))
    self:remove_node(node.id)
end

function Map:remove_nodes_in_group(group)
    assert(group, "You must provide a group name")
    local state = get_map_state(self)
    local g = state.nodes_by_group[group]
    if not g then return end

    local ids = {}
    for node_id in pairs(g) do
        ids[#ids + 1] = node_id
    end

    for i = 1, #ids do
        self:remove_node(ids[i])
    end

    state.nodes_by_group[group] = nil
end

-- ==================== Player Management ====================

function Map:get_player(key)
    return get_map_state(self).players[key]
end

function Map:remove_player(key)
    local state = get_map_state(self)
    local player = state.players[key]
    if not player then return end

    if player.groups then
        for group in pairs(player.groups) do
            local g = state.players_by_group[group]
            if g then g[key] = nil end
        end
    end

    if player.destroy then
        player:destroy()
    end

    state.players[key] = nil
    self:invalidate_collision_cache()
end

function Map:get_players_in_group(group)
    local state = get_map_state(self)
    local g = state.players_by_group[group]
    if not g then return {} end

    local list = {}
    for key in pairs(g) do
        list[#list + 1] = state.players[key]
    end
    return list
end

function Map:remove_players_in_group(group)
    local state = get_map_state(self)
    local g = state.players_by_group[group]
    if not g then return end

    for key in pairs(g) do
        self:remove_player(key)
    end

    state.players_by_group[group] = nil
    self:invalidate_collision_cache()
end

function Map:add_player_to_group(key, group)
    local state = get_map_state(self)
    local player = state.players[key]
    assert(player, "Player not found: " .. tostring(key))

    if player.groups[group] then return false end

    state.players_by_group[group] = state.players_by_group[group] or {}
    state.players_by_group[group][key] = true
    player.groups[group] = true

    self:invalidate_collision_cache(group)
    return true
end

function Map:remove_player_from_group(key, group)
    local state = get_map_state(self)
    local player = state.players[key]
    if not player then return end

    if player.groups[group] then
        player.groups[group] = nil
    end

    local g = state.players_by_group[group]
    if g then
        g[key] = nil
        if next(g) == nil then
            state.players_by_group[group] = nil
        end
    end

    self:invalidate_collision_cache(group)
end

function Map:is_player_in_group(key, group)
    local state = get_map_state(self)
    local player = state.players[key]
    if not player then return false end
    return player.groups and player.groups[group] == true
end

-- ==================== Versioning ====================

function Map:bump_node_version(node_id)
    local state = get_map_state(self)
    local nv = state.node_version
    nv[node_id] = (nv[node_id] or 0) + 1
end

function Map:bump_route_version(from_id, to_id)
    local state = get_map_state(self)
    local rv = state.route_version
    local row = rv[from_id]
    if not row then
        row = {}
        rv[from_id] = row
    end
    row[to_id] = (row[to_id] or 0) + 1
end

function Map:compute_path_version(node_ids)
    local state = get_map_state(self)
    local maxv = 0
    local nv = state.node_version
    local rv = state.route_version

    for i = 1, #node_ids do
        local v = nv[node_ids[i]] or 0
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
    local state = get_map_state(self)
    local ids = cache.path
    local nv  = cache.node_versions
    local rv  = cache.route_versions

    local current_nv = state.node_version
    local current_rv = state.route_version

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

-- ==================== Map Modification ====================

function Map:update_node_position(node_id, position)
    assert(node_id, "You must provide a node id")
    assert(position, "You must provide a position")
    local state = get_map_state(self)
    assert(state.map_node_list[node_id], ("Unknown node id %s"):format(tostring(node_id)))

    state.map_node_list[node_id].position = vmath.vector3(position.x, position.y, 0)
    local neighbors = state.map_node_list[node_id].neighbor_id
    local map_route_list = state.map_route_list

    for i = 1, #neighbors do
        local a_id = node_id
        local b_id = neighbors[i]

        for _ = 1, 2 do
            local from_pos = state.map_node_list[a_id].position
            local to_pos   = state.map_node_list[b_id].position

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

            local routes_from = map_route_list[a_id]
            if routes_from and routes_from[b_id] then
                routes_from[b_id] = {
                    a          = a,
                    b          = b,
                    c          = c,
                    distance   = constants_module.distance(from_pos, to_pos),
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

function Map:create_node(position, key, groups)
    local state = get_map_state(self)

    if key ~= nil then
        assert(type(key) == "string" or type(key) == "userdata",
            "Map:create_node: key must be a string or hash")
    end

    assert(position and type(position) == "userdata",
        "Map:create_node: position must be a vmath.vector3")

    if groups ~= nil then
        assert(type(groups) == "table", "groups must be a list of strings")
        for i = 1, #groups do
            assert(type(groups[i]) == "string", "group names must be strings")
        end
    end

    state.map_node_id_iter = state.map_node_id_iter + 1
    local id = state.map_node_id_iter

    if key == nil then
        key = "defgraph_default_node_key_" .. tostring(id)
    end

    local node = {
        id        = id,
        key       = key,
        position  = vmath.vector3(position.x, position.y, 0),
        type      = constants_module.NODETYPE.SINGLE,
        neighbor_id = {},
        groups    = {},
    }

    state.map_node_list[id] = node
    state.node_registry[key] = node

    if groups then
        for i = 1, #groups do
            local group = groups[i]
            node.groups[group] = true
            state.nodes_by_group[group] = state.nodes_by_group[group] or {}
            state.nodes_by_group[group][id] = true
        end
    end

    self:bump_node_version(id)
    return id
end

function Map:create_node_xy(x, y, key, groups)
    assert(type(x) == "number" and type(y) == "number",
        "Map:create_node_xy: x and y must be numbers")

    local position = vmath.vector3(x, y, 0)
    return self:create_node(position, key, groups)
end

function Map:add_route(source_id, destination_id, is_one_way)
    assert(source_id and destination_id, "source_id and destination_id required")
    local state = get_map_state(self)
    assert(state.map_node_list[source_id], ("Unknown source id %s"):format(tostring(source_id)))
    assert(state.map_node_list[destination_id], ("Unknown destination id %s"):format(tostring(destination_id)))

    if source_id == destination_id then return end

    local route_info = map_add_oneway_route(self, source_id, destination_id, nil)
    if not is_one_way then
        map_add_oneway_route(self, destination_id, source_id, route_info)
    end

    map_update_node_type(self, source_id)
    map_update_node_type(self, destination_id)

    self:bump_node_version(source_id)
    self:bump_node_version(destination_id)
end

function Map:remove_route(source_id, destination_id, is_remove_one_way)
    assert(source_id and destination_id, "source_id and destination_id required")
    local state = get_map_state(self)
    assert(state.map_node_list[source_id])
    assert(state.map_node_list[destination_id])

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
    local state = get_map_state(self)

    local node = state.map_node_list[node_id]
    assert(node, ("Unknown node id %s"):format(tostring(node_id)))

    -- Remove from groups
    if node.groups then
        for group in pairs(node.groups) do
            local g = state.nodes_by_group[group]
            if g then
                g[node_id] = nil
                if next(g) == nil then
                    state.nodes_by_group[group] = nil
                end
            end
        end
    end

    -- Remove from registry
    if node.key then
        state.node_registry[node.key] = nil
    end

    -- Remove all connected routes
    local to_remove = {}
    for from_id, routes in pairs(state.map_route_list) do
        for to_id in pairs(routes) do
            if from_id == node_id or to_id == node_id then
                to_remove[#to_remove + 1] = { from_id = from_id, to_id = to_id }
            end
        end
    end

    for _, r in ipairs(to_remove) do
        map_remove_oneway_route(self, r.from_id, r.to_id)
        if state.map_node_list[r.from_id] then map_update_node_type(self, r.from_id) end
        if state.map_node_list[r.to_id]   then map_update_node_type(self, r.to_id)   end
        self:bump_node_version(r.from_id)
        self:bump_node_version(r.to_id)
    end

    -- Remove node
    state.map_node_list[node_id] = nil
    self:bump_node_version(node_id)

    -- Clear pathfinder cache
    state.pathfinder_cache = {}
end

function Map:normalize_destination_list(list)
    assert(type(list) == "table", "destination_list must be a table")

    local normalized = {}
    for i = 1, #list do
        local ref = list[i]
        local t = type(ref)

        if t == "number" then
            normalized[i] = ref
        elseif t == "string" or t == "userdata" then
            -- treat as node key
            local node = get_map_state(self).node_registry[ref]
            assert(node, "Unknown node key in destination_list: " .. tostring(ref))
            normalized[i] = node.id
        elseif t == "table" and ref.id then
            -- node object
            normalized[i] = ref.id
        else
            error("Invalid destination reference at index " .. i)
        end
    end
    return normalized
end

function Map:get_nearest_node_from_groups(position, groups)
    assert(position and type(position) == "userdata",
        "get_nearest_node_from_groups: position must be a vmath.vector3")

    -- groups can be a single string or a list
    local group_list
    if type(groups) == "string" then
        group_list = { groups }
    else
        assert(type(groups) == "table", "groups must be string or list of strings")
        group_list = groups
    end

    ----------------------------------------------------------------------
    -- Step 1: Find nearest route entry point from the given position
    ----------------------------------------------------------------------
    local near_result = self:calculate_to_nearest_route(position)
    if not near_result then return nil end

    local start_a = near_result.route_from_id
    local start_b = near_result.route_to_id

    ----------------------------------------------------------------------
    -- Step 2: Collect all candidate node IDs from the given groups
    ----------------------------------------------------------------------
    local candidates = {}
    local state = get_map_state(self)

    for _, group in ipairs(group_list) do
        local g = state.nodes_by_group[group]
        if g then
            for node_id in pairs(g) do
                candidates[#candidates + 1] = node_id
            end
        end
    end

    if #candidates == 0 then return nil end

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
            local dist = path_a.distance + constants_module.distance(position, state.map_node_list[start_a].position)
            if dist < best_dist then
                best_dist = dist
                best_node = target
            end
        end

        -- Try path from start_b
        local path_b = self:fetch_path(start_b, target)
        if path_b then
            local dist = path_b.distance + constants_module.distance(position, state.map_node_list[start_b].position)
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

    local group_list
    if type(groups) == "string" then
        group_list = { groups }
    else
        assert(type(groups) == "table", "groups must be string or list of strings")
        group_list = groups
    end

    ------------------------------------------------------------------
    -- Collect unique node IDs from all groups
    ------------------------------------------------------------------
    local collected = {}
    local count = 0
    local state = get_map_state(self)

    for i = 1, #group_list do
        local group = group_list[i]
        local g = state.nodes_by_group[group]
        if g then
            for node_id in pairs(g) do
                if not collected[node_id] then
                    collected[node_id] = true
                    count = count + 1
                end
            end
        end
    end

    if count == 0 then return nil end

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
    return list[math.random(#list)]
end

-- ==================== Player Creation ====================

function Map:create_player(key, groups, initial_position, destination_list, route_type, initial_face_vector, config)
    assert(key, "Player key required")
    local state = get_map_state(self)
    assert(not state.players[key], "Player with this key already exists")
    assert(initial_position, "You must provide initial position")
    assert(destination_list, "You must provide a destination list")

    route_type = constants_module.default(route_type, constants_module.ROUTETYPE.ONETIME)

    if type(config) ~= "table" or getmetatable(config) ~= config_module.PlayerConfig then
        config = config_module.PlayerConfig.new(config or {})
    end

    config:validate()
    destination_list = self:normalize_destination_list(destination_list)

    local destination_id = 1
    local dest_count = #destination_list

    if route_type == constants_module.ROUTETYPE.SHUFFLE and dest_count > 1 then
        destination_id = math.random(dest_count)
    end

    local initial_angle = nil
    if initial_face_vector then
        initial_angle = math.atan2(initial_face_vector.y, initial_face_vector.x)
    end

    local move_data = {
        map               = self,
        destination_list  = destination_list,
        destination_index = destination_id,
        route_type        = route_type,
        path_index        = 0,
        path              = {},
        path_node_ids     = {},
        path_version      = 0,
        patrol_direction  = 1,  -- used for PATROL route type

        current_position    = initial_position,
        current_face_vector = initial_face_vector,
        initial_angle       = initial_angle,

        config = config
    }

    local player = setmetatable(move_data, player_module.Player)

    state.player_id_iter = state.player_id_iter + 1
    player.id = state.player_id_iter
    player.key = key

    state.players[key] = player
    player.groups = {}

    if groups then
        for _, group in ipairs(groups) do
            self:add_player_to_group(key, group)
        end
    end

    return self:move_internal_initialize(initial_position, move_data)
end

-- ==================== Destroy ====================

function Map:destroy()
    local state = get_map_state(self)

    for key, player in pairs(state.players) do
        if player.destroy then player:destroy() end
        state.players[key] = nil
    end

    state.players_by_group = {}
    state.map_node_list = {}
    state.node_registry = {}
    state.nodes_by_group = {}
    state.map_route_list = {}
    state.pathfinder_cache = {}
    state.node_version = {}
    state.route_version = {}
    state.collision_candidate_cache = {}

    self._destroyed = true
    map_state[self] = nil
end

return Map