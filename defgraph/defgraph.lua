-- DefGraph v5.0
-- This module contains functions to create a world map as a shape of a graph and the ability
-- to manipulate it at any time, easily see debug drawing of this graph and move and rotate
-- game objects inside of this graph with utilizing auto pathfinder.

local M = {}

math.randomseed(os.time() - os.clock() * 1000)

--- store node data and it's neighbors.
--- structure: map_node_list[node_id] = { position, type, neighbor_id[]:number }
local map_node_list = {}

--- store routes data and line equation and calculation info.
--- structure: map_route_list[from_id][to_id] = { a, b, c, distance, ab_len2, inv_ab_len }
local map_route_list = {}

--- store cached data from pathfinder algorithm.
--- structure: pathfinder_cache[from_id][to_id] = { change_number, distance, path[]:number }
local pathfinder_cache = {}

local map_node_id_iterator = 0
local map_change_iterator = 0

local NODETYPE = {}
NODETYPE.SINGLE = hash("defgraph_nodetype_single")
NODETYPE.DEADEND = hash("defgraph_nodetype_deadend")
NODETYPE.INTERSECTION = hash("defgraph_nodetype_intersection")

-- color vectors and scale of debug drawing
local debug_node_color = vmath.vector4(1, 0, 1, 1)
local debug_two_way_route_color = vmath.vector4(0, 1, 0, 1)
local debug_one_way_route_color = vmath.vector4(0, 1, 1, 1)
local debug_draw_scale = 5

-- main settings
local settings_main_gameobject_threshold = 1
local settings_main_path_curve_tightness = 4
local settings_main_path_curve_roundness = 3
local settings_main_path_curve_max_distance_from_corner = 10
local settings_main_allow_enter_on_route = true

-- math functions
local sqrt = math.sqrt
local abs = math.abs
local huge = math.huge
local atan2 = math.atan2

--- routing types
M.ROUTETYPE = {}
M.ROUTETYPE.ONETIME = hash("defgraph_routetype_onetime")
M.ROUTETYPE.SHUFFLE = hash("defgraph_routetype_shuffle")
M.ROUTETYPE.CYCLE = hash("defgraph_routetype_cycle")

--- utility local functions
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

local function copy_table(table)
    local new_table = {}
    for key, value in pairs(table) do
        new_table[key] = value
    end
    return new_table
end

local function table_size(table)
    local count = 0
    for _ in pairs(table) do count = count + 1 end
    return count
end

--- Set the main path and move calculation properties, nil inputs will fall back to default values.
--- @param settings_gameobject_threshold (number|nil) optional game object threshold [1]
--- @param settings_path_curve_tightness (number|nil) optional path curvature tightness [4]
--- @param settings_path_curve_roundness (number|nil) optional path curvature roundness [3]
--- @param settings_path_curve_max_distance_from_corner (number|nil) optional path curvature maximum distance from corner [10]
--- @param settings_allow_enter_on_route (boolean|nil) optional is game object allow enter on route [true]
function M.map_set_properties(settings_gameobject_threshold, settings_path_curve_tightness, settings_path_curve_roundness,
                              settings_path_curve_max_distance_from_corner, settings_allow_enter_on_route)
    settings_main_gameobject_threshold = settings_gameobject_threshold or settings_main_gameobject_threshold
    settings_main_path_curve_tightness = settings_path_curve_tightness or settings_main_path_curve_tightness
    settings_main_path_curve_roundness = settings_path_curve_roundness or settings_main_path_curve_roundness
    settings_main_path_curve_max_distance_from_corner = settings_path_curve_max_distance_from_corner or settings_main_path_curve_max_distance_from_corner
    if settings_allow_enter_on_route ~= nil then
        settings_main_allow_enter_on_route = settings_allow_enter_on_route
    end
end

--- Update an existing node position.
--- @param node_id (number) node id
--- @param position (vector3) node position
function M.map_update_node_position(node_id, position)
    assert(node_id, "You must provide a node id")
    assert(position, "You must provide a position")
    assert(map_node_list[node_id], ("Unknown node id %s"):format(tostring(node_id)))

    map_node_list[node_id].position = vmath.vector3(position.x, position.y, 0)
    local neighbors = map_node_list[node_id].neighbor_id

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

            local ab_len2 = a * a + b * b
            local inv_ab_len = 1 / sqrt(ab_len2)

            if map_route_list[a_id] and map_route_list[a_id][b_id] then
                map_route_list[a_id][b_id] = {
                    a = a,
                    b = b,
                    c = c,
                    distance = distance(from_pos, to_pos),
                    ab_len2 = ab_len2,
                    inv_ab_len = inv_ab_len,
                }
            end

            a_id, b_id = b_id, a_id
        end
    end

    map_change_iterator = map_change_iterator + 1
