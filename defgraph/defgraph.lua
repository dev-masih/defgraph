-- DefGraph
-- This module contains functions to create a world map as a shape of a graph and the ability
-- to manipulate it at any time, easily see debug drawing of this graph and move and rotate
-- game objects inside of this graph with utilizing auto pathfinder.

local M = {}

local map_node_list = {}
-- map_node_list[node_id] = { position, type }

local map_route_list = {}
-- map_route_list[from_id][to_id] = { a, b, c, distance }

local pathfinder_cache = {}
-- pathfinder_cache[from_id][to_id] = { change_number, distance, path:{} }

local map_node_id_iterator = 0
local map_change_iterator = 0
local NODETYPE = {
    single = 0,
    deadend = 1,
    intersection = 2
}

-- local: color vectors and scale of debug drawing
local debug_node_color = vmath.vector4(1, 0, 1, 1)
local debug_route_color = vmath.vector4(0, 1, 0, 1)
local debug_draw_scale = 5

-- local: main settings
local settings_main_go_threshold = 1
local settings_main_path_curve_tightness = 4
local settings_main_path_curve_roundness = 3
local settings_main_path_curve_max_distance_from_corner = 10
local settings_main_allow_enter_on_route = true

-- local: math functions
local sqrt = math.sqrt
local pow = math.pow
local abs = math.abs
local huge = math.huge
local pi = math.pi

-- global: Set the main path and move calculation properties, nil inputs will fall back to default values.
-- arguments: settings_go_threshold as optional number [1]
--            settings_path_curve_tightness as optional number [4]
--            settings_path_curve_roundness as optional number [3]
--            settings_path_curve_max_distance_from_corner as optional number [10]
--            settings_allow_enter_on_route as optional boolean [true]
function M.map_set_properties(settings_go_threshold, settings_path_curve_tightness, settings_path_curve_roundness
    , settings_path_curve_max_distance_from_corner, settings_allow_enter_on_route)
    if settings_go_threshold ~= nil then
        settings_main_go_threshold = settings_go_threshold
    end
    if settings_path_curve_tightness ~= nil then
        settings_main_path_curve_tightness = settings_path_curve_tightness
    end
    if settings_path_curve_roundness ~= nil then
        settings_main_path_curve_roundness = settings_path_curve_roundness
    end
    if settings_path_curve_max_distance_from_corner ~= nil then
        settings_main_path_curve_max_distance_from_corner = settings_path_curve_max_distance_from_corner
    end
    if settings_allow_enter_on_route ~= nil then
        settings_main_allow_enter_on_route = settings_allow_enter_on_route
    end
end

-- global: Update an existing node position.
-- arguments: node_id as number
--            position as vecotr3
function M.map_update_node_position(node_id, position)
    if map_node_list[node_id] ~= nil then
        map_node_list[node_id].position = position
    end
    for to_id, route in pairs(map_route_list[node_id]) do
        -- line equation: ax + by + c = 0
        local a, b, c
        local from_pos = map_node_list[node_id].position
        local to_pos = map_node_list[to_id].position
        if from_pos.x ~= to_pos.x then
            --non vertical
            a = (from_pos.y - to_pos.y)/(to_pos.x - from_pos.x)
            b = 1
            c = ((from_pos.x * to_pos.y) - (to_pos.x * from_pos.y))/(to_pos.x - from_pos.x)
        else
            --vertical
            a = 1
            b = 0
            c = -from_pos.x
        end
        map_route_list[node_id][to_id] = {
            a = a,
            b = b,
            c = c,
            distance = sqrt(pow(from_pos.x - to_pos.x, 2) + pow(from_pos.y - to_pos.y, 2))
        }
        map_route_list[to_id][node_id] = map_route_list[node_id][to_id]
    end
    -- map shape is changed
    map_change_iterator = map_change_iterator + 1
end

