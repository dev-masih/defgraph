-- defgraph/debug.lua
-- All debug drawing functions

local constants = require("defgraph.constants")

-- Shared debug drawing defaults
local debug_node_color          = vmath.vector4(1, 0, 1, 1)
local debug_two_way_route_color = vmath.vector4(0, 1, 0, 1)
local debug_one_way_route_color = vmath.vector4(0, 1, 1, 1)
local debug_draw_scale          = 5

-- ==================== Map Debug Functions ====================

local function debug_set_properties(node_color, two_way_route_color, one_way_route_color, draw_scale)
    debug_node_color          = node_color or debug_node_color
    debug_two_way_route_color = two_way_route_color or debug_two_way_route_color
    debug_one_way_route_color = one_way_route_color or debug_one_way_route_color
    debug_draw_scale          = draw_scale or debug_draw_scale
end

local function debug_draw_map_nodes(self, is_show_ids, is_show_meta)
    local s = debug_draw_scale
    local state = get_map_state(self)

    local up     = vmath.vector3(0,  s, 0)
    local down   = vmath.vector3(0, -s, 0)
    local left   = vmath.vector3(-s, 0, 0)
    local right  = vmath.vector3( s, 0, 0)
    local diag   = vmath.vector3( s,  s, 0)
    local ndiag  = vmath.vector3(-s, -s, 0)

    local text_dy = vmath.vector3(0, -14, 0)

    for node_id, node in pairs(state.map_node_list) do
        local p = node.position

        if is_show_ids then
            msg.post("@render:", "draw_text", {
                text = tostring(node_id),
                position = p + diag
            })
        end

        if is_show_meta then
            local key_text = "(no key)"
            if node.key and type(node.key) == "string" then
                if node.key:sub(1, 26) == "defgraph_default_node_key_" then
                    key_text = "(no key)"
                else
                    key_text = tostring(node.key)
                end
            end

            local groups_text = "(no groups)"
            if node.groups and next(node.groups) then
                local tmp = {}
                for g in pairs(node.groups) do
                    tmp[#tmp+1] = g
                end
                table.sort(tmp)
                groups_text = table.concat(tmp, ", ")
            end

            msg.post("@render:", "draw_text", {
                text = key_text,
                position = p + text_dy * 1
            })

            msg.post("@render:", "draw_text", {
                text = groups_text,
                position = p + text_dy * 2
            })
        end

        if node.type == constants.NODETYPE.SINGLE then
            msg.post("@render:", "draw_line", { start_point = p + up,    end_point = p + left,  color = debug_node_color })
            msg.post("@render:", "draw_line", { start_point = p + left,  end_point = p + right, color = debug_node_color })
            msg.post("@render:", "draw_line", { start_point = p + right, end_point = p + up,    color = debug_node_color })

        elseif node.type == constants.NODETYPE.DEADEND then
            msg.post("@render:", "draw_line", { start_point = p + diag,  end_point = p + ndiag, color = debug_node_color })
            msg.post("@render:", "draw_line", { start_point = p + vmath.vector3(-s, s, 0), end_point = p + vmath.vector3(s, -s, 0), color = debug_node_color })

        elseif node.type == constants.NODETYPE.INTERSECTION then
            msg.post("@render:", "draw_line", { start_point = p + left + up,    end_point = p + right + up,    color = debug_node_color })
            msg.post("@render:", "draw_line", { start_point = p + right + up,   end_point = p + right + down,  color = debug_node_color })
            msg.post("@render:", "draw_line", { start_point = p + right + down, end_point = p + left + down,   color = debug_node_color })
            msg.post("@render:", "draw_line", { start_point = p + left + down,  end_point = p + left + up,     color = debug_node_color })
        end
    end
end

local function debug_draw_map_routes(self)
    local arrow = 6
    local a1 = vmath.vector3( arrow,  arrow, 0)
    local a2 = vmath.vector3( arrow, -arrow, 0)
    local a3 = vmath.vector3(-arrow,  arrow, 0)
    local a4 = vmath.vector3(-arrow, -arrow, 0)

    local state = get_map_state(self)
    local map_node_list  = state.map_node_list
    local map_route_list = state.map_route_list

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

-- ==================== Player Debug Drawing ====================

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

                msg.post("@render:", "draw_line", { start_point = from_pos, end_point = to_pos, color = vmath.vector4(1, 1, 0, 1) })
                msg.post("@render:", "draw_line", { start_point = self_player.current_position, end_point = proj, color = vmath.vector4(1, 1, 0, 1) })

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

        -- Density radius
        do
            local preset = constants.COLLISION_BEHAVIOR_PRESETS[self_player.config.collision_behavior]
            if preset and self_player._debug_density and self_player._debug_density > 0 then
                local density = self_player._debug_density
                local density_radius = radius * preset.density_radius_factor
                local steps_d = 24
                local prev_d = nil

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

        -- Predicted future position
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

        -- Avoidance vector
        if self_player._debug_avoid_x then
            local ax = self_player.current_position.x + self_player._debug_avoid_x * 20
            local ay = self_player.current_position.y + self_player._debug_avoid_y * 20

            msg.post("@render:", "draw_line", {
                start_point = self_player.current_position,
                end_point   = vmath.vector3(ax, ay, 0),
                color       = vmath.vector4(1, 0.8, 0.1, 1)
            })
        end

        -- Final movement direction
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

-- Debug draw group helpers (kept on Map)
local function debug_draw_group(self, group, color, show_projection, show_dirs, show_snap)
    local state = get_map_state(self)
    local g = state.players_by_group[group]
    if not g then return end

    for key in pairs(g) do
        local player = state.players[key]
        if player then
            debug_draw_player(self, player, color, show_projection, show_dirs, show_snap)
        end
    end
end

local function debug_draw_groups(self, groups, color, show_projection, show_dirs, show_snap)
    local state = get_map_state(self)
    local visited = {}

    for i = 1, #groups do
        local group = groups[i]
        local g = state.players_by_group[group]
        if g then
            for key in pairs(g) do
                if not visited[key] then
                    visited[key] = true
                    local player = state.players[key]
                    if player then
                        debug_draw_player(self, player, color, show_projection, show_dirs, show_snap)
                    end
                end
            end
        end
    end
end

-- Export
return {
    debug_set_properties = debug_set_properties,
    debug_draw_map_nodes = debug_draw_map_nodes,
    debug_draw_map_routes = debug_draw_map_routes,
    debug_draw_player = debug_draw_player,
    debug_draw_group = debug_draw_group,
    debug_draw_groups = debug_draw_groups,
}