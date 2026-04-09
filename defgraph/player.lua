-- defgraph/player.lua
-- Player logic with clean multiple event listeners and new collision matrix support

local constants = require("defgraph.constants")
local collision = require("defgraph.collision")
local config    = require("defgraph.config")
local debug     = require("defgraph.debug")

local Player = {}
Player.__index = Player

-- ==================== Event Listener System ====================

function Player:add_listener(event_name, callback)
    assert(event_name == "reached" or event_name == "finished",
           "add_listener: event_name must be 'reached' or 'finished'")
    assert(type(callback) == "function", "add_listener: callback must be a function")

    self._listeners = self._listeners or {}
    self._listeners[event_name] = self._listeners[event_name] or {}

    -- Prevent duplicate listeners
    for _, cb in ipairs(self._listeners[event_name]) do
        if cb == callback then
            return false
        end
    end

    table.insert(self._listeners[event_name], callback)
    return true
end

function Player:remove_listener(event_name, callback)
    if not self._listeners or not self._listeners[event_name] then 
        return false 
    end

    local list = self._listeners[event_name]
    for i = #list, 1, -1 do
        if list[i] == callback then
            table.remove(list, i)
            return true
        end
    end
    return false
end

function Player:clear_listeners(event_name)
    if self._listeners then
        if event_name then
            self._listeners[event_name] = nil
        else
            self._listeners = nil
        end
    end
end

-- Internal safe trigger
local function trigger_listeners(self_player, event_name, event_data)
    if not self_player._listeners or not self_player._listeners[event_name] then
        return
    end

    local listeners = self_player._listeners[event_name]
    for i = 1, #listeners do
        local success, err = pcall(listeners[i], self_player, event_data)
        if not success then
            print("Warning: Error in '" .. event_name .. "' listener: " .. tostring(err))
        end
    end
end

-- ==================== Core Update Function ====================

