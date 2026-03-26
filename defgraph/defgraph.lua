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

local function copy_table(t)
    local new_table = {}
    for k, v in pairs(t) do
        new_table[k] = v
    end
    return new_table
end

----------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------

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

----------------------------------------------------------------------
-- Default settings (used as template for each Map)
----------------------------------------------------------------------

local settings_main_gameobject_threshold                = 1
local settings_main_path_curve_tightness               = 4
local settings_main_path_curve_roundness               = 3
local settings_main_path_curve_max_distance_from_corner = 10
local settings_main_allow_enter_on_route               = true

-- debug drawing defaults (shared)
local debug_node_color          = vmath.vector4(1, 0, 1, 1)
local debug_two_way_route_color = vmath.vector4(0, 1, 0, 1)
local debug_one_way_route_color = vmath.vector4(0, 1, 1, 1)
local debug_draw_scale          = 5

----------------------------------------------------------------------
-- Classes
----------------------------------------------------------------------

local Map   = {}
Map.__index = Map

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
    local self = {
        -- graph data
        map_node_list    = {}, -- [node_id] = { position, type, neighbor_id[] }
        map_route_list   = {}, -- [from_id][to_id] = { a,b,c,distance,ab_len2,inv_ab_len }
        pathfinder_cache = {}, -- [from_id][to_id] = { distance, path[], node_versions[], route_versions[] }

        -- versioning
        node_version   = {},   -- [node_id] = int
        route_version  = {},   -- [from_id][to_id] = int

        -- node id iterator
        map_node_id_iter = 0,

        -- per-map settings (copied from global defaults)
        settings_gameobject_threshold                = settings_main_gameobject_threshold,
        settings_path_curve_tightness               = settings_main_path_curve_tightness,
        settings_path_curve_roundness               = settings_main_path_curve_roundness,
        settings_path_curve_max_distance_from_corner = settings_main_path_curve_max_distance_from_corner,
        settings_allow_enter_on_route               = settings_main_allow_enter_on_route,

        -- holds players
        players = {}
    }
    return setmetatable(self, Map)
end

function Map:destroy()
    -- Clear all internal structures
    self.map_node_list = {}
    self.map_route_list = {}
    self.pathfinder_cache = {}
    self.node_version = {}
    self.route_version = {}

    -- Optional: track players and destroy them
    if self.players then
        for _, player in ipairs(self.players) do
            if player.destroy then
                player:destroy()
            end
        end
        self.players = {}
    end

    self._destroyed = true
end

----------------------------------------------------------------------
-- Map: versioning helpers
----------------------------------------------------------------------

function Map:bump_node_version(node_id)
    local nv = self.node_version
    nv[node_id] = (nv[node_id] or 0) + 1
end

function Map:bump_route_version(from_id, to_id)
    local rv = self.route_version
    local row = rv[from_id]
    if not row then
        row = {}
        rv[from_id] = row
    end
    row[to_id] = (row[to_id] or 0) + 1
end

function Map:compute_path_version(node_ids)
    local maxv = 0
    local nv = self.node_version
    local rv = self.route_version

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

    local current_nv = self.node_version
    local current_rv = self.route_version

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
-- Map settings
----------------------------------------------------------------------

function Map:set_properties(settings_gameobject_threshold,
                            settings_path_curve_tightness,
                            settings_path_curve_roundness,
                            settings_path_curve_max_distance_from_corner,
                            settings_allow_enter_on_route)

    self.settings_gameobject_threshold                = settings_gameobject_threshold or self.settings_gameobject_threshold
    self.settings_path_curve_tightness               = settings_path_curve_tightness or self.settings_path_curve_tightness
    self.settings_path_curve_roundness               = settings_path_curve_roundness or self.settings_path_curve_roundness
    self.settings_path_curve_max_distance_from_corner =
        settings_path_curve_max_distance_from_corner or self.settings_path_curve_max_distance_from_corner

    if settings_allow_enter_on_route ~= nil then
        self.settings_allow_enter_on_route = settings_allow_enter_on_route
    end
end

----------------------------------------------------------------------
-- Map modification
----------------------------------------------------------------------

function Map:update_node_position(node_id, position)
    assert(node_id, "You must provide a node id")
    assert(position, "You must provide a position")
    local map_node_list = self.map_node_list
    assert(map_node_list[node_id], ("Unknown node id %s"):format(tostring(node_id)))

    map_node_list[node_id].position = vmath.vector3(position.x, position.y, 0)
    local neighbors = map_node_list[node_id].neighbor_id
    local map_route_list = self.map_route_list

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
    local map_node_list = map.map_node_list
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

