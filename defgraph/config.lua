-- defgraph/config.lua
-- PlayerConfig class

local function default(value, fallback)
    if value == nil then return fallback end
    return value
end

local PlayerConfig = {}
PlayerConfig.__index = PlayerConfig

local PLAYER_DEFAULTS = {
    gameobject_threshold = 2,
    allow_enter_on_route = true,

    path_curve_tightness = 4,
    path_curve_roundness = 3,
    path_curve_max_distance_from_corner = 10,

    collision_enabled = false,
    collision_radius  = 6,
    collision_groups  = nil,
    collision_behavior = nil,
}

function PlayerConfig.new(options)
    options = options or {}

    local self = {
        gameobject_threshold = default(options.gameobject_threshold, PLAYER_DEFAULTS.gameobject_threshold),
        allow_enter_on_route = default(options.allow_enter_on_route, PLAYER_DEFAULTS.allow_enter_on_route),
        path_curve_tightness = default(options.path_curve_tightness, PLAYER_DEFAULTS.path_curve_tightness),
        path_curve_roundness = default(options.path_curve_roundness, PLAYER_DEFAULTS.path_curve_roundness),
        path_curve_max_distance_from_corner = default(options.path_curve_max_distance_from_corner, PLAYER_DEFAULTS.path_curve_max_distance_from_corner),
        collision_enabled = default(options.collision_enabled, PLAYER_DEFAULTS.collision_enabled),
        collision_radius  = default(options.collision_radius, PLAYER_DEFAULTS.collision_radius),
        collision_groups  = default(options.collision_groups, PLAYER_DEFAULTS.collision_groups),
        collision_behavior = default(options.collision_behavior, nil),
    }

    return setmetatable(self, PlayerConfig)
end

function PlayerConfig:validate()
    -- Numeric validations
    assert(type(self.gameobject_threshold) == "number",
        "PlayerConfig: gameobject_threshold must be a number")

    assert(type(self.path_curve_tightness) == "number",
        "PlayerConfig: path_curve_tightness must be a number")

    assert(type(self.path_curve_roundness) == "number",
        "PlayerConfig: path_curve_roundness must be a number")

    assert(self.path_curve_roundness >= 0 and self.path_curve_roundness <= 12,
        "PlayerConfig: path_curve_roundness must be between 0 and 12")

    assert(type(self.path_curve_max_distance_from_corner) == "number",
        "PlayerConfig: path_curve_max_distance_from_corner must be a number")

    -- Boolean validations
    assert(type(self.allow_enter_on_route) == "boolean",
        "PlayerConfig: allow_enter_on_route must be a boolean")

    assert(type(self.collision_enabled) == "boolean",
        "PlayerConfig: collision_enabled must be a boolean")

    -- Collision radius
    assert(type(self.collision_radius) == "number",
        "PlayerConfig: collision_radius must be a number")

    -- Collision groups
    assert(self.collision_groups == nil or type(self.collision_groups) == "table",
        "PlayerConfig: collision_groups must be nil or a list of strings")

    if self.collision_groups ~= nil then
        for i, group in ipairs(self.collision_groups) do
            assert(type(group) == "string",
                "PlayerConfig: collision_groups must contain strings")
        end
    end

    -- Collision behavior
    assert(self.collision_behavior ~= nil,
        "PlayerConfig: collision_behavior is required")

    -- Range checks
    assert(self.gameobject_threshold >= 0,
        "PlayerConfig: gameobject_threshold must be >= 0")

    assert(self.path_curve_tightness >= 0,
        "PlayerConfig: path_curve_tightness must be >= 0")

    assert(self.path_curve_roundness >= 0,
        "PlayerConfig: path_curve_roundness must be >= 0")

    assert(self.path_curve_max_distance_from_corner >= 0,
        "PlayerConfig: path_curve_max_distance_from_corner must be >= 0")

    assert(self.collision_radius >= 0,
        "PlayerConfig: collision_radius must be >= 0")

    return true
end

return { PlayerConfig = PlayerConfig }