local function player_update(self_player, speed, compute_collision_list)
    compute_collision_list = compute_collision_list or false

    local map = self_player.map
    assert(map, "Player has no map assigned")

    -- Ensure valid destination_index
    if not self_player.destination_index or self_player.destination_index < 1 then
        self_player.destination_index = 1
    end

    local path       = self_player.path
    local path_index = self_player.path_index or 1

    -- If player has already finished, stay in finished state
    if self_player._finished then
        local rotation = nil
        if self_player.initial_angle then
            local cf = self_player.current_face_vector
            rotation = vmath.quat_rotation_z(math.atan2(cf.y, cf.x) - self_player.initial_angle)
        end

        return {
            position                   = vmath.vector3(self_player.current_position.x, self_player.current_position.y, 0),
            rotation                   = rotation,
            reached_destination_id     = nil,
            to_destination_id          = nil,
            reached_destination_vector = nil,
            to_destination_vector      = nil,
            reached                    = false,
            finished                   = true,
            collided                   = {},
        }
    end

    -- Path invalidation
    if path_index > 1 then
        local ids = self_player.path_node_ids
        if ids and #ids > 0 then
            if map:compute_path_version(ids) ~= self_player.path_version then
                self_player = map:move_internal_initialize(self_player.current_position, self_player)
                path = self_player.path
                path_index = self_player.path_index or 1
            end
        end
    end

    if not path or #path == 0 then
        self_player._finished = true
        local rotation = nil
        if self_player.initial_angle then
            local cf = self_player.current_face_vector
            rotation = vmath.quat_rotation_z(math.atan2(cf.y, cf.x) - self_player.initial_angle)
        end
        return {
            position                   = vmath.vector3(self_player.current_position.x, self_player.current_position.y, 0),
            rotation                   = rotation,
            reached_destination_id     = nil,
            to_destination_id          = nil,
            reached_destination_vector = nil,
            to_destination_vector      = nil,
            reached                    = false,
            finished                   = true,
            collided                   = {},
        }
    end

    -- Rotation smoothing helper
    local rotation = nil
    local function apply_rotation_smoothing(dir_x, dir_y)
        if not self_player.initial_angle then return nil end
        local cf = self_player.current_face_vector
        local rx = cf.x + (dir_x - cf.x) * (0.2 * speed)
        local ry = cf.y + (dir_y - cf.y) * (0.2 * speed)
        local angle = math.atan2(ry, rx)
        local prev = self_player._prev_angle or angle
        local diff = angle - prev
        if diff > 3.14159 then diff = diff - 6.28318 end
        if diff < -3.14159 then diff = diff + 6.28318 end
        angle = prev + diff * 0.25
        self_player._prev_angle = angle
        self_player.current_face_vector.x = rx
        self_player.current_face_vector.y = ry
        return vmath.quat_rotation_z(angle - self_player.initial_angle)
    end

    -- Collision list collection (NEW: uses collision matrix)
    local collided = {}
    if compute_collision_list and self_player.config.collision_enabled then
        local cfg = self_player.config
        local radius_sq = cfg.collision_radius * cfg.collision_radius
        local px, py = self_player.current_position.x, self_player.current_position.y

        local candidates = self_player._scratch_candidates or {}
        self_player._scratch_candidates = candidates
        local count = 0
        for i = 1, #candidates do candidates[i] = nil end

        local map_state = map:get_map_state()
        local matrix = map_state.collision_matrix

        -- Build candidates using collision matrix
        for _, other in pairs(map_state.players) do
            if other ~= self_player and other.config.collision_enabled then
                local should_collide = false

                -- Only players with groups can collide
                if self_player.groups and other.groups and
                   next(self_player.groups) ~= nil and next(other.groups) ~= nil then
                    
                    for g1 in pairs(self_player.groups) do
                        for g2 in pairs(other.groups) do
                            if matrix[g1] and matrix[g1][g2] then
                                should_collide = true
                                break
                            end
                        end
                        if should_collide then break end
                    end
                end

                if should_collide then
                    count = count + 1
                    candidates[count] = other
                end
            end
        end

        -- Check actual overlap for collided list
        for i = 1, count do
            local other = candidates[i]
            local dx = px - other.current_position.x
            local dy = py - other.current_position.y
            if dx*dx + dy*dy <= radius_sq then
                table.insert(collided, {
                    id = other.id,
                    key = other.key,
                    groups = other:get_groups() or {}
                })
            end
        end
    end

    ----------------------------------------------------------------------
    -- Movement loop
    ----------------------------------------------------------------------
    local threshold_sq = (self_player.config.gameobject_threshold + 1) ^ 2
    local last_index = #path
    local i = path_index

    while i <= last_index do
        local target = path[i]
        local vx = target.x - self_player.current_position.x
        local vy = target.y - self_player.current_position.y
        local dist_sq = vx*vx + vy*vy

        if dist_sq > threshold_sq then
            self_player.path_index = i

            local inv_len = 1 / math.sqrt(dist_sq)
            local dir_x = vx * inv_len
            local dir_y = vy * inv_len

            dir_x, dir_y, speed = collision.compute_collision_avoidance(map, self_player, dir_x, dir_y, speed)

            if self_player.initial_angle then
                rotation = apply_rotation_smoothing(dir_x, dir_y)
            end

            self_player.current_position.x = self_player.current_position.x + dir_x * speed
            self_player.current_position.y = self_player.current_position.y + dir_y * speed

            local next_target = self_player.targets and self_player.targets[self_player.destination_index] or nil

            return {
                position                   = vmath.vector3(self_player.current_position.x, self_player.current_position.y, 0),
                rotation                   = rotation,
                reached_destination_id     = nil,
                to_destination_id          = type(next_target) == "number" and next_target or nil,
                reached_destination_vector = nil,
                to_destination_vector      = type(next_target) == "userdata" and next_target or nil,
                reached                    = false,
                finished                   = false,
                collided                   = collided,
            }
        end

        i = i + 1
    end

    -- ============================================================
    -- Reached current destination
    -- ============================================================
    self_player.path_index = last_index + 1

    local current_target = self_player.targets and self_player.targets[self_player.destination_index] or nil
    local is_reached = false

    if current_target then
        if type(current_target) == "userdata" then
            local dx = self_player.current_position.x - current_target.x
            local dy = self_player.current_position.y - current_target.y
            is_reached = (dx*dx + dy*dy <= threshold_sq)
        else
            local state = map:get_map_state()
            local dest_pos = state.map_node_list[current_target].position
            local dx = self_player.current_position.x - dest_pos.x
            local dy = self_player.current_position.y - dest_pos.y
            is_reached = (dx*dx + dy*dy <= threshold_sq)
        end
    end

    if self_player.initial_angle then
        local cf = self_player.current_face_vector
        rotation = apply_rotation_smoothing(cf.x, cf.y)
    end

    if is_reached then
        local old_index = self_player.destination_index
        local reached_target = self_player.targets and self_player.targets[old_index] or nil

        -- Prepare event data
        local event_data = {
            player                     = self_player,
            reached_destination_id     = type(reached_target) == "number" and reached_target or nil,
            reached_destination_vector = type(reached_target) == "userdata" and reached_target or nil,
            destination_index          = old_index,
            total_destinations         = #self_player.targets or 0,
            route_type                 = self_player.route_type,
        }

        -- Trigger reached event
        trigger_listeners(self_player, "reached", event_data)

        -- Route progression logic
        local count = #self_player.targets or 0
        local is_finished = false
        local should_continue = true

        local rt = self_player.route_type

        if rt == constants.ROUTETYPE.ONETIME then
            if old_index >= count then
                is_finished = true
                should_continue = false
                self_player._finished = true
            else
                self_player.destination_index = old_index + 1
            end

        elseif rt == constants.ROUTETYPE.CYCLE then
            self_player.destination_index = (old_index % count) + 1

        elseif rt == constants.ROUTETYPE.SHUFFLE then
            local t = self_player.targets
            for i = #t, 2, -1 do
                local j = math.random(i)
                t[i], t[j] = t[j], t[i]
            end
            self_player.destination_index = 1

        elseif rt == constants.ROUTETYPE.PATROL then
            if old_index >= count then
                self_player.patrol_direction = -1
                self_player.destination_index = count - 1
            elseif old_index <= 1 then
                self_player.patrol_direction = 1
                self_player.destination_index = 2
            else
                self_player.destination_index = old_index + self_player.patrol_direction
            end
        end

        if should_continue then
            local updated_data = map:move_internal_initialize(self_player.current_position, self_player)
            for k, v in pairs(updated_data) do
                self_player[k] = v
            end
            if updated_data.destination_index then
                self_player.destination_index = updated_data.destination_index
            end
        end

        -- Trigger finished event only once
        if is_finished then
            trigger_listeners(self_player, "finished", event_data)
        end

        local next_target = self_player.targets and self_player.targets[self_player.destination_index] or nil

        return {
            position                   = vmath.vector3(self_player.current_position.x, self_player.current_position.y, 0),
            rotation                   = rotation,
            reached_destination_id     = type(reached_target) == "number" and reached_target or nil,
            to_destination_id          = type(next_target) == "number" and next_target or nil,
            reached_destination_vector = type(reached_target) == "userdata" and reached_target or nil,
            to_destination_vector      = type(next_target) == "userdata" and next_target or nil,
            reached                    = true,
            finished                   = is_finished,
            collided                   = collided,
        }
    end

    -- Still moving toward current destination
    local next_target = self_player.targets and self_player.targets[self_player.destination_index] or nil

    return {
        position                   = vmath.vector3(self_player.current_position.x, self_player.current_position.y, 0),
        rotation                   = rotation,
        reached_destination_id     = nil,
        to_destination_id          = type(next_target) == "number" and next_target or nil,
        reached_destination_vector = nil,
        to_destination_vector      = type(next_target) == "userdata" and next_target or nil,
        reached                    = false,
        finished                   = false,
        collided                   = collided,
    }