-- global: Set the debug drawing properties, nil inputs will fall back to default values.
-- arguments: node_color as optional vector4 [vector4(1, 0, 1, 1)]
--            route_color as optional vector4 [vector4(0, 1, 0, 1)]
--            draw_scale as optional number [5]
function M.debug_set_properties(node_color, route_color, draw_scale)
    if node_color ~= nil then
        debug_node_color = node_color
    end
    if route_color ~= nil then
        debug_route_color = route_color
    end
    if draw_scale ~= nil then
        debug_draw_scale = draw_scale
    end
end

-- local: Count size of non-sequential table.
-- arguments: table as table
-- return: size of table as number
local function table_size(table)
    local count = 0
    for _ in pairs(table) do
        count = count + 1
    end
    return count
end

-- local: Add one way route from one node to another.
-- arguments: source_id as number
--            destination_id as number
local function map_add_oneway_route(source_id, destination_id)
    if map_route_list[source_id] == nil then
        map_route_list[source_id] = {}
    end

    if map_route_list[source_id][destination_id] == nil then
        -- line equation: ax + by + c = 0
        local a, b, c
        local from_pos = map_node_list[source_id].position
        local to_pos = map_node_list[destination_id].position
        if from_pos.x ~= to_pos.x then
            --non vertical
            a = (from_pos.y - to_pos.y)/(to_pos.x - from_pos.x)
            b = 1
            c = ((from_pos.x * to_pos.y) - (to_pos.x * from_pos.y))/(to_pos.x - from_pos.x)
        else
            --vertical
            a = 1
            b = 0
            c = -from_pos.x
        end
        map_route_list[source_id][destination_id] = {
            a = a,
            b = b,
            c = c,
            distance = sqrt(pow(from_pos.x - to_pos.x, 2) + pow(from_pos.y - to_pos.y, 2))
        }
    end
end

-- local: Update node type parameter.
-- arguments: node_id as number
local function map_update_node_type(node_id)
    if map_route_list[node_id] ~= nil then
        local size = table_size(map_route_list[node_id])
        if size == 0 then
            map_node_list[node_id].type = NODETYPE.single
        elseif size == 1 then
            map_node_list[node_id].type = NODETYPE.deadend
        elseif size > 1 then
            map_node_list[node_id].type = NODETYPE.intersection
        end
    end
end

-- local: Remove an existing route between two nodes.
-- arguments: source_id as number
--            destination_id as number
local function map_remove_oneway_route(source_id, destination_id)
    if map_route_list[source_id] ~= nil then
        map_route_list[source_id][destination_id] = nil
        if table_size(map_route_list[source_id]) == 0 then
            map_route_list[source_id] = nil
        end
    end
end

-- global: Adding a node at the given position (position.z will get ignored).
-- arguments: position as vector3
-- return: Newly added node id as number
function M.map_add_node(position)
    map_node_id_iterator = map_node_id_iterator + 1
    local node_id = map_node_id_iterator
    map_node_list[node_id] = { position = vmath.vector3(position.x, position.y, 0), type = NODETYPE.single }
    map_change_iterator = map_change_iterator + 1
    return node_id
end

-- global: Adding a two-way route between two nodes.
-- arguments: source_id as number
--            destination_id as number
function M.map_add_route(source_id, destination_id)
    if map_node_list[source_id] == nil 
    or map_node_list[destination_id] == nil
    or source_id == destination_id then
        return
    end
    map_add_oneway_route(source_id, destination_id)
    map_add_oneway_route(destination_id, source_id)
    map_update_node_type(source_id)
    map_update_node_type(destination_id)
    map_change_iterator = map_change_iterator + 1
end

-- global: Removing an existing route between two nodes.
-- arguments: source_id as number
--            destination_id as number
function M.map_remove_route(source_id, destination_id)
    if map_node_list[source_id] == nil
    or map_node_list[destination_id] == nil
    or source_id == destination_id then
        return
    end
    map_remove_oneway_route(source_id, destination_id)
    map_remove_oneway_route(destination_id, source_id)
    map_update_node_type(source_id)
    map_update_node_type(destination_id)
    map_change_iterator = map_change_iterator + 1
