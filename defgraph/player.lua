-- defgraph/player.lua
-- Player class and main update logic

local constants_module = require("defgraph.constants")
local collision = require("defgraph.collision")
local config_module = require("defgraph.config")
local debug_module = require("defgraph.debug")

local Player = {}
Player.__index = Player

-- ==================== Player Update (Main Logic) ====================

function Player:update(speed)
    return self.map:player_update(self, speed)
end

local function player_update(map, self_player, speed)  -- Note: 'self' here is the Map
    assert(map, "Player has no map assigned")

    local path       = self_player.path
    local path_index = self_player.path_index

    ----------------------------------------------------------------------
    -- 1. Path invalidation
    ----------------------------------------------------------------------
    if path_index ~= 0 then
        local ids = self_player.path_node_ids
        if ids and #ids > 0 then
            if map:compute_path_version(ids) ~= self_player.path_version then
                self_player = map:move_internal_initialize(self_player.current_position, self_player)
                path = self_player.path
                path_index = self_player.path_index
            end
        end
    end

    ----------------------------------------------------------------------
    -- 2. Rotation smoothing helper
    ----------------------------------------------------------------------
    local rotation = nil
    local function apply_rotation_smoothing(dir_x, dir_y)
        if not self_player.initial_angle then return nil end

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

    ----------------------------------------------------------------------
    -- Helper to build return table
    ----------------------------------------------------------------------
    local function make_result(reached_this_frame, reached_id, is_finished)
        return {
            position               = vmath.vector3(self_player.current_position.x, self_player.current_position.y, 0),
            rotation               = rotation,
            reached_destination_id = reached_this_frame and reached_id or nil,
            to_destination_id      = self_player.destination_list[self_player.destination_index],
            reached                = reached_this_frame or false,
            finished               = is_finished or false,
        }
    end

    ----------------------------------------------------------------------
    -- 3. No path case
    ----------------------------------------------------------------------
    if path_index == 0 then
        if self_player.initial_angle then
            local cf = self_player.current_face_vector
            rotation = apply_rotation_smoothing(cf.x, cf.y)
        end

        local is_finished = #self_player.destination_list <= 1
        return make_result(false, nil, is_finished)
    end

    ----------------------------------------------------------------------
    -- 4. Collision avoidance
    ----------------------------------------------------------------------
    local function compute_collision_avoidance(dir_x, dir_y, speed)
        return collision.compute_collision_avoidance(map, self_player, dir_x, dir_y, speed)
    end

    ----------------------------------------------------------------------
    -- 5. Movement loop
    ----------------------------------------------------------------------
    local threshold = self_player.config.gameobject_threshold + 1
    local threshold_sq = threshold * threshold

    local last_index = #path
    local state = map:get_map_state()
    local map_node_list = state.map_node_list

    for i = path_index, last_index do
        local target = path[i]

        local vx = target.x - self_player.current_position.x
        local vy = target.y - self_player.current_position.y
        local dist_sq = vx*vx + vy*vy

        if dist_sq > threshold_sq then
            self_player.path_index = i

            local inv_len = 1 / math.sqrt(dist_sq)
            local dir_x = vx * inv_len
            local dir_y = vy * inv_len

            dir_x, dir_y, speed = compute_collision_avoidance(dir_x, dir_y, speed)

            if self_player.initial_angle then
                rotation = apply_rotation_smoothing(dir_x, dir_y)
            end

            local new_x = self_player.current_position.x + dir_x * speed
            local new_y = self_player.current_position.y + dir_y * speed

            self_player.current_position.x = new_x
            self_player.current_position.y = new_y

            return make_result(false, nil, false)
        end

        ------------------------------------------------------------------
        -- 6. Destination reached this frame
        ------------------------------------------------------------------
        if i == last_index then
            local dest_id  = self_player.destination_list[self_player.destination_index]
            local dest_pos = map_node_list[dest_id].position

            local dx = self_player.current_position.x - dest_pos.x
            local dy = self_player.current_position.y - dest_pos.y
            local is_reached = (dx*dx + dy*dy <= threshold_sq)

            if self_player.initial_angle then
                local cf = self_player.current_face_vector
                rotation = apply_rotation_smoothing(cf.x, cf.y)
            end

            if is_reached then
                local count = #self_player.destination_list
                local rt = self_player.route_type
                local should_continue = true
                local is_finished = false

                if count == 1 then
                    -- Single destination case: once reached, we are finished
                    should_continue = false
                    is_finished = true
                else
                    if rt == constants_module.ROUTETYPE.ONETIME then
                        if self_player.destination_index < count then
                            self_player.destination_index = self_player.destination_index + 1
                        else
                            should_continue = false
                            is_finished = true
                        end

                    elseif rt == constants_module.ROUTETYPE.SHUFFLE then
                        if count > 1 then
                            local new_id = self_player.destination_index
                            repeat
                                new_id = math.random(count)
                            until new_id ~= self_player.destination_index
                            self_player.destination_index = new_id
                        end

                    elseif rt == constants_module.ROUTETYPE.CYCLE then
                        self_player.destination_index = (self_player.destination_index % count) + 1

                    elseif rt == constants_module.ROUTETYPE.PATROL then
                        if count > 1 then
                            local dir = self_player.patrol_direction or 1
                            local next_index = self_player.destination_index + dir

                            if next_index > count then
                                self_player.patrol_direction = -1
                                next_index = count - 1
                            elseif next_index < 1 then
                                self_player.patrol_direction = 1
                                next_index = 2
                            end
                            self_player.destination_index = next_index
                        end
                    end
                end

                if should_continue then
                    self_player = map:move_internal_initialize(self_player.current_position, self_player)
                end

                return make_result(true, dest_id, is_finished)
            end

            -- Not exactly at destination yet
            return make_result(false, nil, false)
        end
    end

    -- Fallback
    return make_result(false, nil, false)
