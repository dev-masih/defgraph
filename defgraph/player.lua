-- defgraph/player.lua
-- Clean version with safe debug for projection + vector3

local constants = require("defgraph.constants")
local collision = require("defgraph.collision")
local config    = require("defgraph.config")
local debug     = require("defgraph.debug")

local Player = {}
Player.__index = Player

local function player_update(self_player, speed, compute_collision_list)
    compute_collision_list = compute_collision_list or false

    local map = self_player.map
    assert(map, "Player has no map assigned")

    local path       = self_player.path
    local path_index = self_player.path_index or 1
    local dest_index = self_player.destination_index or 1

    print(string.format("DEBUG: [%s] pos=(%.1f, %.1f) | path=%d/%d | dest_idx=%d | targets=%s", 
          self_player.key or "?", 
          self_player.current_position.x or 0, 
          self_player.current_position.y or 0,
          path_index, #path or 0, dest_index, 
          self_player.targets and "yes" or "NIL"))

    -- Path invalidation
    if path_index > 1 then
        local ids = self_player.path_node_ids
        if ids and #ids > 0 then
            if map:compute_path_version(ids) ~= self_player.path_version then
                print("DEBUG: Path invalidated - recalculating")
                self_player = map:move_internal_initialize(self_player.current_position, self_player)
                path = self_player.path
                path_index = self_player.path_index or 1
            end
        end
    end

    if not path or #path == 0 then
        print("DEBUG: No path")
        local rotation = nil
        if self_player.initial_angle then
            local cf = self_player.current_face_vector
            rotation = vmath.quat_rotation_z(math.atan2(cf.y, cf.x) - self_player.initial_angle)
        end
        return {
            position = vmath.vector3(self_player.current_position.x, self_player.current_position.y, 0),
            rotation = rotation,
            reached = false,
            finished = true,
            collided = {},
        }
    end

    -- Rotation smoothing
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

    -- Collision avoidance
    local function compute_collision_avoidance(dir_x, dir_y, speed)
        return collision.compute_collision_avoidance(map, self_player, dir_x, dir_y, speed)
    end

    -- Collision list
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
        if cfg.collision_groups then
            for _, group in ipairs(cfg.collision_groups) do
                local cached = map_state.collision_candidate_cache[group]
                if cached then
                    for j = 1, #cached do
                        count = count + 1
                        candidates[count] = cached[j]
                    end
                end
            end
        else
            for _, p in pairs(map_state.players) do
                count = count + 1
                candidates[count] = p
            end
        end

        for i = 1, count do
            local other = candidates[i]
            if other ~= self_player then
                local dx = px - other.current_position.x
                local dy = py - other.current_position.y
                if dx*dx + dy*dy <= radius_sq then
                    table.insert(collided, {id = other.id, key = other.key, groups = other:get_groups() or {}})
                end
            end
        end
    end

    ----------------------------------------------------------------------
    -- Movement Loop
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

            dir_x, dir_y, speed = compute_collision_avoidance(dir_x, dir_y, speed)

            if self_player.initial_angle then
                rotation = apply_rotation_smoothing(dir_x, dir_y)
            end

            self_player.current_position.x = self_player.current_position.x + dir_x * speed
            self_player.current_position.y = self_player.current_position.y + dir_y * speed

            return {
                position = vmath.vector3(self_player.current_position.x, self_player.current_position.y, 0),
                rotation = rotation,
                reached = false,
                finished = false,
                collided = collided,
            }
        end

        i = i + 1
    end

    -- All path points passed
    self_player.path_index = last_index + 1

    local current_target = self_player.targets and self_player.targets[dest_index] or nil
    local is_reached = false

    if current_target then
        if type(current_target) == "userdata" then
            local dx = self_player.current_position.x - current_target.x
            local dy = self_player.current_position.y - current_target.y
            is_reached = (dx*dx + dy*dy <= threshold_sq)
            print(string.format("DEBUG: Checking VECTOR3 | dist=%.2f | reached=%s", math.sqrt(dx*dx + dy*dy), tostring(is_reached)))
        else
            local state = map:get_map_state()
            local dest_pos = state.map_node_list[current_target].position
            local dx = self_player.current_position.x - dest_pos.x
            local dy = self_player.current_position.y - dest_pos.y
            is_reached = (dx*dx + dy*dy <= threshold_sq)
            print("DEBUG: Checking NODE", current_target, "dist=", math.sqrt(dx*dx + dy*dy))
        end
    else
        print("DEBUG: WARNING: No current_target! targets=", self_player.targets and "exists" or "nil")
    end

    if self_player.initial_angle then
        local cf = self_player.current_face_vector
        rotation = apply_rotation_smoothing(cf.x, cf.y)
    end

    if is_reached then
        print("DEBUG: *** REAL DESTINATION REACHED ***")
        -- Add your route logic here (ONETIME, CYCLE, etc.)
        local count = #self_player.destination_list
        local rt = self_player.route_type
        local should_continue = true
        local is_finished = false

        if count == 1 then
            should_continue = false
            is_finished = true
        else
            if rt == constants.ROUTETYPE.ONETIME then
                if self_player.destination_index < count then
                    self_player.destination_index = self_player.destination_index + 1
                else
                    should_continue = false
                    is_finished = true
                end
            elseif rt == constants.ROUTETYPE.CYCLE then
                self_player.destination_index = (self_player.destination_index % count) + 1
            end
        end

        if should_continue then
            self_player = map:move_internal_initialize(self_player.current_position, self_player)
        end

        return {
            position = vmath.vector3(self_player.current_position.x, self_player.current_position.y, 0),
            rotation = rotation,
            reached = true,
            finished = is_finished,
            collided = collided,
        }
    end

    print("DEBUG: Not at final destination yet")
    return {
        position = vmath.vector3(self_player.current_position.x, self_player.current_position.y, 0),
        rotation = rotation,
        reached = false,
        finished = false,
        collided = collided,
    }
end

function Player:update(speed, compute_collision_list)
    return player_update(self, speed, compute_collision_list)
end

function Player:update_destinations(destination_list, route_type)
    assert(destination_list, "Player:update_destinations: destination_list is required")
    route_type = constants.default(route_type, self.route_type or constants.ROUTETYPE.ONETIME)

    local normalized, targets = self.map:normalize_destination_list(destination_list)

    self.destination_list = normalized
    self.targets = targets

    local count = #self.destination_list
    self.destination_index = 1
    self.patrol_direction = 1

    if route_type == constants.ROUTETYPE.SHUFFLE and count > 1 then
        self.destination_index = math.random(count)
    end

    self.route_type = route_type

    print("DEBUG: update_destinations called with", #destination_list, "items. targets count =", #targets or 0)
    self = self.map:move_internal_initialize(self.current_position, self)
end


function Player:update_config(new_config)
    assert(new_config, "Player:update_config: new_config is required")

    if type(new_config) ~= "table" or getmetatable(new_config) ~= config.PlayerConfig then
        new_config = config.PlayerConfig.new(new_config)
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
    debug.debug_draw_player(self.map, self, color or vmath.vector4(1,1,0,1),
                            show_projection or false,
                            show_directions or false,
                            show_snap_radius or false,
                            show_collision or false)
end

return {
    Player = Player,
    player_update = player_update,
}