end

-- global: Debug draw all map nodes and choose to show node ids or not.
-- arguments: is_show_ids as optional boolean [false]
function M.debug_draw_map_nodes(is_show_ids)
    for node_id, node in pairs(map_node_list) do
        if is_show_ids then
            msg.post("@render:", "draw_text", { text = node_id, position = node.position + vmath.vector3(debug_draw_scale, -debug_draw_scale, 0) } )
        end

        if node.type == NODETYPE.single then
            msg.post("@render:", "draw_line", { start_point = node.position + vmath.vector3(debug_draw_scale, -debug_draw_scale, 0), end_point = node.position + vmath.vector3(-debug_draw_scale, -debug_draw_scale, 0), color = debug_node_color } )
            msg.post("@render:", "draw_line", { start_point = node.position + vmath.vector3(debug_draw_scale, -debug_draw_scale, 0), end_point = node.position + vmath.vector3(0, debug_draw_scale, 0), color = debug_node_color } )
            msg.post("@render:", "draw_line", { start_point = node.position + vmath.vector3(-debug_draw_scale, -debug_draw_scale, 0), end_point = node.position + vmath.vector3(0, debug_draw_scale, 0), color = debug_node_color } )
        end
        
        if node.type == NODETYPE.deadend then
            msg.post("@render:", "draw_line", { start_point = node.position + vmath.vector3(debug_draw_scale, debug_draw_scale, 0), end_point = node.position + vmath.vector3(-debug_draw_scale, -debug_draw_scale, 0), color = debug_node_color } )
            msg.post("@render:", "draw_line", { start_point = node.position + vmath.vector3(-debug_draw_scale, debug_draw_scale, 0), end_point = node.position + vmath.vector3(debug_draw_scale, -debug_draw_scale, 0), color = debug_node_color } )
        end

        if node.type == NODETYPE.intersection then
            msg.post("@render:", "draw_line", { start_point = node.position + vmath.vector3(debug_draw_scale, debug_draw_scale, 0), end_point = node.position + vmath.vector3(debug_draw_scale, -debug_draw_scale, 0), color = debug_node_color } )
            msg.post("@render:", "draw_line", { start_point = node.position + vmath.vector3(-debug_draw_scale, debug_draw_scale, 0), end_point = node.position + vmath.vector3(-debug_draw_scale, -debug_draw_scale, 0), color = debug_node_color } )
            msg.post("@render:", "draw_line", { start_point = node.position + vmath.vector3(-debug_draw_scale, debug_draw_scale, 0), end_point = node.position + vmath.vector3(debug_draw_scale, debug_draw_scale, 0), color = debug_node_color } )
            msg.post("@render:", "draw_line", { start_point = node.position + vmath.vector3(-debug_draw_scale, -debug_draw_scale, 0), end_point = node.position + vmath.vector3(debug_draw_scale, -debug_draw_scale, 0), color = debug_node_color } )
        end

    end
end

-- global: Debug draw all map routes.
function M.debug_draw_map_routes()
    for from_id, routes in pairs(map_route_list) do
        for to_id, route in pairs(routes) do
            if from_id < to_id then
                msg.post("@render:", "draw_line", { start_point = map_node_list[from_id].position, end_point = map_node_list[to_id].position, color = debug_route_color } )
            end
        end
    end
end