end

--- Add one way route from one node to another.
local function map_add_oneway_route(source_id, destination_id, route_info)
    if not map_route_list[source_id] then map_route_list[source_id] = {} end

    if not map_route_list[source_id][destination_id] then
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

            local ab_len2 = a * a + b * b
            local inv_ab_len = 1 / sqrt(ab_len2)

            map_route_list[source_id][destination_id] = {
                a = a,
                b = b,
                c = c,
                distance = distance(from_pos, to_pos),
                ab_len2 = ab_len2,
                inv_ab_len = inv_ab_len,
            }
        else
            map_route_list[source_id][destination_id] = route_info
        end

        if not route_info then
            local is_found = false
            for i = 1, #map_node_list[source_id].neighbor_id do
                if map_node_list[source_id].neighbor_id[i] == destination_id then
                    is_found = true
                    break
                end
            end
            if not is_found then
                table.insert(map_node_list[source_id].neighbor_id, destination_id)
            end

            is_found = false
            for i = 1, #map_node_list[destination_id].neighbor_id do
                if map_node_list[destination_id].neighbor_id[i] == source_id then
                    is_found = true
                    break
                end
            end
            if not is_found then
                table.insert(map_node_list[destination_id].neighbor_id, source_id)
            end
        end
    end

    return map_route_list[source_id][destination_id]
end

--- Update node type parameter.
local function map_update_node_type(node_id)
    if #map_node_list[node_id].neighbor_id == 0 then
        map_node_list[node_id].type = NODETYPE.SINGLE
    elseif #map_node_list[node_id].neighbor_id == 1 then
        map_node_list[node_id].type = NODETYPE.DEADEND
    elseif #map_node_list[node_id].neighbor_id > 1 then
        map_node_list[node_id].type = NODETYPE.INTERSECTION
    end
end

--- Remove an existing route between two nodes.
local function map_remove_oneway_route(source_id, destination_id)
    map_route_list[source_id][destination_id] = nil
    if table_size(map_route_list[source_id]) == 0 then
        map_route_list[source_id] = nil
    end
    if not (map_route_list[destination_id] and map_route_list[destination_id][source_id]) then
        for i = 1, #map_node_list[destination_id].neighbor_id do
            if map_node_list[destination_id].neighbor_id[i] == source_id then
                table.remove(map_node_list[destination_id].neighbor_id, i)
                break
            end
        end
        for i = 1, #map_node_list[source_id].neighbor_id do
            if map_node_list[source_id].neighbor_id[i] == destination_id then
                table.remove(map_node_list[source_id].neighbor_id, i)
                break
            end
        end
    end
end

--- Adding a node at the given position (position.z will get ignored).
--- @param position (vector3) node position
--- @return (number) Newly added node id
function M.map_add_node(position)
    assert(position, "You must provide a position")

    map_node_id_iterator = map_node_id_iterator + 1
    local node_id = map_node_id_iterator
    map_node_list[node_id] = { position = vmath.vector3(position.x, position.y, 0), type = NODETYPE.SINGLE, neighbor_id = {} }
    map_change_iterator = map_change_iterator + 1
    return node_id
end

--- Adding a two-way route between two nodes, you can set it as one way or two way.
--- @param source_id (number) source node id
--- @param destination_id (number) destination node id
--- @param is_one_way (boolean|nil) optional is one-way route [false]
function M.map_add_route(source_id, destination_id, is_one_way)
    assert(source_id, "You must provide a source id")
    assert(destination_id, "You must provide a destination id")

    assert(map_node_list[source_id], ("Unknown source id %s"):format(tostring(source_id)))
    assert(map_node_list[destination_id], ("Unknown destination id %s"):format(tostring(destination_id)))

    if source_id == destination_id then return end

    local route_info = map_add_oneway_route(source_id, destination_id, nil)
    if not is_one_way then
        map_add_oneway_route(destination_id, source_id, route_info)
    end
    map_update_node_type(source_id)
    map_update_node_type(destination_id)
    map_change_iterator = map_change_iterator + 1
