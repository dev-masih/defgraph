-- defgraph/pathfinding.lua
-- Pathfinding, nearest route, and related functions

local constants_module = require("defgraph.constants")

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

-- ==================== Nearest Route ====================

local function calculate_to_nearest_route(self, position)
    local state = self:get_map_state()
    local map_node_list  = state.map_node_list
    local map_route_list = state.map_route_list

    local min_from, min_to
    local min_x, min_y
    local min_dist = math.huge

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

                if math.abs(to_pos.x - from_pos.x) >= math.abs(to_pos.y - from_pos.y) then
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
                        inv_len = 1 / math.sqrt(ab_len2)
                        route.ab_len2    = ab_len2
                        route.inv_ab_len = inv_len
                    end
                    dist = math.abs(route.a * position.x + route.b * position.y + route.c) * inv_len
                else
                    local d1 = constants_module.distance(position, from_pos)
                    local d2 = constants_module.distance(position, to_pos)
                    dist = (d1 < d2) and d1 or d2
                end

                if dist < min_dist then
                    min_dist = dist
                    if is_between then
                        min_x, min_y = near_x, near_y
                    else
                        if constants_module.distance(position, from_pos) < constants_module.distance(position, to_pos) then
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

    if min_dist == math.huge then
        return nil
    end

    return {
        position_on_route = vmath.vector3(min_x, min_y, 0),
        distance          = min_dist,
        route_from_id     = min_from,
        route_to_id       = min_to,
    }
end

-- ==================== Pathfinding ====================

-- Note: path[1].distance = total distance from start to end (remaining distance decreases)
function calculate_path(self, start_id, finish_id)
    local state = self:get_map_state()
    local map_node_list  = state.map_node_list
    local map_route_list = state.map_route_list

    local previous  = {}
    local distances = {}
    local visited   = {}
    local heap      = {}

    for node_id in pairs(map_node_list) do
        distances[node_id] = math.huge
    end

    distances[start_id] = 0
    heap_push(heap, start_id, 0)

    while true do
        local current, current_dist = heap_pop(heap)
        if not current then
            return nil
        end

        if current_dist == math.huge then
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

function fetch_path(self, from_id, to_id)
    local state = self:get_map_state()
    local pathfinder_cache = state.pathfinder_cache

    if from_id == to_id then
        local ids = { from_id }
        local node_versions = { state.node_version[from_id] or 0 }
        return {
            distance       = 0,
            path           = ids,
            node_versions  = node_versions,
            route_versions = {},
        }
    end

    local row = pathfinder_cache[from_id]
    if row then
        local cache = row[to_id]
        if cache and self:is_path_cache_valid(cache) then
            return cache
        end
    end

    local path_nodes = self.calculate_path(self, from_id, to_id)
    if not path_nodes or #path_nodes == 0 then
        return nil
    end

    local route = {}
    local route_count = #path_nodes
    for i = 1, route_count do
        route[i] = path_nodes[i].id
    end

    row = pathfinder_cache[from_id]
    if not row then
        row = {}
        pathfinder_cache[from_id] = row
    end

    for index = route_count, 1, -1 do
        local node = path_nodes[index]
        if node.distance ~= 0 then
            local nid = node.id

            local cache_row = pathfinder_cache[nid]
            if not cache_row then
                cache_row = {}
                pathfinder_cache[nid] = cache_row
            end

            local sub_len = route_count - index + 1
            local node_ids = {}
            for j = 1, sub_len do
                node_ids[j] = route[index + j - 1]
            end

            local node_versions = {}
            local route_versions = {}

            for j = 1, sub_len do
                node_versions[j] = state.node_version[node_ids[j]] or 0
            end

            for j = 1, sub_len - 1 do
                local a = node_ids[j]
                local b = node_ids[j + 1]
                local rv_row = state.route_version[a]
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

-- Expose functions to be used by Map
return {
    calculate_to_nearest_route = calculate_to_nearest_route,
    calculate_path             = calculate_path,
    fetch_path                 = fetch_path,
}