end

function Player:update(speed, compute_collision_list)
    return player_update(self, speed, compute_collision_list)
end

-- ==================== Other Player Methods ====================

function Player:update_destinations(destination_list, route_type)
    assert(destination_list, "Player:update_destinations: destination_list is required")
    assert(type(destination_list) == "table", "destination_list must be a table")

    route_type = constants.default(route_type, self.route_type or constants.ROUTETYPE.ONETIME)

    local normalized, targets = self.map:normalize_destination_list(destination_list)

    self.destination_list = normalized
    self.targets          = targets

    local count = #normalized
    self.destination_index = 1
    self.patrol_direction  = 1

    if route_type == constants.ROUTETYPE.SHUFFLE and count > 1 then
        self.destination_index = math.random(count)
    end

    self.route_type = route_type

    -- Rebuild path
    self = self.map:move_internal_initialize(self.current_position, self)
end

function Player:update_config(new_config)
    assert(new_config, "Player:update_config: new_config is required")

    if type(new_config) ~= "table" or getmetatable(new_config) ~= config.PlayerConfig then
        new_config = config.PlayerConfig.new(new_config)
    end

    new_config:validate()
    self.config = new_config

    -- Clear collision-related caches
    self._scratch_candidates = nil
    self._smooth_dir_x = nil
    self._smooth_dir_y = nil
    self._smooth_speed = nil
    self._last_dir_x = nil
    self._last_dir_y = nil
    self._last_speed = nil

    if self.map then
        self.map:invalidate_collision_cache()
    end
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
    self._finished = nil
    self:clear_listeners()        -- Clean up listeners
end

-- ==================== Debug Methods ====================

function Player:debug_draw_player(color, show_projection, show_directions, show_snap_radius, show_collision)
    if not self.map then return end
    debug.debug_draw_player(self.map, self, color or vmath.vector4(1,1,0,1),
                            show_projection or false,
                            show_directions or false,
                            show_snap_radius or false,
                            show_collision or false)
end

-- Export
return {
    Player = Player,
    player_update = player_update,
}