-- defgraph/curvature_module.lua
-- Path curvature processing and movement initialization

local constants_module = require("defgraph.constants")

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

    -- Guard zero-length segments and reuse distances
    local bc_dist = constants_module.distance(before, current)
    local ca_dist = constants_module.distance(current, after)

    if bc_dist > 0 then
        if constants_module.distance(Q_before, before) > path_curve_max_distance_from_corner then
            Q_before = vmath.lerp(path_curve_max_distance_from_corner / bc_dist, before, current)
        end
        if constants_module.distance(R_before, current) > path_curve_max_distance_from_corner then
            R_before = vmath.lerp(path_curve_max_distance_from_corner / bc_dist, current, before)
        end
    end

    if ca_dist > 0 then
        if constants_module.distance(Q_after, current) > path_curve_max_distance_from_corner then
            Q_after = vmath.lerp(path_curve_max_distance_from_corner / ca_dist, current, after)
        end
        if constants_module.distance(R_after, after) > path_curve_max_distance_from_corner then
            R_after = vmath.lerp(path_curve_max_distance_from_corner / ca_dist, after, current)
        end
    end

    if roundness ~= 1 and roundness > 0 then
        -- FIXED: Properly capture boundary points from deeper recursion levels
        local _, Qb, _ = process_path_curvature(Q_before, R_before, Q_after, roundness - 1,
                               path_curve_tightness,
                               path_curve_max_distance_from_corner,
                               out_list)
        local _, _, Ra = process_path_curvature(R_before, Q_after, R_after, roundness - 1,
                               path_curve_tightness,
                               path_curve_max_distance_from_corner,
                               out_list)
        return out_list, Qb, Ra
    else
        out_list[#out_list + 1] = R_before
        out_list[#out_list + 1] = Q_after
        return out_list, Q_before, R_after
    end
end

-- ==================== Movement Initialization ====================

local function move_internal_initialize(self, source_position, move_data)
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
    local state = self:get_map_state()
    local map_route_list = state.map_route_list

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

    if (near_result.distance > move_data.config.gameobject_threshold + 1) and move_data.config.allow_enter_on_route then
        pos_count = pos_count + 1
        position_list[pos_count] = near_result.position_on_route
    end

    local map_node_list = state.map_node_list

    if from_path or to_path then
        local from_distance = math.huge
        local to_distance   = math.huge

        local from_node_pos = map_node_list[near_result.route_from_id].position
        local to_node_pos   = map_node_list[near_result.route_to_id].position

        if from_path then
            from_distance = from_path.distance + constants_module.distance(source_position, from_node_pos)
        end
        if to_path then
            to_distance = to_path.distance + constants_module.distance(source_position, to_node_pos)
        end

        if from_distance <= to_distance then
            pos_count = pos_count + 1
            position_list[pos_count] = from_node_pos
            node_ids_list[#node_ids_list + 1] = near_result.route_from_id

            local fp = from_path.path
            -- SKIP the first node, it's the same as from_node_pos
            for i = 2, #fp do
                pos_count = pos_count + 1
                position_list[pos_count] = map_node_list[fp[i]].position
                node_ids_list[#node_ids_list + 1] = fp[i]
            end
        else
            pos_count = pos_count + 1
            position_list[pos_count] = to_node_pos
            node_ids_list[#node_ids_list + 1] = near_result.route_to_id

            local tp = to_path.path
            -- SKIP the first node, it's the same as to_node_pos
            for i = 2, #tp do
                pos_count = pos_count + 1
                position_list[pos_count] = map_node_list[tp[i]].position
                node_ids_list[#node_ids_list + 1] = tp[i]
            end
        end
    end

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
                process_path_curvature(position_list[i - 1], position_list[i], position_list[i + 1],
                                       move_data.config.path_curve_roundness,
                                       move_data.config.path_curve_tightness,
                                       move_data.config.path_curve_max_distance_from_corner,
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

-- Export functions
return {
    move_internal_initialize   = move_internal_initialize,
}