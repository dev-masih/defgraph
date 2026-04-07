-- defgraph/curvature.lua
-- Path curvature processing and movement initialization

local constants = require("defgraph.constants")

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

    local bc_dist = constants.distance(before, current)
    local ca_dist = constants.distance(current, after)

    if bc_dist > 0 then
        if constants.distance(Q_before, before) > path_curve_max_distance_from_corner then
            Q_before = vmath.lerp(path_curve_max_distance_from_corner / bc_dist, before, current)
        end
        if constants.distance(R_before, current) > path_curve_max_distance_from_corner then
            R_before = vmath.lerp(path_curve_max_distance_from_corner / bc_dist, current, before)
        end
    end

    if ca_dist > 0 then
        if constants.distance(Q_after, current) > path_curve_max_distance_from_corner then
            Q_after = vmath.lerp(path_curve_max_distance_from_corner / ca_dist, current, after)
        end
        if constants.distance(R_after, after) > path_curve_max_distance_from_corner then
            R_after = vmath.lerp(path_curve_max_distance_from_corner / ca_dist, after, current)
        end
    end

    if roundness ~= 1 and roundness > 0 then
        local _, Qb, _ = process_path_curvature(Q_before, R_before, Q_after, roundness - 1,
                               path_curve_tightness, path_curve_max_distance_from_corner, out_list)
        local _, _, Ra = process_path_curvature(R_before, Q_after, R_after, roundness - 1,
                               path_curve_tightness, path_curve_max_distance_from_corner, out_list)
        return out_list, Qb, Ra
    else
        out_list[#out_list + 1] = R_before
        out_list[#out_list + 1] = Q_after
        return out_list, Q_before, R_after
    end
end

-- ==================== Movement Initialization (Full Implementation) ====================

local function move_internal_initialize(self, source_position, move_data)
    local targets = move_data.targets
    local dest_index = move_data.destination_index or 1
    local current_target = targets and targets[dest_index] or nil

    if not current_target then
        move_data.path = {source_position}
        move_data.path_index = 1
        return move_data
    end

    local is_vector = type(current_target) == "userdata"
    local graph_target = is_vector and nil or current_target

    local near_result = self:calculate_to_nearest_route(source_position)
    if not near_result then
        move_data.path = {source_position, current_target}
        move_data.path_index = 1
        return move_data
    end

    local state = self:get_map_state()
    local map_node_list  = state.map_node_list
    local map_route_list = state.map_route_list

    local position_list = {}
    local node_ids_list = {}

    position_list[1] = source_position
    local pos_count = 1

    -- Entry projection when starting off-route
    if (near_result.distance > move_data.config.gameobject_threshold + 1) and move_data.config.allow_enter_on_route then
        pos_count = pos_count + 1
        position_list[pos_count] = near_result.position_on_route
    end

    if not is_vector then
        -- NODE target (unchanged)
        local from_path, to_path

        if map_route_list[near_result.route_to_id] and map_route_list[near_result.route_to_id][near_result.route_from_id] then
            from_path = self:fetch_path(near_result.route_from_id, graph_target)
        end
        if map_route_list[near_result.route_from_id] and map_route_list[near_result.route_from_id][near_result.route_to_id] then
            to_path = self:fetch_path(near_result.route_to_id, graph_target)
        end

        if from_path or to_path then
            local from_distance = math.huge
            local to_distance   = math.huge

            local from_node_pos = map_node_list[near_result.route_from_id].position
            local to_node_pos   = map_node_list[near_result.route_to_id].position

            if from_path then from_distance = from_path.distance + constants.distance(source_position, from_node_pos) end
            if to_path   then to_distance   = to_path.distance   + constants.distance(source_position, to_node_pos)   end

            if from_distance <= to_distance then
                pos_count = pos_count + 1
                position_list[pos_count] = from_node_pos
                node_ids_list[#node_ids_list + 1] = near_result.route_from_id
                local fp = from_path.path
                for j = 2, #fp do
                    pos_count = pos_count + 1
                    position_list[pos_count] = map_node_list[fp[j]].position
                    node_ids_list[#node_ids_list + 1] = fp[j]
                end
            else
                pos_count = pos_count + 1
                position_list[pos_count] = to_node_pos
                node_ids_list[#node_ids_list + 1] = near_result.route_to_id
                local tp = to_path.path
                for j = 2, #tp do
                    pos_count = pos_count + 1
                    position_list[pos_count] = map_node_list[tp[j]].position
                    node_ids_list[#node_ids_list + 1] = tp[j]
                end
            end
        end

    else
        ------------------------------------------------------------------
        -- VECTOR3 target - Always do graph pathfinding
        ------------------------------------------------------------------
        local target_vec = current_target
        local exit_near = self:calculate_to_nearest_route(target_vec)

        if exit_near then
            local exit_from_id = exit_near.route_from_id
            local exit_to_id   = exit_near.route_to_id

            print("DEBUG: VECTOR3 - exit route", exit_from_id, "↔", exit_to_id)

            -- Check if already on the exit route
            local on_same_route = (near_result.route_from_id == exit_from_id or near_result.route_from_id == exit_to_id) and
                                  (near_result.route_to_id   == exit_from_id or near_result.route_to_id   == exit_to_id)

            if on_same_route then
                print("DEBUG:   Already on exit route → direct to projection")
                if move_data.config.allow_exit_on_route and exit_near.distance > move_data.config.gameobject_threshold + 1 then
                    pos_count = pos_count + 1
                    position_list[pos_count] = exit_near.position_on_route
                    print("DEBUG:   Added exit projection (same route)")
                end
            else
                -- Find last graph node (or use current nearest node if no previous path)
                local last_node = nil
                if move_data.path_node_ids and #move_data.path_node_ids > 0 then
                    last_node = move_data.path_node_ids[#move_data.path_node_ids]
                else
                    -- First destination is a vector3 → use nearest node as starting point
                    last_node = near_result.route_from_id   -- or near_result.route_to_id, doesn't matter
                end

                local path_to_from = nil
                local path_to_to   = nil

                if last_node then
                    path_to_from = map_route_list[last_node] and self:fetch_path(last_node, exit_from_id) or nil
                    path_to_to   = map_route_list[last_node] and self:fetch_path(last_node, exit_to_id)   or nil
                end

                if path_to_from or path_to_to then
                    local from_node_pos = map_node_list[exit_from_id].position
                    local to_node_pos   = map_node_list[exit_to_id].position

                    local from_total = path_to_from and (path_to_from.distance + constants.distance(from_node_pos, exit_near.position_on_route)) or math.huge
                    local to_total   = path_to_to   and (path_to_to.distance   + constants.distance(to_node_pos,   exit_near.position_on_route)) or math.huge

                    print("DEBUG:   Gateway", exit_from_id, "full cost =", from_total)
                    print("DEBUG:   Gateway", exit_to_id,   "full cost =", to_total)

                    if from_total <= to_total then
                        print("DEBUG:   → Chose gateway", exit_from_id)
                        local fp = path_to_from.path
                        for j = 1, #fp do
                            pos_count = pos_count + 1
                            position_list[pos_count] = map_node_list[fp[j]].position
                            node_ids_list[#node_ids_list + 1] = fp[j]
                        end
                    else
                        print("DEBUG:   → Chose gateway", exit_to_id)
                        local tp = path_to_to.path
                        for j = 1, #tp do
                            pos_count = pos_count + 1
                            position_list[pos_count] = map_node_list[tp[j]].position
                            node_ids_list[#node_ids_list + 1] = tp[j]
                        end
                    end
                end

                if move_data.config.allow_exit_on_route and exit_near.distance > move_data.config.gameobject_threshold + 1 then
                    pos_count = pos_count + 1
                    position_list[pos_count] = exit_near.position_on_route
                    print("DEBUG:   Added exit projection")
                end
            end
        end
    end

    -- Final target
    pos_count = pos_count + 1
    if is_vector then
        position_list[pos_count] = current_target
    else
        position_list[pos_count] = map_node_list[graph_target].position
    end

    -- Build final path
    local path = move_data.path
    for i = 1, #path do path[i] = nil end

    if move_data.config.path_curve_roundness ~= 0 and #position_list > 2 then
        path[1] = position_list[1]
        local path_count = 1
        for i = 2, #position_list - 1 do
            local curve_temp = move_data._curve_temp or {}
            move_data._curve_temp = curve_temp
            for k = 1, #curve_temp do curve_temp[k] = nil end

            local partial, Qb, Ra = process_path_curvature(
                position_list[i-1], position_list[i], position_list[i+1],
                move_data.config.path_curve_roundness,
                move_data.config.path_curve_tightness,
                move_data.config.path_curve_max_distance_from_corner,
                curve_temp)

            if i == 2 then
                path_count = path_count + 1
                path[path_count] = Qb
            end

            for k = 1, #partial do
                path_count = path_count + 1
                path[path_count] = partial[k]
            end

            if i == #position_list - 1 then
                path_count = path_count + 1
                path[path_count] = Ra
            end
        end
        path[#path + 1] = position_list[#position_list]
    else
        for i = 1, #position_list do
            path[i] = position_list[i]
        end
    end

    move_data.path_index    = 1
    move_data.path_node_ids = node_ids_list
    move_data.path_version  = self:compute_path_version(node_ids_list)

    return move_data
end

-- Export
return {
    move_internal_initialize = move_internal_initialize,
}