local function map_add_oneway_route(map, source_id, destination_id, route_info)
    local map_node_list  = map.map_node_list
    local map_route_list = map.map_route_list

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
            local inv_ab_len = 1 / sqrt(ab_len2)

            routes_from[destination_id] = {
                a          = a,
                b          = b,
                c          = c,
                distance   = distance(from_pos, to_pos),
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
        end
    end

    map:bump_route_version(source_id, destination_id)
    return routes_from[destination_id]
end

local function map_remove_oneway_route(map, source_id, destination_id)
    local map_node_list  = map.map_node_list
    local map_route_list = map.map_route_list

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

function Map:add_node(position)
    assert(position, "You must provide a position")

    self.map_node_id_iter = self.map_node_id_iter + 1
    local node_id = self.map_node_id_iter

    self.map_node_list[node_id] = {
        position    = vmath.vector3(position.x, position.y, 0),
        type        = NODETYPE.SINGLE,
        neighbor_id = {},
    }

    self:bump_node_version(node_id)
    return node_id
end

function Map:add_route(source_id, destination_id, is_one_way)
    assert(source_id, "You must provide a source id")
    assert(destination_id, "You must provide a destination id")
    local map_node_list = self.map_node_list
    assert(map_node_list[source_id], ("Unknown source id %s"):format(tostring(source_id)))
    assert(map_node_list[destination_id], ("Unknown destination id %s"):format(tostring(destination_id)))

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
    assert(source_id, "You must provide a source id")
    assert(destination_id, "You must provide a destination id")
    local map_node_list = self.map_node_list
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
    local map_node_list  = self.map_node_list
    local map_route_list = self.map_route_list
    assert(map_node_list[node_id], ("Unknown node id %s"):format(tostring(node_id)))

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

    map_node_list[node_id] = nil
    self:bump_node_version(node_id)
end

----------------------------------------------------------------------
-- Nearest route
----------------------------------------------------------------------

function Map:calculate_to_nearest_route(position)
    local map_node_list  = self.map_node_list
    local map_route_list = self.map_route_list

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

----------------------------------------------------------------------
-- Pathfinding
----------------------------------------------------------------------

function Map:calculate_path(start_id, finish_id)
    local map_node_list  = self.map_node_list
    local map_route_list = self.map_route_list

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
    local pathfinder_cache = self.pathfinder_cache

    if from_id == to_id then
        local ids = { from_id }
        local node_versions = { self.node_version[from_id] or 0 }
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
    if not path_nodes or #path_nodes == 0 then return nil end

    local route = {}
    for index = #path_nodes, 1, -1 do
        local node = path_nodes[index]
        if node.distance ~= 0 then
            local cache_row = pathfinder_cache[node.id]
            if not cache_row then
                cache_row = {}
                pathfinder_cache[node.id] = cache_row
            end

            local node_ids = copy_table(route)
            local node_versions = {}
            local route_versions = {}

            for i = 1, #node_ids do
                node_versions[i] = self.node_version[node_ids[i]] or 0
            end
            for i = 1, #node_ids - 1 do
                local a = node_ids[i]
                local b = node_ids[i + 1]
                local rv_row = self.route_version[a]
                route_versions[i] = rv_row and rv_row[b] or 0
            end

            cache_row[to_id] = {
                distance       = node.distance,
                path           = node_ids,
                node_versions  = node_versions,
                route_versions = route_versions,
            }
        end
        table.insert(route, 1, node.id)
    end

    return pathfinder_cache[from_id][to_id]
end

----------------------------------------------------------------------
-- Path curvature
----------------------------------------------------------------------

local function process_path_curvature(before, current, after, roundness,
                                      settings_path_curve_tightness,
                                      settings_path_curve_max_distance_from_corner,
                                      out_list)
    out_list = out_list or {}

    local Q_before = (settings_path_curve_tightness - 1) / settings_path_curve_tightness * before +
                     current / settings_path_curve_tightness
    local R_before = before / settings_path_curve_tightness +
                     (settings_path_curve_tightness - 1) / settings_path_curve_tightness * current
    local Q_after  = (settings_path_curve_tightness - 1) / settings_path_curve_tightness * current +
                     after / settings_path_curve_tightness
    local R_after  = current / settings_path_curve_tightness +
                     (settings_path_curve_tightness - 1) / settings_path_curve_tightness * after

    if distance(Q_before, before) > settings_path_curve_max_distance_from_corner then
        Q_before = vmath.lerp(settings_path_curve_max_distance_from_corner / distance(before, current), before, current)
    end
    if distance(R_before, current) > settings_path_curve_max_distance_from_corner then
        R_before = vmath.lerp(settings_path_curve_max_distance_from_corner / distance(before, current), current, before)
    end
    if distance(Q_after, current) > settings_path_curve_max_distance_from_corner then
        Q_after = vmath.lerp(settings_path_curve_max_distance_from_corner / distance(current, after), current, after)
    end
    if distance(R_after, after) > settings_path_curve_max_distance_from_corner then
        R_after = vmath.lerp(settings_path_curve_max_distance_from_corner / distance(current, after), after, current)
    end

    if roundness ~= 1 then
        process_path_curvature(Q_before, R_before, Q_after, roundness - 1,
                               settings_path_curve_tightness,
                               settings_path_curve_max_distance_from_corner,
                               out_list)
        process_path_curvature(R_before, Q_after, R_after, roundness - 1,
                               settings_path_curve_tightness,
                               settings_path_curve_max_distance_from_corner,
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

    local from_path, to_path
    local map_route_list = self.map_route_list

    if map_route_list[near_result.route_to_id] and map_route_list[near_result.route_to_id][near_result.route_from_id] then
        from_path = self:fetch_path(near_result.route_from_id,
                                    move_data.destination_list[move_data.destination_index])
    end
    if map_route_list[near_result.route_from_id] and map_route_list[near_result.route_from_id][near_result.route_to_id] then
        to_path = self:fetch_path(near_result.route_to_id,
                                  move_data.destination_list[move_data.destination_index])
    end

    local position_list = {}
    local node_ids_list = {}

    position_list[1] = source_position
    local pos_count = 1

    if (near_result.distance > move_data.settings_gameobject_threshold + 1) and move_data.settings_allow_enter_on_route then
        pos_count = pos_count + 1
        position_list[pos_count] = near_result.position_on_route
    end

    local map_node_list = self.map_node_list

    if from_path or to_path then
        local from_distance = huge
        local to_distance   = huge

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
            position_list[pos_count] = from_node_pos
            node_ids_list[#node_ids_list + 1] = near_result.route_from_id

            local fp = from_path.path
            for i = 1, #fp do
                pos_count = pos_count + 1
                position_list[pos_count] = map_node_list[fp[i]].position
                node_ids_list[#node_ids_list + 1] = fp[i]
            end
        else
            pos_count = pos_count + 1
            position_list[pos_count] = to_node_pos
            node_ids_list[#node_ids_list + 1] = near_result.route_to_id

            local tp = to_path.path
            for i = 1, #tp do
                pos_count = pos_count + 1
                position_list[pos_count] = map_node_list[tp[i]].position
                node_ids_list[#node_ids_list + 1] = fp and fp[i] or tp[i]
            end
        end
    end

    local path = move_data.path
    for i = 1, #path do path[i] = nil end

    if move_data.settings_path_curve_roundness ~= 0 and pos_count > 2 then
        path[1] = position_list[1]
        local path_count = 1

        for i = 2, pos_count - 1 do
            local curve_temp = move_data._curve_temp or {}
            move_data._curve_temp = curve_temp
            for k = 1, #curve_temp do curve_temp[k] = nil end

            local partial_position_list, Q_before, R_after =
                process_path_curvature(position_list[i - 1], position_list[i], position_list[i + 1],
                                       move_data.settings_path_curve_roundness,
                                       move_data.settings_path_curve_tightness,
                                       move_data.settings_path_curve_max_distance_from_corner,
                                       curve_temp)

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
    assert(self_player, "You must provide defold move data")
    assert(go, "You must provide a game object")

    local current_position = go.get_position()
    local path             = self_player.path
    local path_index       = self_player.path_index

    -- 1. Fine-grained path invalidation
    if path_index ~= 0 then
        local ids = self_player.path_node_ids
        if ids and #ids > 0 then
            if self:compute_path_version(ids) ~= self_player.path_version then
                self_player = self:move_internal_initialize(current_position, self_player)
                path = self_player.path
                path_index = self_player.path_index
            end
        end
    end

    -- 2. Rotation smoothing helper
    local rotation = nil
    local function apply_rotation_smoothing(dir_x, dir_y)
        if not self_player.initial_angle then
            return nil
        end

        local cf = self_player.current_face_vector
        local rx = cf.x + (dir_x - cf.x) * (0.2 * speed)
        local ry = cf.y + (dir_y - cf.y) * (0.2 * speed)

        local angle = math.atan2(ry, rx)

        local prev_angle = self_player._prev_angle or angle
        local diff = angle - prev_angle

        if diff > 3.14159 then diff = diff - 6.28318 end
        if diff < -3.14159 then diff = diff + 6.28318 end

        if math.abs(diff) < 0.02 then
            angle = prev_angle
        else
            angle = prev_angle + diff * 0.25
        end

        self_player._prev_angle = angle
        self_player.current_face_vector.x = rx
        self_player.current_face_vector.y = ry

        return vmath.quat_rotation_z(angle - self_player.initial_angle)
    end

    -- 3. No path
    if path_index == 0 then
        if self_player.initial_angle then
            local cf = self_player.current_face_vector
            rotation = apply_rotation_smoothing(cf.x, cf.y)
        end

        return {
            position       = current_position,
            rotation       = rotation,
            is_reached     = false,
            destination_id = self_player.destination_list[self_player.destination_index],
        }
    end

    -- 4. Movement loop
    local threshold_sq = self_player.settings_gameobject_threshold_sq
    local last_index   = #path
    local map_node_list = self.map_node_list

    for i = path_index, last_index do
        local target = path[i]

        local vx = target.x - current_position.x
        local vy = target.y - current_position.y
        local dist_sq = vx*vx + vy*vy

        if dist_sq > threshold_sq then
            self_player.path_index = i

            local inv_len = 1 / math.sqrt(dist_sq)
            local dir_x = vx * inv_len
            local dir_y = vy * inv_len

            if self_player.initial_angle then
                rotation = apply_rotation_smoothing(dir_x, dir_y)
            end

            local new_x = current_position.x + dir_x * speed
            local new_y = current_position.y + dir_y * speed

            return {
                position       = vmath.vector3(new_x, new_y, 0),
                rotation       = rotation,
                is_reached     = false,
                destination_id = self_player.destination_list[self_player.destination_index],
            }
        end

        if i == last_index then
            local dest_id  = self_player.destination_list[self_player.destination_index]
            local dest_pos = map_node_list[dest_id].position

            local dx = current_position.x - dest_pos.x
            local dy = current_position.y - dest_pos.y
            local is_reached = (dx*dx + dy*dy <= threshold_sq)

            if self_player.initial_angle then
                local cf = self_player.current_face_vector
                rotation = apply_rotation_smoothing(cf.x, cf.y)
            end

            if is_reached then
                local count = #self_player.destination_list
                if self_player.route_type == M.ROUTETYPE.ONETIME then
                    if self_player.destination_index < count then
                        self_player.destination_index = self_player.destination_index + 1
                        self_player = self:move_internal_initialize(current_position, self_player)
                    end
                elseif self_player.route_type == M.ROUTETYPE.SHUFFLE then
                    if count > 1 then
                        local new_id = self_player.destination_index
                        repeat
                            new_id = math.random(count)
                        until new_id ~= self_player.destination_index
                        self_player.destination_index = new_id
                        self_player = self:move_internal_initialize(current_position, self_player)
                    end
                elseif self_player.route_type == M.ROUTETYPE.CYCLE then
                    if self_player.destination_index < count then
                        self_player.destination_index = self_player.destination_index + 1
                    else
                        self_player.destination_index = 1
                    end
                    self_player = self:move_internal_initialize(current_position, self_player)
                end
            end

            return {
                position       = current_position,
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
    debug_node_color          = node_color or debug_node_color
    debug_two_way_route_color = two_way_route_color or debug_two_way_route_color
    debug_one_way_route_color = one_way_route_color or debug_one_way_route_color
    debug_draw_scale          = draw_scale or debug_draw_scale
end

function Map:debug_draw_map_nodes(is_show_ids)
    local s = debug_draw_scale

    local up     = vmath.vector3(0,  s, 0)
    local down   = vmath.vector3(0, -s, 0)
    local left   = vmath.vector3(-s, 0, 0)
    local right  = vmath.vector3( s, 0, 0)
    local diag   = vmath.vector3( s,  s, 0)
    local ndiag  = vmath.vector3(-s, -s, 0)

    for node_id, node in pairs(self.map_node_list) do
        local p = node.position

        if is_show_ids then
            msg.post("@render:", "draw_text", {
                text = tostring(node_id),
                position = p + diag
            })
        end

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

    local map_node_list  = self.map_node_list
    local map_route_list = self.map_route_list

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

local function debug_draw_player(map, self_player, color, is_show_projection, is_show_directions, is_show_snap_radius)
    assert(self_player, "You must provide movement data")
    assert(color, "You must provide a color")

    local path = self_player.path
    local start_i = self_player.path_index
    local pos = go.get_position()

    if is_show_snap_radius then
        local r = self_player.settings_gameobject_threshold + 1
        local steps = 16
        local prev = nil

        for i = 0, steps do
            local angle = (i / steps) * 6.28318530718
            local p = pos + vmath.vector3(math.cos(angle) * r, math.sin(angle) * r, 0)

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
            local result = map:calculate_to_nearest_route(pos)
            if result then
                local proj = result.position_on_route
                local from_pos = map.map_node_list[result.route_from_id].position
                local to_pos   = map.map_node_list[result.route_to_id].position

                msg.post("@render:", "draw_line", {
                    start_point = from_pos,
                    end_point   = to_pos,
                    color       = vmath.vector4(1, 1, 0, 1)
                })

                msg.post("@render:", "draw_line", {
                    start_point = pos,
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
        local dx = pos.x - target.x
        local dy = pos.y - target.y
        local dist_sq = dx*dx + dy*dy

        if dist_sq > self_player.settings_gameobject_threshold_sq then
            local result = map:calculate_to_nearest_route(pos)
            if result then
                local proj = result.position_on_route
                local from_pos = map.map_node_list[result.route_from_id].position
                local to_pos   = map.map_node_list[result.route_to_id].position

                msg.post("@render:", "draw_line", { start_point = from_pos, end_point = to_pos, color = vmath.vector4(1,1,0,1) })
                msg.post("@render:", "draw_line", { start_point = pos, end_point = proj, color = vmath.vector4(1,1,0,1) })

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
end

----------------------------------------------------------------------
-- Player class methods
----------------------------------------------------------------------

function Player:update(speed)
    return self.map:player_update(self, speed)
end

function Player:debug_draw(color, is_show_projection, is_show_directions, is_show_snap_radius)
    return debug_draw_player(self.map, self, color, is_show_projection, is_show_directions, is_show_snap_radius)
end

function Player:destroy()
    self.map = nil
    self.path = {}
    self.path_node_ids = {}
    self._prev_angle = nil
    self.current_face_vector = nil
end


----------------------------------------------------------------------
-- Player creation (Map method)
----------------------------------------------------------------------

function Map:create_player(initial_position,
                           destination_list,
                           route_type,
                           initial_face_vector,
                           settings_gameobject_threshold,
                           settings_path_curve_tightness,
                           settings_path_curve_roundness,
                           settings_path_curve_max_distance_from_corner,
                           settings_allow_enter_on_route)

    assert(initial_position, "You must provide initial position")
    assert(destination_list, "You must provide a destination list")

    route_type                        = route_type or M.ROUTETYPE.ONETIME
    settings_gameobject_threshold     = settings_gameobject_threshold or self.settings_gameobject_threshold
    settings_path_curve_roundness     = settings_path_curve_roundness or self.settings_path_curve_roundness
    settings_path_curve_tightness     = settings_path_curve_tightness or self.settings_path_curve_tightness
    settings_path_curve_max_distance_from_corner =
        settings_path_curve_max_distance_from_corner or self.settings_path_curve_max_distance_from_corner

    if settings_allow_enter_on_route == nil then
        settings_allow_enter_on_route = self.settings_allow_enter_on_route
    end

    local destination_id = 1
    local dest_count     = #destination_list
    if route_type == M.ROUTETYPE.SHUFFLE and dest_count > 1 then
        destination_id = math.random(dest_count)
    end

    local initial_angle = nil
    if initial_face_vector then
        initial_angle = atan2(initial_face_vector.y, initial_face_vector.x)
    end

    local threshold_sq = (settings_gameobject_threshold + 1) * (settings_gameobject_threshold + 1)

    local move_data = {
        map                                   = self,
        destination_list                      = destination_list,
        destination_index                     = destination_id,
        route_type                            = route_type,
        path_index                            = 0,
        path                                  = {},
        path_node_ids                         = {},
        path_version                          = 0,
        current_face_vector                   = initial_face_vector,
        initial_angle                         = initial_angle,
        settings_gameobject_threshold         = settings_gameobject_threshold,
        settings_gameobject_threshold_sq      = threshold_sq,
        settings_path_curve_tightness         = settings_path_curve_tightness,
        settings_path_curve_roundness         = settings_path_curve_roundness,
        settings_allow_enter_on_route         = settings_allow_enter_on_route,
        settings_path_curve_max_distance_from_corner = settings_path_curve_max_distance_from_corner,
    }

    local player = setmetatable(move_data, Player)

    -- Track players for cleanup
    self.players = self.players or {}
    table.insert(self.players, player)

    return self:move_internal_initialize(initial_position, move_data)
end

----------------------------------------------------------------------
-- Module exports
----------------------------------------------------------------------

M.Map      = Map
M.Player   = Player
M.NODETYPE = NODETYPE

return M