end

-- ==================== Player Helper Methods ====================

function Player:update_config(new_config)
    assert(new_config, "Player:update_config: new_config is required")

    if type(new_config) ~= "table" or getmetatable(new_config) ~= config_module.PlayerConfig then
        new_config = config_module.PlayerConfig.new(new_config)
    end

    new_config:validate()
    self.config = new_config

    -- Clear collision caches
    self._scratch_candidates = nil
    self._smooth_dir_x = nil
    self._smooth_dir_y = nil
    self._smooth_speed = nil
    self._last_dir_x = nil
    self._last_dir_y = nil
    self._last_speed = nil

    if self.map then
        if self.config.collision_groups then
            for _, group in ipairs(self.config.collision_groups) do
                self.map:invalidate_collision_cache(group)
            end
        else
            self.map:invalidate_collision_cache()
        end
    end
end

function Player:update_destinations(destination_list, route_type)
    assert(destination_list, "Player:update_destinations: destination_list is required")

    route_type = constants_module.default(route_type, self.route_type or constants_module.ROUTETYPE.ONETIME)

    self.destination_list = self.map:normalize_destination_list(destination_list)

    local count = #self.destination_list
    self.destination_index = 1
    self.patrol_direction = 1

    if route_type == constants_module.ROUTETYPE.SHUFFLE and count > 1 then
        self.destination_index = math.random(count)
    end

    self.route_type = route_type

    -- Force path recalculation
    self = self.map:move_internal_initialize(self.current_position, self)
end

function Player:update_face_vector(face_vector)
    if face_vector then
        self.current_face_vector = vmath.vector3(face_vector.x, face_vector.y, 0)
        self.initial_angle = math.atan2(face_vector.y, face_vector.x)
    else
        self.current_face_vector = nil
        self.initial_angle = nil
    end

    self._prev_angle = nil
end

function Player:teleport(position)
    assert(position and type(position) == "userdata",
           "Player:teleport: position must be a vmath.vector3")

    self.current_position = vmath.vector3(position.x, position.y, 0)

    -- Force path recalculation
    self = self.map:move_internal_initialize(self.current_position, self)
end

function Player:is_in_group(group)
    if not self.groups then return false end
    return self.groups[group] == true
end

function Player:get_groups()
    local list = {}
    if self.groups then
        for group in pairs(self.groups) do
            list[#list + 1] = group
        end
    end
    return list
end

function Player:add_to_group(group)
    assert(self.map, "Player has no map assigned")
    if self.groups and self.groups[group] then return false end

    self.map:add_player_to_group(self.key, group)
    return true
end

function Player:remove_from_group(group)
    assert(self.map, "Player has no map assigned")
    self.map:remove_player_from_group(self.key, group)
end

function Player:destroy()
    self.map = nil
    self.path = {}
    self.path_node_ids = {}
    self.current_face_vector = nil
    self._prev_angle = nil
    self.groups = nil
    self.patrol_direction = nil
    self.destination_list = nil
    self._scratch_candidates = nil
    self._scratch_ids        = nil
    self._scratch_nv         = nil
    self._scratch_rv         = nil
end

-- ==================== Debug Methods on Player ====================

function Player:debug_draw_player(color, show_projection, show_directions, show_snap_radius, show_collision)
    if not self.map then return end
    debug_module.debug_draw_player(self.map, self, color or vmath.vector4(1,1,0,1),
                                show_projection or false,
                                show_directions or false,
                                show_snap_radius or false,
                                show_collision or false)
end

-- ==================== Export ====================

return {
    Player = Player,
    player_update = player_update,
}