-- global: Debug draw player specific path with given color.
-- arguments: movement_data as table
--            color as vector4
--            is_show_intersection as optional boolean [false]
function M.debug_draw_player_move(movement_data, color, is_show_intersection)
    if movement_data.path_index ~= 0 then
        for index = movement_data.path_index, #movement_data.path do
            if index ~= #movement_data.path then
                msg.post("@render:", "draw_line", { start_point = movement_data.path[index], end_point = movement_data.path[index + 1], color = color } )
            end
            if is_show_intersection then
                msg.post("@render:", "draw_line", { start_point = movement_data.path[index] + vmath.vector3(debug_draw_scale + 2, debug_draw_scale + 2, 0), end_point = movement_data.path[index] + vmath.vector3(-debug_draw_scale - 2, -debug_draw_scale - 2, 0), color = color } )
                msg.post("@render:", "draw_line", { start_point = movement_data.path[index] + vmath.vector3(-debug_draw_scale - 2, debug_draw_scale + 2, 0), end_point = movement_data.path[index] + vmath.vector3(debug_draw_scale + 2, -debug_draw_scale - 2, 0), color = color } )
            end
        end
    end
end

-- local: Calculate distance between two vector3.
-- arguments: source as vecotr3
--            destination as vecotr3
-- return: distance as number
local function distance(source, destination)
    return sqrt(pow(source.x - destination.x, 2) + pow(source.y - destination.y, 2))
end

-- local: Shallow copy a table.
-- arguments: table as table
-- return: duplicated table as table
local function shallow_copy(table)
    local new_table = {}
    for key, value in pairs(table) do
        new_table[key] = value
    end
    return new_table
  end

-- local: Calculate the nearest position on the nearest route on the map from the given position.
-- arguments: position as vecotr3
-- return: near_result as table {
--              position_on_route as vecotr3,
--              distance as number
--              route_from_id as number
--              route_to_id as number }
local function calculate_to_nearest_route(position)
    local min_from_id, min_to_id
    local min_near_pos_x, min_near_pos_y
    local min_dist = huge

    for from_id, routes in pairs(map_route_list) do
        for to_id, route in pairs(routes) do
            if from_id < to_id then
                
                local is_between, near_pos_x, near_pos_y, dist, dist_from_id, dist_to_id
                local from_pos = map_node_list[from_id].position
                local to_pos = map_node_list[to_id].position

                -- calculate nearest position for every route to it's line equation
                if from_pos.x ~= to_pos.x then
                    --non vertical
                    near_pos_x = (route.b * ((route.b * position.x) - (route.a * position.y)) - (route.a * route.c))/((route.a * route.a) + (route.b * route.b))
                    near_pos_y = (route.a * ((-route.b * position.x) + (route.a * position.y)) - (route.b * route.c))/((route.a * route.a) + (route.b * route.b))
                else
                    --vertical
                    near_pos_x = from_pos.x
                    near_pos_y = position.y
                end

                -- check if nearest postion is between route nodes
                if (abs(to_pos.x - from_pos.x) >= abs(to_pos.y - from_pos.y)) then
                    if(to_pos.x - from_pos.x) > 0 then 
                        is_between = from_pos.x <= near_pos_x and near_pos_x <= to_pos.x 
                    else
                        is_between = to_pos.x <= near_pos_x and near_pos_x <= from_pos.x
                    end
                else
                    if (to_pos.y - from_pos.y) > 0 then 
                        is_between = from_pos.y <= near_pos_y and near_pos_y <= to_pos.y
                    else
                        is_between = to_pos.y <= near_pos_y and near_pos_y <= from_pos.y
                    end
                end

                -- calculate minimum distance to every routes
                if is_between then
                    dist = abs((route.a * position.x) + (route.b * position.y) + route.c)/sqrt((route.a * route.a) + (route.b * route.b))
                else
                    dist_from_id = distance(position, from_pos)
                    dist_to_id = distance(position, to_pos)
                    if dist_from_id < dist_to_id then
                        dist = dist_from_id
                    else
                        dist = dist_to_id
                    end
                end

                -- update min values if calculated distance is lower
                if dist < min_dist then
                    if is_between then
                        min_dist = dist
                        min_near_pos_x = near_pos_x
                        min_near_pos_y = near_pos_y
                    else
                        if dist_from_id < dist_to_id then
                            min_dist = dist_from_id
                            min_near_pos_x = from_pos.x
                            min_near_pos_y = from_pos.y
                        else
                            min_dist = dist_to_id
                            min_near_pos_x = to_pos.x
                            min_near_pos_y = to_pos.y
                        end
                    end
                    min_from_id = from_id
                    min_to_id = to_id
                end
                
            end
        end
    end

    if min_dist == huge then
        -- if no route exists
        return nil
    else
        return {
            position_on_route = vmath.vector3(min_near_pos_x, min_near_pos_y, 0),
            distance = min_dist,
            route_from_id = min_from_id,
            route_to_id = min_to_id
        }
    end
