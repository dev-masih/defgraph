-- DefGraph
-- This module contains functions to create a world map as a shape of a graph
-- and the ability to manipulate it at any time, easily see debug draw of This
-- graph and move go's inside of this graph with utilizing auto pathfilder.

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

-- local: color vectors for debug drawing
local debug_node_color = vmath.vector4(1, 0, 1, 1)
local debug_route_color = vmath.vector4(0, 1, 0, 1)

-- local: scale of node symboles for debug drawing
local debug_draw_scale = 5

-- local: math functions
local sqrt = math.sqrt
local pow = math.pow
local abs = math.abs
local huge = math.huge

-- global: set debug drawing properties
function M.debug_set_properties(node_color, route_color, draw_scale)
    debug_node_color = node_color
    debug_route_color = route_color
    debug_draw_scale = 5
end

-- local: count size of non-sequences table
local function table_size(table)
    local count = 0
    for _ in pairs(table) do
        count = count + 1
    end
    return count
end

-- local: Add one way route from node source_id to node destination_id
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

-- local: update node type parameter
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

-- local: remove an existing route between source_id and destination_id nodes
local function map_remove_oneway_route(source_id, destination_id)
    if map_route_list[source_id] ~= nil then
        map_route_list[source_id][destination_id] = nil
        if table_size(map_route_list[source_id]) == 0 then
            map_route_list[source_id] = nil
        end
    end
end

-- global: Adding a node at the given position (position.z will get ignored)
-- return: Added node id
function M.map_add_node(position)
    map_node_id_iterator = map_node_id_iterator + 1
    local node_id = map_node_id_iterator
    map_node_list[node_id] = { position = vmath.vector3(position.x, position.y, 0), type = NODETYPE.single }
    map_change_iterator = map_change_iterator + 1
    return node_id
end

-- global: Adding a two way route between nodes with id of source_id and destination_id
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

-- global: Removing an existing route between nodes with id of source_id and destination_id
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


-- global: debug draw all map nodes and choose to show node ids or not
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

-- global: debug draw all map routes
function M.debug_draw_map_routes()
    for from_id, routes in pairs(map_route_list) do
        for to_id, route in pairs(routes) do
            if from_id < to_id then
                msg.post("@render:", "draw_line", { start_point = map_node_list[from_id].position, end_point = map_node_list[to_id].position, color = debug_route_color } )
            end
        end
    end
end

-- global: debug draw player specific movement_data with given color
function M.debug_draw_player_move(movement_data, color)
    local next_position = movement_data.next_position
    msg.post("@render:", "draw_line", { start_point = next_position + vmath.vector3(debug_draw_scale, debug_draw_scale, 0), end_point = next_position + vmath.vector3(-debug_draw_scale, -debug_draw_scale, 0), color = color } )
    msg.post("@render:", "draw_line", { start_point = next_position + vmath.vector3(-debug_draw_scale, debug_draw_scale, 0), end_point = next_position + vmath.vector3(debug_draw_scale, -debug_draw_scale, 0), color = color } )
end


-- local: calculate distance between two vector 3
local function distance(source, destination)
    return sqrt(pow(source.x - destination.x, 2) + pow(source.y - destination.y, 2))
end

-- local: calculate neareset position on nearest route on map to given position
-- return: table include vecotr3 for position on a nearest route, distance to that position and node ids for that nearest route
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

-- local: calculate graph path inside map from node id of start_id to finish_id
-- return: list of node ids, total distance of path
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

-- local: retrive path results from cache or update cache
-- return: two next node ids and distance to destination
function M.fetch_path(change_number, from_id, to_id)

    -- TODO
    -- if from_id == to_id then
    --     return from_id, from_id, 0
    -- end

    -- TODO
    -- retrive result from cache
    -- if pathfinder_cache[from_id] ~= nil then
    --     local cache = pathfinder_cache[from_id][to_id]
    --     if cache ~= nil then
    --         if cache.change_number == change_number then
    --             return cache.next_node_1_id, cache.next_node_2_id, cache.distance
    --         end
    --     end
    -- end

    -- update cache if not exists or old
    local path = calculate_path(from_id, to_id)
    
    local distance = path[1].distance
    local path_next_1 = path[1].id
    local path_next_2 = path[1].id
    if #path > 1 then
        path_next_2 = path[2].id
    end

    if pathfinder_cache[from_id] == nil then
        pathfinder_cache[from_id] = {}
    end

    pathfinder_cache[from_id][to_id] = {
        change_number = change_number,
        distance = distance,
        next_node_1_id = path_next_1,
        next_node_2_id = path_next_2
    }
    
    for path_index = 1, #path do

        if path_index >= #path - 1 then
            break
        end
        
        if pathfinder_cache[path[path_index].id] == nil then
            pathfinder_cache[path[path_index].id] = {}
        end

        pathfinder_cache[path[path_index].id][to_id] = {
            change_number = change_number,
            distance = path[path_index + 1].distance,
            next_node_1_id = path[path_index + 1].id,
            next_node_2_id = path[path_index + 2].id
        }
    end
    
    return path_next_1, path_next_2, distance
