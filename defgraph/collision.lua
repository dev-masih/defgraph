-- defgraph/collision.lua
-- Collision avoidance system

local constants_module = require("defgraph.constants")

local function compute_collision_avoidance(map, self_player, dir_x, dir_y, speed)
    local cfg = self_player.config
    if not cfg.collision_enabled then
        self_player._debug_avoid_x = 0
        self_player._debug_avoid_y = 0
        self_player._debug_final_x = dir_x
        self_player._debug_final_y = dir_y
        self_player._debug_density = 0

        self_player._last_dir_x    = dir_x
        self_player._last_dir_y    = dir_y
        self_player._last_speed    = speed

        self_player._smooth_speed  = speed
        self_player._smooth_dir_x  = dir_x
        self_player._smooth_dir_y  = dir_y
        return dir_x, dir_y, speed
    end

    local preset = constants_module.COLLISION_BEHAVIOR_PRESETS[cfg.collision_behavior]

    local px = self_player.current_position.x
    local py = self_player.current_position.y

    local radius    = cfg.collision_radius
    local radius_sq = radius * radius

    local avoid_x, avoid_y = 0, 0
    local slow_factor      = 1

    local strongest_reactive   = 0
    local strongest_predictive = 0
    local strongest_queueing   = 0

    local density_radius = radius * preset.density_radius_factor
    local density_radius_sq = density_radius * density_radius
    local neighbor_count = 0
    local density_sum = 0

    -- dynamic lookahead
    local lookahead = preset.lookahead_min + speed * preset.lookahead_speed_factor
    if lookahead > preset.lookahead_max then
        lookahead = preset.lookahead_max
    elseif lookahead < preset.lookahead_min then
        lookahead = preset.lookahead_min
    end

    local future_px = px + dir_x * speed * lookahead
    local future_py = py + dir_y * speed * lookahead

    -- reuse per-player candidates table
    local candidates = self_player._scratch_candidates or {}
    self_player._scratch_candidates = candidates
    local count = 0

    -- clear previous contents
    for i = 1, #candidates do candidates[i] = nil end

    local map_state = map:get_map_state()

    if cfg.collision_groups then
        for _, group in ipairs(cfg.collision_groups) do
            local cached = map_state.collision_candidate_cache[group]
            if not cached then
                cached = {}
                local g = map_state.players_by_group[group]
                if g then
                    for key in pairs(g) do
                        cached[#cached + 1] = map_state.players[key]
                    end
                end
                map_state.collision_candidate_cache[group] = cached
            end
            for j = 1, #cached do
                count = count + 1
                candidates[count] = cached[j]
            end
        end
    else
        -- full list fallback
        for _, p in pairs(map_state.players) do
            count = count + 1
            candidates[count] = p
        end
    end

    -- path perpendicular
    local lx = -dir_y
    local ly =  dir_x

    -- main loop
    for i = 1, count do
        local other = candidates[i]
        if other ~= self_player then
            local ox = other.current_position.x
            local oy = other.current_position.y

            -- predict other
            local ofx = ox
            local ofy = oy

            local odx = other._last_dir_x
            if odx then
                local ospeed = other._last_speed
                local ody = other._last_dir_y
                ofx = ox + odx * ospeed * lookahead
                ofy = oy + ody * ospeed * lookahead
            end

            -- current distance
            local dx = px - ox
            local dy = py - oy
            local dist_sq = dx*dx + dy*dy

            -- future distance
            local fdx = future_px - ofx
            local fdy = future_py - ofy
            local fdist_sq = fdx*fdx + fdy*fdy

            -- 1. Reactive avoidance
            if dist_sq < radius_sq and dist_sq > 0 then
                local dist = math.sqrt(dist_sq)
                local overlap = (radius - dist) * (1 / radius)

                if overlap > strongest_reactive then
                    strongest_reactive = overlap
                end

                local inv_dist = 1 / dist
                local rx = dx * inv_dist
                local ry = dy * inv_dist
                local lateral = rx * lx + ry * ly
                if lateral == 0 then
                    lateral = (self_player.id % 2 == 0) and 1 or -1
                end

                local force = overlap * (radius * preset.reactive_scale)
                local lat_force = lateral * force
                avoid_x = avoid_x + lx * lat_force
                avoid_y = avoid_y + ly * lat_force

                local dot = dx * dir_x + dy * dir_y
                if dot < 0 then
                    local factor = 1 - overlap * preset.reactive_slow
                    if factor < slow_factor then
                        slow_factor = factor
                    end
                end
            end

            -- 2. Predictive avoidance
            if fdist_sq < radius_sq and fdist_sq > 0 then
                local fdist = math.sqrt(fdist_sq)
                local foverlap = (radius - fdist) * (1 / radius)

                if foverlap > strongest_predictive then
                    strongest_predictive = foverlap
                end

                local inv_fdist = 1 / fdist
                local rx = fdx * inv_fdist
                local ry = fdy * inv_fdist
                local lateral = rx * lx + ry * ly
                if lateral == 0 then
                    lateral = (self_player.id % 2 == 0) and 1 or -1
                end

                local force = foverlap * (radius * preset.predictive_scale)
                local lat_force = lateral * force
                avoid_x = avoid_x + lx * lat_force
                avoid_y = avoid_y + ly * lat_force

                local dot = fdx * dir_x + fdy * dir_y
                if dot < 0 then
                    local factor = 1 - foverlap * preset.predictive_slow
                    if factor < slow_factor then
                        slow_factor = factor
                    end
                end
            end

            -- 3. Queueing
            local odx2 = other._last_dir_x
            if odx2 then
                local ody2 = other._last_dir_y
                local align = dir_x * odx2 + dir_y * ody2
                if align > 0.7 then
                    local dx2 = ox - px
                    local dy2 = oy - py
                    local dist2_sq = dx2*dx2 + dy2*dy2

                    local desired = radius * preset.queue_spacing_factor
                    local desired_sq = desired * desired

                    if dist2_sq < desired_sq and dist2_sq > 0 then
                        local dist2 = math.sqrt(dist2_sq)
                        local overlap2 = (desired - dist2) / desired

                        if overlap2 > strongest_queueing then
                            strongest_queueing = overlap2
                        end

                        local factor = 1 - overlap2 * preset.queue_slow
                        if factor < slow_factor then
                            slow_factor = factor
                        end

                        local back_force = overlap2 * (radius * 0.2)
                        avoid_x = avoid_x - dir_x * back_force
                        avoid_y = avoid_y - dir_y * back_force

                        local side = (self_player.id % 2 == 0) and 1 or -1
                        local side_force = overlap2 * 0.1
                        avoid_x = avoid_x + (-dir_y) * side * side_force
                        avoid_y = avoid_y + ( dir_x) * side * side_force
                    end
                end
            end

            -- Density accumulation (merged)
            local dx_density = px - ox
            local dy_density = py - oy
            local dist_density_sq = dx_density*dx_density + dy_density*dy_density

            if dist_density_sq < density_radius_sq then
                neighbor_count = neighbor_count + 1
                density_sum = density_sum + (1 - dist_density_sq / density_radius_sq)
            end
        end
    end

    local density = 0
    if neighbor_count > 0 then
        density = density_sum / neighbor_count
        local density_slow = 1 - density * preset.density_slow_factor
        if density_slow < slow_factor then
            slow_factor = density_slow
        end
    end

    self_player._debug_density = density

    -- no avoidance
    if strongest_reactive == 0 and strongest_predictive == 0 and strongest_queueing == 0 then
        self_player._debug_avoid_x = 0
        self_player._debug_avoid_y = 0
        self_player._debug_final_x = dir_x
        self_player._debug_final_y = dir_y

        self_player._last_dir_x   = dir_x
        self_player._last_dir_y   = dir_y
        self_player._last_speed   = speed

        self_player._smooth_speed = speed
        self_player._smooth_dir_x = dir_x
        self_player._smooth_dir_y = dir_y

        return dir_x, dir_y, speed
    end

    -- combine forces
    local predictive_weight = strongest_predictive * 0.6
    if predictive_weight > 1 then
        predictive_weight = 1
    end

    local base_weight = 1 - predictive_weight
    if base_weight < 0 then
        base_weight = 0
    end

    local raw_x = dir_x * base_weight + avoid_x
    local raw_y = dir_y * base_weight + avoid_y

    -- normalize
    local len = raw_x*raw_x + raw_y*raw_y
    if len > 0 then
        local inv = 1 / math.sqrt(len)
        raw_x = raw_x * inv
        raw_y = raw_y * inv
    else
        raw_x, raw_y = 0, 0
    end

    -- path recentering (relaxed during collision)
    local alignment = raw_x * dir_x + raw_y * dir_y
    if alignment < 0.6 then
        local recenter_strength = preset.path_recentering

            -- dynamically reduce recentering when we are actively avoiding
        if strongest_reactive > 0 or strongest_predictive > 0 or strongest_queueing > 0 then
            recenter_strength = recenter_strength * (preset.path_recentering_collision_scale or 0.4)
        end

        local correction = (0.6 - alignment) * recenter_strength
        raw_x = raw_x + dir_x * correction
        raw_y = raw_y + dir_y * correction

        local len2 = raw_x*raw_x + raw_y*raw_y
        if len2 > 0 then
            local inv2 = 1 / math.sqrt(len2)
            raw_x = raw_x * inv2
            raw_y = raw_y * inv2
        end
    end

    -- direction smoothing
    local ds = preset.dir_smoothing

    local sdx = self_player._smooth_dir_x or raw_x
    local sdy = self_player._smooth_dir_y or raw_y

    sdx = sdx + (raw_x - sdx) * ds
    sdy = sdy + (raw_y - sdy) * ds

    local slen = sdx*sdx + sdy*sdy
    if slen > 0 then
        local invs = 1 / math.sqrt(slen)
        sdx = sdx * invs
        sdy = sdy * invs
    end

    -- speed smoothing
    local target_speed = speed * slow_factor
    local ss = preset.speed_smoothing

    local smooth_speed = self_player._smooth_speed or target_speed
    smooth_speed = smooth_speed + (target_speed - smooth_speed) * ss

    -- store debug + predictive memory
    self_player._debug_avoid_x = avoid_x
    self_player._debug_avoid_y = avoid_y
    self_player._debug_final_x = sdx
    self_player._debug_final_y = sdy

    self_player._smooth_dir_x = sdx
    self_player._smooth_dir_y = sdy
    self_player._smooth_speed = smooth_speed

    self_player._last_dir_x = sdx
    self_player._last_dir_y = sdy
    self_player._last_speed = smooth_speed

    return sdx, sdy, smooth_speed
end

-- Export
return {
    compute_collision_avoidance = compute_collision_avoidance,
}