end

-- local: Calculate graph path inside map from a node to another node.
-- arguments: start_id as number
--            finish_id as number
-- return: path_result as list of table {
--              id as number,
--              distance as number }           
local function calculate_path(start_id, finish_id)
    local previous = {}
    local distances = {}
    local nodes = {}
    local path = nil
    local path_distance = 0

    for node_id in pairs(map_node_list) do
        if node_id == start_id then
            distances[node_id] = 0
        else
            distances[node_id] = huge
        end

        table.insert(nodes, node_id)
    end

    while #nodes ~= 0 do
        table.sort(nodes, function(x, y) return distances[x] < distances[y] end)

        local smallest = nodes[1]
        table.remove(nodes, 1)

        if smallest == finish_id then
            path = {}
            path_distance = 0
            while previous[smallest] ~= nil do

                table.insert(path, 1, { id = smallest, distance = path_distance })
                
                if map_route_list[smallest] == nil then
                    return nil
                end

                if map_route_list[smallest][previous[smallest]] == nil then
                    return nil
                end

                path_distance = path_distance + map_route_list[smallest][previous[smallest]].distance
                smallest = previous[smallest];
            end
            table.insert(path, 1, { id = smallest, distance = path_distance })
            break
        end

        if distances[smallest] == huge then
            break;
        end

        for to_id, neighbor in pairs(map_route_list[smallest]) do
            local alt = distances[smallest] + neighbor.distance
            if alt < distances[to_id] then
                distances[to_id] = alt;
                previous[to_id] = smallest;
            end
        end

    end

    return path
end

-- local: Retrive path results from cache or update cache.
-- arguments: change_number as number
--            from_id as number
--            to_id as number
-- return: cache table as table {
--              change_number as number,
--              distance as number
--              path as list of number }
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
    if pathfinder_cache[from_id] ~= nil then
        local cache = pathfinder_cache[from_id][to_id]
        if cache ~= nil then
            if cache.change_number == change_number then
                return cache
            end
        end
    end

    -- calculate path
    local path = calculate_path(from_id, to_id)
    if path == nil then
        return nil
    end
    
    -- update cache
    local route = {}
    for index = #path, 1, -1 do
        if path[index].distance ~= 0 then
            if pathfinder_cache[path[index].id] == nil then
                pathfinder_cache[path[index].id] = {}
            end

            pathfinder_cache[path[index].id][to_id] = {
                change_number = change_number,
                distance = path[index].distance,
                path = shallow_copy(route)
            }
        end
        table.insert(route, 1, path[index].id)
    end
    
    return pathfinder_cache[from_id][to_id]
end