end

-- local: rethink moves from source_position to destination_position and use last calculated movement data
-- return: new movement data table
local function rethink_move(source_position, destination_position, move_data)
    local new_move_data = {}
    new_move_data.change_number = move_data.change_number
    new_move_data.threshold = move_data.threshold
    new_move_data.last_position = destination_position
    new_move_data.near_result = move_data.near_result
    new_move_data.destination_id = move_data.destination_id
    
    if distance(source_position, move_data.near_result.position) <= move_data.threshold
    and distance(source_position, map_node_list[move_data.near_result.from_id].position) > move_data.threshold
    and distance(source_position, map_node_list[move_data.near_result.to_id].position) > move_data.threshold then
        -- i'm on a route
        if move_data.near_result.from_id == move_data.destination_id or move_data.near_result.to_id == move_data.destination_id then
            -- i'm on same route as destination
            new_move_data.next_position = destination_position
            return new_move_data
        else
            -- i'm not on same route as destination

            local _, _, from_distance = fetch_pathfinder(move_data.change_number, move_data.near_result.from_id, move_data.destination_id)

            if from_distance == nil then
                new_move_data.next_position = source_position
                return new_move_data
            end
            
            local _, _, to_distance = fetch_pathfinder(move_data.change_number, move_data.near_result.to_id, move_data.destination_id)
            
            from_distance = from_distance + distance(source_position, map_node_list[move_data.near_result.from_id].position)
            to_distance = to_distance + distance(source_position, map_node_list[move_data.near_result.to_id].position)

            if from_distance <= to_distance then
                new_move_data.next_position = map_node_list[move_data.near_result.from_id].position
            else
                new_move_data.next_position = map_node_list[move_data.near_result.to_id].position
            end
            
            return new_move_data
        end
    else
        if distance(source_position, map_node_list[move_data.near_result.from_id].position) <= move_data.threshold then
            -- i'm on corner (near from_id)
            local from_path_1, from_path_2 = fetch_pathfinder(move_data.change_number, move_data.near_result.from_id, move_data.destination_id)

            if from_path_1 == nil then
                new_move_data.next_position = source_position
                return new_move_data
            end
            
            new_move_data.next_position = map_node_list[from_path_1].position            
            new_move_data.near_result.position = source_position
            new_move_data.near_result.distance = 0
            new_move_data.near_result.from_id = from_path_1
            new_move_data.near_result.to_id = from_path_2

        elseif distance(source_position, map_node_list[move_data.near_result.to_id].position) <= move_data.threshold then
            -- i'm on corner (near to_id)
            local to_path_1, to_path_2 = fetch_pathfinder(move_data.change_number, move_data.near_result.to_id, move_data.destination_id)

            if to_path_1 == nil then
                new_move_data.next_position = source_position
                return new_move_data
            end
            
            new_move_data.next_position = map_node_list[to_path_1].position
            new_move_data.near_result.position = source_position
            new_move_data.near_result.distance = 0
            new_move_data.near_result.from_id = to_path_1
            new_move_data.near_result.to_id = to_path_2

        else
            -- i'm not on a route
            new_move_data.next_position = move_data.near_result.position
        end
        return new_move_data
    end
end

-- global: initialize moves from source_position to node with id of destination_id inside
--         map with specified threshold in position calculations
-- return: movement data table
function M.move_initialize(source_position, threshold, destination_id)
    local destination_position = map_node_list[destination_id].position
    local near_result = calculate_to_nearest_route(source_position)

    local first_move_data = {
        change_number = map_change_iterator,
        threshold = threshold,
        next_position = source_position,
        last_position = destination_position,
        near_result = near_result,
        destination_id = destination_id
    }
    
    if near_result == nil then
        return first_move_data
    else
        return rethink_move(source_position, destination_position, first_move_data)
    end
end

-- global: calculate movements from current_position inside given map considering given
--         speed and dt useing last calculated movement data
-- return: new position for movement, new movement data table
function M.move_player(current_position, speed, move_data)
    -- check for map updates
    if move_data.change_number ~= map_change_iterator then
        move_data = M.move_initialize(current_position, move_data.threshold, move_data.destination_id)
    end

    -- check for reaching destination
    if distance(move_data.last_position, current_position) >= move_data.threshold then

        -- check for reaching next position
        local direction_vector = move_data.next_position - current_position
        if distance(move_data.next_position, current_position) >= move_data.threshold then
            direction_vector.z = 0
            direction_vector = vmath.normalize(direction_vector)
            return (current_position +  direction_vector * speed), move_data, false
        else
            -- I reached next_position, now rethink next position
            if move_data.near_result == nil then
                return current_position, move_data, false
            else
                return current_position, rethink_move(current_position, move_data.last_position, move_data), false
            end
        end
    end
    
    return current_position, move_data, true
end

return M