end

--- Removing an existing route between two nodes, you can set it to remove just one way or both ways.
--- @param source_id (number) source node id
--- @param destination_id (number) destination node id
--- @param is_remove_one_way (boolean|nil) optional is remove only one-way route [false]
function M.map_remove_route(source_id, destination_id, is_remove_one_way)
    assert(source_id, "You must provide a source id")
    assert(destination_id, "You must provide a destination id")

    assert(map_node_list[source_id], ("Unknown source id %s"):format(tostring(source_id)))
    assert(map_node_list[destination_id], ("Unknown destination id %s"):format(tostring(destination_id)))

    if source_id == destination_id then return end

    map_remove_oneway_route(source_id, destination_id)
    if not is_remove_one_way then
        map_remove_oneway_route(destination_id, source_id)
    end
    map_update_node_type(source_id)
    map_update_node_type(destination_id)
    map_change_iterator = map_change_iterator + 1
end

--- Removing an existing node, attached routes to this node will remove.
--- @param node_id (number) node id
function M.map_remove_node(node_id)
    assert(node_id, "You must provide a node id")
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

        map_remove_oneway_route(from_id, to_id)

        if map_node_list[from_id] then map_update_node_type(from_id) end
        if map_node_list[to_id]   then map_update_node_type(to_id)   end
    end

    map_node_list[node_id] = nil
    map_change_iterator = map_change_iterator + 1
end

--- Calculate the nearest position on the nearest route on the map from the given position.
local function calculate_to_nearest_route(position)
    local min_from, min_to
    local min_x, min_y
    local min_dist = huge

    local visited = {}

    for from_id, routes in pairs(map_route_list) do
        for to_id, route in pairs(routes) do
            if not (visited[from_id] and visited[from_id][to_id]) then
                local from_pos = map_node_list[from_id].position
                local to_pos   = map_node_list[to_id].position

                local near_x, near_y
                local is_between

                if from_pos.x ~= to_pos.x then
                    local denom2 = route.ab_len2 or (route.a * route.a + route.b * route.b)
                    local bx_ax  = (route.b * position.x) - (route.a * position.y)

                    near_x = (route.b * bx_ax - route.a * route.c) / denom2
                    near_y = (route.a * (-route.b * position.x + route.a * position.y) - route.b * route.c) / denom2
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
                        local denom2 = route.ab_len2 or (route.a * route.a + route.b * route.b)
                        inv_len = 1 / sqrt(denom2)
                        route.ab_len2 = denom2
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

                visited[from_id] = visited[from_id] or {}
                visited[from_id][to_id] = true
            end
        end
    end

    if min_dist == huge then
        return nil
    end

    return {
        position_on_route = vmath.vector3(min_x, min_y, 0),
        distance = min_dist,
        route_from_id = min_from,
        route_to_id = min_to
    }
end

--- Calculate graph path inside map from a node to another node.
local function calculate_path(start_id, finish_id)
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

        if not visited[current] then
            visited[current] = true

            if current == finish_id then
                local path = {}
                local total = 0
                local node = finish_id

                while previous[node] do
                    table.insert(path, 1, { id = node, distance = total })
                    local prev = previous[node]
                    local route = map_route_list[prev] and map_route_list[prev][node]
                    if not route then return nil end
                    total = total + route.distance
                    node = prev
                end

                table.insert(path, 1, { id = node, distance = total })
                return path
            end

            local neighbors = map_route_list[current]
            if neighbors then
                for to_id, route in pairs(neighbors) do
                    local alt = current_dist + route.distance
                    if alt < distances[to_id] then
                        distances[to_id] = alt
                        previous[to_id] = current
                        heap_push(heap, to_id, alt)
                    end
                end
            end
        end
    end
end

--- Retrive path results from cache or update cache.
local function fetch_path(change_number, from_id, to_id)
    -- check for same from and to id
    if from_id == to_id then
        return {
            change_number = change_number,
            distance = 0,
            path = {}
        }
    end

    -- check for existing cache
    if pathfinder_cache[from_id] then
        local cache = pathfinder_cache[from_id][to_id]
        if cache and cache.change_number == change_number then
            return cache
        end
    end

    -- calculate path
    local path = calculate_path(from_id, to_id)
    if not path or #path == 0 then return nil end

    -- update cache
    local route = {}
    for index = #path, 1, -1 do
        if path[index].distance ~= 0 then
            if not pathfinder_cache[path[index].id] then
                pathfinder_cache[path[index].id] = {}
            end
            pathfinder_cache[path[index].id][to_id] = {
                change_number = change_number,
                distance = path[index].distance,
                path = copy_table(route)
            }
        end
        table.insert(route, 1, path[index].id)
    end

    return pathfinder_cache[from_id][to_id]