-- local: Calculate path curvature.
-- arguments: position_list as list table
--            settings_path_curve_tightness as number
--            settings_path_curve_max_distance_from_corner as number
-- return: curve postions as list table of vector3
local function process_path_curvature(position_list, settings_path_curve_tightness, settings_path_curve_max_distance_from_corner)
    if #position_list < 2 then
        return position_list
    end

    local new_position_list = {}
    table.insert(new_position_list, position_list[1])
    for i = 1, #position_list - 1 do
        local Q = (settings_path_curve_tightness - 1) / settings_path_curve_tightness * position_list[i] + position_list[i + 1] / settings_path_curve_tightness
        
        if distance(Q, position_list[i]) > settings_path_curve_max_distance_from_corner then
            Q = vmath.lerp(settings_path_curve_max_distance_from_corner/distance(position_list[i], position_list[i + 1]), position_list[i], position_list[i + 1])
        end
        
        local R = position_list[i] / settings_path_curve_tightness + (settings_path_curve_tightness - 1) / settings_path_curve_tightness * position_list[i + 1]

        if distance(R, position_list[i + 1]) > settings_path_curve_max_distance_from_corner then
            R = vmath.lerp(settings_path_curve_max_distance_from_corner/distance(position_list[i], position_list[i + 1]), position_list[i + 1], position_list[i])
        end

        table.insert(new_position_list, Q)
        table.insert(new_position_list, R)

    end
    table.insert(new_position_list, position_list[#position_list])
    return new_position_list
end

-- local: Initialize moves from source position to a node with an destination node inside the created map.
-- arguments: source_position as vector3
--            destination_id as number
--            settings_go_threshold as number
--            initial_face_vector as vector3
--            current_face_vector as vector3
--            settings_path_curve_tightness as number
--            settings_path_curve_roundness as number
--            settings_path_curve_max_distance_from_corner as number
--            settings_allow_enter_on_route as boolean
-- return: special movement data as table
local function move_internal_initialize(source_position, destination_id, settings_go_threshold, initial_face_vector
    , current_face_vector, settings_path_curve_tightness, settings_path_curve_roundness, settings_path_curve_max_distance_from_corner
    , settings_allow_enter_on_route)
    local near_result = calculate_to_nearest_route(source_position)
    if near_result == nil then
        -- stay until something changes
        return {
            change_number = map_change_iterator,
            destination_id = destination_id,
            path_index = 0,
            path = {},
            initial_face_vector = initial_face_vector,
            current_face_vector = current_face_vector,
            settings_go_threshold = settings_go_threshold,
            settings_path_curve_tightness = settings_path_curve_tightness,
            settings_path_curve_roundness = settings_path_curve_roundness,
            settings_allow_enter_on_route = settings_allow_enter_on_route,
            settings_path_curve_max_distance_from_corner = settings_path_curve_max_distance_from_corner
        }
    else
        local from_path = fetch_path(map_change_iterator, near_result.route_from_id, destination_id)
        local to_path = fetch_path(map_change_iterator, near_result.route_to_id, destination_id)

        local position_list = {}
        table.insert(position_list, source_position)

        if (near_result.distance > settings_go_threshold + 1) and settings_allow_enter_on_route then
            table.insert(position_list, near_result.position_on_route)
        end
        
        if from_path ~= nil and to_path ~= nil then
            local from_distance = from_path.distance + distance(source_position, map_node_list[near_result.route_from_id].position)
            local to_distance = to_path.distance + distance(source_position, map_node_list[near_result.route_to_id].position)

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

        for i = 1, settings_path_curve_roundness do
            position_list = process_path_curvature(position_list, settings_path_curve_tightness, settings_path_curve_max_distance_from_corner)
        end

        table.remove(position_list, 1)
        return {
            change_number = map_change_iterator,
            destination_id = destination_id,
            path_index = 1,
            path = position_list,
            initial_face_vector = initial_face_vector,
            current_face_vector = current_face_vector,
            settings_go_threshold = settings_go_threshold,
            settings_path_curve_tightness = settings_path_curve_tightness,
            settings_path_curve_roundness = settings_path_curve_roundness,
            settings_allow_enter_on_route = settings_allow_enter_on_route,
            settings_path_curve_max_distance_from_corner = settings_path_curve_max_distance_from_corner
        }
    end
end

-- global: Initialize moves from a source position to destination node inside the created map and
-- using given threshold and initial face vector as game object initial face direction and path
-- calculate settings, the optional value will fall back to their default values.
-- arguments: source_position as vector3
--            destination_id as number
--            initial_face_vector as optional vecotr3
--            settings_go_threshold as optional number
--            settings_path_curve_tightness as optional number
--            settings_path_curve_roundness as optional number
--            settings_path_curve_max_distance_from_corner as optional number
--            settings_allow_enter_on_route as optional boolean
-- return: special movement data as table
function M.move_initialize(source_position, destination_id, initial_face_vector, settings_go_threshold
    , settings_path_curve_tightness, settings_path_curve_roundness, settings_path_curve_max_distance_from_corner, settings_allow_enter_on_route)

    if settings_go_threshold == nil then
        settings_go_threshold = settings_main_go_threshold
    end

    if settings_path_curve_roundness == nil then
        settings_path_curve_roundness = settings_main_path_curve_roundness
    end

    if settings_path_curve_tightness == nil then
        settings_path_curve_tightness = settings_main_path_curve_tightness
    end

    if settings_path_curve_max_distance_from_corner == nil then
        settings_path_curve_max_distance_from_corner = settings_main_path_curve_max_distance_from_corner
    end

    if settings_allow_enter_on_route == nil then
        settings_allow_enter_on_route = settings_main_allow_enter_on_route
    end

    return move_internal_initialize(source_position, destination_id, settings_go_threshold, initial_face_vector, initial_face_vector
    , settings_path_curve_tightness, settings_path_curve_roundness, settings_path_curve_max_distance_from_corner, settings_allow_enter_on_route)
end

-- global: Calculate movements from current position of the game object inside the created map
-- considering given speed, using last calculated movement data
-- arguments: current_position as vector3
--            speed as number
--            move_data as table
-- return: new movement data as table
--         move result table {
--              position as vector3,
--              rotation as vector3,
--              is_reached as boolean }
function M.move_player(current_position, speed, move_data)

    -- check for map updates
    if move_data.change_number ~= map_change_iterator then
        move_data = move_internal_initialize(current_position, move_data.destination_id, move_data.settings_go_threshold, move_data.initial_face_vector
        , move_data.current_face_vector, move_data.settings_path_curve_tightness, move_data.settings_path_curve_roundness
        , move_data.settings_path_curve_max_distance_from_corner, move_data.settings_allow_enter_on_route)
    end    

    local rotation
    -- stand still if no route found
    if move_data.path_index == 0 then
        if move_data.initial_face_vector == nil then
            rotation = nil
        else
            rotation = vmath.quat_from_to(move_data.current_face_vector, move_data.initial_face_vector)
        end
        return move_data, { 
            position = current_position,
            rotation = rotation,
            is_reached = false
        }
    end

    -- check for reaching path section
    while distance(current_position, move_data.path[move_data.path_index]) <= move_data.settings_go_threshold + 1 do
        if move_data.path_index == #move_data.path then
            -- reached next path node
            if move_data.initial_face_vector == nil then
                rotation = nil
            else
                rotation = vmath.quat_from_to(move_data.current_face_vector, move_data.initial_face_vector)
            end

            -- reached destination
            local is_reached = true
            if distance(current_position, map_node_list[move_data.destination_id].position) > move_data.settings_go_threshold + 1 then
                is_reached = false
            end

            return move_data, {
                position = current_position,
                rotation = rotation,
                is_reached = is_reached
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
    if move_data.initial_face_vector == nil then
        rotation = nil
    else
        local rotation_vector = vmath.lerp(0.2 * speed, move_data.current_face_vector, direction_vector)
        rotation = vmath.quat_from_to(move_data.initial_face_vector, rotation_vector)
        if rotation.x ~= rotation.x then
            rotation = vmath.quat_rotation_z(pi)
        end
        move_data.current_face_vector = rotation_vector
    end
    return move_data, {
        position = (current_position +  direction_vector * speed),
        rotation = rotation,
        is_reached = false
    }
end

return M