end

--- Calculate path curvature.
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

--- Initialize moves from source position to a node with an destination node inside the created map.
local function move_internal_initialize(source_position, move_data)
    local near_result = calculate_to_nearest_route(source_position)
    if not near_result or #move_data.destination_list == 0 then
        -- stay until something changes
        move_data.change_number = map_change_iterator
        move_data.path_index = 0
        move_data.path = {}
        return move_data
    else
        local from_path = nil
        local to_path = nil

        if map_route_list[near_result.route_to_id] and map_route_list[near_result.route_to_id][near_result.route_from_id] then
            from_path = fetch_path(map_change_iterator, near_result.route_from_id, move_data.destination_list[move_data.destination_index])
        end
        if map_route_list[near_result.route_from_id] and map_route_list[near_result.route_from_id][near_result.route_to_id] then
            to_path = fetch_path(map_change_iterator, near_result.route_to_id, move_data.destination_list[move_data.destination_index])
        end

        local position_list = {}
        table.insert(position_list, source_position)

        if (near_result.distance > move_data.settings_gameobject_threshold + 1) and move_data.settings_allow_enter_on_route then
            table.insert(position_list, near_result.position_on_route)
        end

        if from_path or to_path then
            local from_distance, to_distance

            if not from_path then
                from_distance = huge
            else
                from_distance = from_path.distance + distance(source_position, map_node_list[near_result.route_from_id].position)
            end

            if not to_path then
                to_distance = huge
            else
                to_distance = to_path.distance + distance(source_position, map_node_list[near_result.route_to_id].position)
            end

            if from_distance <= to_distance then
                table.insert(position_list, map_node_list[near_result.route_from_id].position)
                for index = 1, #from_path.path do
                    table.insert(position_list, map_node_list[from_path.path[index]].position)
                end
            else
                table.insert(position_list, map_node_list[near_result.route_to_id].position)
                for index = 1, #to_path.path do
                    table.insert(position_list, map_node_list[to_path.path[index]].position)
                end
            end
        end

        if move_data.settings_path_curve_roundness ~= 0 then
            move_data.path = {}

            table.insert(move_data.path, position_list[1])

            for i = 2, #position_list - 1 do
                local partial_position_list, Q_before, R_after = process_path_curvature(position_list[i - 1], position_list[i], position_list[i + 1],
                           move_data.settings_path_curve_roundness,
                           move_data.settings_path_curve_tightness,
                           move_data.settings_path_curve_max_distance_from_corner,
                           {})

                if i == 2 then
                    table.insert(move_data.path, Q_before)
                end

                for key, value in pairs(partial_position_list) do
                    table.insert(move_data.path, value)
                end

                if i == #position_list - 1 then
                    table.insert(move_data.path, R_after)
                end
            end

            table.insert(move_data.path, position_list[#position_list])
        else
            move_data.path = position_list
        end

        move_data.change_number = map_change_iterator
        move_data.path_index = 1
        return move_data
    end
end

--- Initialize moves from a source position to destination node list inside the created
--- map and using given threshold and initial face vector as game object initial face direction
--- and path calculate settings considering the route type, the optional value will fall back
--- to their default values.
--- @alias ROUTETYPE hash
--- @param self (table) self table
--- @param go (defold_api.go) current game object
--- @param destination_list (table) list of destinations id
--- @param route_type (ROUTETYPE|nil) optional route type [ROUTETYPE.ONETIME]
--- @param initial_face_vector (vector3|nil) optional initial game object face vector [nil]
--- @param settings_gameobject_threshold (number|nil) optional game object threshold [settings_main_gameobject_threshold]
--- @param settings_path_curve_tightness (number|nil) optional path curvature tightness [settings_main_path_curve_tightness]
--- @param settings_path_curve_roundness (number|nil) optional path curvature roundness [settings_main_path_curve_roundness]
--- @param settings_path_curve_max_distance_from_corner (number|nil) optional path curvature maximum distance from corner [settings_main_path_curve_max_distance_from_corner]
--- @param settings_allow_enter_on_route (boolean|nil) optional is game object allow to enter on route [settings_main_allow_enter_on_route]
function M.player_initialization(self,
                                 go,
                                 destination_list,
                                 route_type,
                                 initial_face_vector,
                                 settings_gameobject_threshold,
                                 settings_path_curve_tightness,
                                 settings_path_curve_roundness,
                                 settings_path_curve_max_distance_from_corner,
                                 settings_allow_enter_on_route)

    assert(self, "You must provide self table")
    assert(go, "You must provide a game object")
    assert(destination_list, "You must provide a destination list")

    route_type = route_type or M.ROUTETYPE.ONETIME
    settings_gameobject_threshold = settings_gameobject_threshold or settings_main_gameobject_threshold
    settings_path_curve_roundness = settings_path_curve_roundness or settings_main_path_curve_roundness
    settings_path_curve_tightness = settings_path_curve_tightness or settings_main_path_curve_tightness
    settings_path_curve_max_distance_from_corner = settings_path_curve_max_distance_from_corner or settings_main_path_curve_max_distance_from_corner
    if settings_allow_enter_on_route == nil then
        settings_allow_enter_on_route = settings_main_allow_enter_on_route
    end

    local destination_id = 1
    if route_type == M.ROUTETYPE.SHUFFLE and #destination_list > 1 then
        math.random(#destination_list)
        math.random(#destination_list)
        math.random(#destination_list)

        destination_id = math.random(#destination_list)
    end

    local move_data = {
        change_number = map_change_iterator,
        destination_list = destination_list,
        destination_index = destination_id,
        route_type = route_type,
        path_index = 0,
        path = {},
        initial_face_vector = initial_face_vector,
        current_face_vector = initial_face_vector,
        settings_gameobject_threshold = settings_gameobject_threshold,
        settings_path_curve_tightness = settings_path_curve_tightness,
        settings_path_curve_roundness = settings_path_curve_roundness,
        settings_allow_enter_on_route = settings_allow_enter_on_route,
        settings_path_curve_max_distance_from_corner = settings_path_curve_max_distance_from_corner
    }

    self._defgraph_internal_movement_data = move_internal_initialize(go.get_position(), move_data)
end

--- Calculate movements from current position of the game object inside the created map
--- considering given speed, using last calculated movement data.
--- @param self (table) self table
--- @param go (defold_api.go) current game object
--- @param speed (number) player speed
--- @return (table) move result this table includes:
---      * position (vector3) game object next postion.
---      * rotation (vector3|nil) game object next rotation if rotation calculation was on.
---      * is_reached (boolean) is game object reached a destination.
---      * destination_id (number) node id of destination.
function M.player_update(self, go, speed)

    assert(self, "You must provide self table")
    assert(go, "You must provide a game object")

    local current_position = go.get_position()
    local move_data = self._defgraph_internal_movement_data

    -- check for map updates
    if move_data.change_number ~= map_change_iterator then
        move_data = move_internal_initialize(current_position, move_data)
    end

    local rotation = nil
    -- stand still if no route found
    if move_data.path_index == 0 then
        if move_data.initial_face_vector then
            rotation = vmath.quat_rotation_z(atan2(move_data.current_face_vector.y, move_data.current_face_vector.x) - atan2(move_data.initial_face_vector.y, move_data.initial_face_vector.x))
        end

        self._defgraph_internal_movement_data = move_data
        return {
            position = current_position,
            rotation = rotation,
            is_reached = false,
            destination_id = move_data.destination_list[move_data.destination_index]
        }
    end

    -- check for reaching path section
    while distance(current_position, move_data.path[move_data.path_index]) <= move_data.settings_gameobject_threshold + 1 do
        if move_data.path_index == #move_data.path then
            -- reached next path node
            if move_data.initial_face_vector then
                rotation = vmath.quat_rotation_z(atan2(move_data.current_face_vector.y, move_data.current_face_vector.x) - atan2(move_data.initial_face_vector.y, move_data.initial_face_vector.x))
            end

            -- reached destination
            local is_reached = true
            local destination_id = move_data.destination_list[move_data.destination_index]
            if distance(current_position, map_node_list[destination_id].position) > move_data.settings_gameobject_threshold + 1 then
                is_reached = false
            else
                if move_data.route_type == M.ROUTETYPE.ONETIME then
                    if move_data.destination_index < #move_data.destination_list then
                        move_data.destination_index = move_data.destination_index + 1
                        move_data = move_internal_initialize(current_position, move_data)
                    end
                elseif move_data.route_type == M.ROUTETYPE.SHUFFLE then
                    if #move_data.destination_list > 1 then
                        local new_destination_id = move_data.destination_index
                        repeat
                            new_destination_id = math.random(#move_data.destination_list)
                        until new_destination_id ~= move_data.destination_index
                        move_data.destination_index = new_destination_id
                        move_data = move_internal_initialize(current_position, move_data)
                    end
                elseif move_data.route_type == M.ROUTETYPE.CYCLE then
                    if move_data.destination_index < #move_data.destination_list then
                        move_data.destination_index = move_data.destination_index + 1
                    else
                        move_data.destination_index = 1
                    end
                    move_data = move_internal_initialize(current_position, move_data)
                end
            end

            self._defgraph_internal_movement_data = move_data
            return {
                position = current_position,
                rotation = rotation,
                is_reached = is_reached,
                destination_id = destination_id
            }
        else
            -- go for next section
            move_data.path_index = move_data.path_index + 1
        end
    end

    -- movement calculation
    local direction_vector = move_data.path[move_data.path_index] - current_position
    direction_vector.z = 0
    direction_vector = vmath.normalize(direction_vector)
    if move_data.initial_face_vector then
        local rotation_vector = vmath.lerp(0.2 * speed, move_data.current_face_vector, direction_vector)
        rotation = vmath.quat_rotation_z(atan2(rotation_vector.y, rotation_vector.x) - atan2(move_data.initial_face_vector.y, move_data.initial_face_vector.x))
        move_data.current_face_vector = rotation_vector
    end

    self._defgraph_internal_movement_data = move_data
    return {
        position = current_position +  direction_vector * speed,
        rotation = rotation,
        is_reached = false,
        destination_id = move_data.destination_list[move_data.destination_index]
    }
end

-- Debug Methods

--- set the debug drawing properties, nil inputs will fall back to default values.
--- @param node_color (vector4|nil) optional nodes color [vector4(1, 0, 1, 1)]
--- @param two_way_route_color (vector4|nil) optional two-way routes color [vector4(0, 1, 0, 1)]
--- @param one_way_route_color (vector4|nil) optional one-way routes color [vector4(0, 1, 1, 1)]
--- @param draw_scale (number|nil) optional drawing scale [5]
function M.debug_set_properties(node_color, two_way_route_color, one_way_route_color, draw_scale)
    debug_node_color = node_color or debug_node_color
    debug_two_way_route_color = two_way_route_color or debug_two_way_route_color
    debug_one_way_route_color = one_way_route_color or debug_one_way_route_color
    debug_draw_scale = draw_scale or debug_draw_scale
end

--- Debug draw all map nodes and choose to show node ids or not.
--- @param is_show_ids (boolean|nil) optional is show nodes id [false]
function M.debug_draw_map_nodes(is_show_ids)
    for node_id, node in pairs(map_node_list) do
        if is_show_ids then
            msg.post("@render:", "draw_text", { text = node_id, position = node.position + vmath.vector3(debug_draw_scale, -debug_draw_scale, 0) } )
        end

        if node.type == NODETYPE.SINGLE then
            msg.post("@render:", "draw_line", { start_point = node.position + vmath.vector3(debug_draw_scale, -debug_draw_scale, 0), end_point = node.position + vmath.vector3(-debug_draw_scale, -debug_draw_scale, 0), color = debug_node_color } )
            msg.post("@render:", "draw_line", { start_point = node.position + vmath.vector3(debug_draw_scale, -debug_draw_scale, 0), end_point = node.position + vmath.vector3(0, debug_draw_scale, 0), color = debug_node_color } )
            msg.post("@render:", "draw_line", { start_point = node.position + vmath.vector3(-debug_draw_scale, -debug_draw_scale, 0), end_point = node.position + vmath.vector3(0, debug_draw_scale, 0), color = debug_node_color } )
        end

        if node.type == NODETYPE.DEADEND then
            msg.post("@render:", "draw_line", { start_point = node.position + vmath.vector3(debug_draw_scale, debug_draw_scale, 0), end_point = node.position + vmath.vector3(-debug_draw_scale, -debug_draw_scale, 0), color = debug_node_color } )
            msg.post("@render:", "draw_line", { start_point = node.position + vmath.vector3(-debug_draw_scale, debug_draw_scale, 0), end_point = node.position + vmath.vector3(debug_draw_scale, -debug_draw_scale, 0), color = debug_node_color } )
        end

        if node.type == NODETYPE.INTERSECTION then
            msg.post("@render:", "draw_line", { start_point = node.position + vmath.vector3(debug_draw_scale, debug_draw_scale, 0), end_point = node.position + vmath.vector3(debug_draw_scale, -debug_draw_scale, 0), color = debug_node_color } )
            msg.post("@render:", "draw_line", { start_point = node.position + vmath.vector3(-debug_draw_scale, debug_draw_scale, 0), end_point = node.position + vmath.vector3(-debug_draw_scale, -debug_draw_scale, 0), color = debug_node_color } )
            msg.post("@render:", "draw_line", { start_point = node.position + vmath.vector3(-debug_draw_scale, debug_draw_scale, 0), end_point = node.position + vmath.vector3(debug_draw_scale, debug_draw_scale, 0), color = debug_node_color } )
            msg.post("@render:", "draw_line", { start_point = node.position + vmath.vector3(-debug_draw_scale, -debug_draw_scale, 0), end_point = node.position + vmath.vector3(debug_draw_scale, -debug_draw_scale, 0), color = debug_node_color } )
        end

    end
end

--- Debug draw all map routes.
function M.debug_draw_map_routes()
    for from_id, routes in pairs(map_route_list) do
        for to_id, route in pairs(routes) do
            if map_route_list[to_id] and map_route_list[to_id][from_id] then
                msg.post("@render:", "draw_line", { start_point = map_node_list[from_id].position, end_point = map_node_list[to_id].position, color = debug_two_way_route_color } )
            else
                msg.post("@render:", "draw_line", { start_point = map_node_list[from_id].position, end_point = map_node_list[to_id].position, color = debug_one_way_route_color } )

                local arrow_postion = 4 / 5 * map_node_list[to_id].position + map_node_list[from_id].position / 5
                msg.post("@render:", "draw_line", { start_point = arrow_postion + vmath.vector3(3, 3, 0), end_point = arrow_postion + vmath.vector3(3, -3, 0), color = debug_one_way_route_color } )
                msg.post("@render:", "draw_line", { start_point = arrow_postion + vmath.vector3(-3, 3, 0), end_point = arrow_postion + vmath.vector3(-3, -3, 0), color = debug_one_way_route_color } )
                msg.post("@render:", "draw_line", { start_point = arrow_postion + vmath.vector3(-3, 3, 0), end_point = arrow_postion + vmath.vector3(3, 3, 0), color = debug_one_way_route_color } )
                msg.post("@render:", "draw_line", { start_point = arrow_postion + vmath.vector3(-3, -3, 0), end_point = arrow_postion + vmath.vector3(3, -3, 0), color = debug_one_way_route_color } )
            end
        end
    end
end

--- Debug draw player specific path with given color.
--- @param self (table) self table
--- @param color (vector4) path color
--- @param is_show_intersection (boolean|nil) optional is show intersection [false]
function M.debug_draw_player(self, color, is_show_intersection)

    assert(self, "You must provide self table")
    assert(color, "You must provide a color")

    if self._defgraph_internal_movement_data.path_index ~= 0 then
        for index = self._defgraph_internal_movement_data.path_index, #self._defgraph_internal_movement_data.path do
            if index ~= #self._defgraph_internal_movement_data.path then
                msg.post("@render:", "draw_line", { start_point = self._defgraph_internal_movement_data.path[index], end_point = self._defgraph_internal_movement_data.path[index + 1], color = color } )
            end
            if is_show_intersection then
                msg.post("@render:", "draw_line", { start_point = self._defgraph_internal_movement_data.path[index] + vmath.vector3(debug_draw_scale + 2, debug_draw_scale + 2, 0), end_point = self._defgraph_internal_movement_data.path[index] + vmath.vector3(-debug_draw_scale - 2, -debug_draw_scale - 2, 0), color = color } )
                msg.post("@render:", "draw_line", { start_point = self._defgraph_internal_movement_data.path[index] + vmath.vector3(-debug_draw_scale - 2, debug_draw_scale + 2, 0), end_point = self._defgraph_internal_movement_data.path[index] + vmath.vector3(debug_draw_scale + 2, -debug_draw_scale - 2, 0), color = color } )
            end
        end
    end
end

return M