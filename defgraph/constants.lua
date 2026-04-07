-- defgraph/constants.lua
-- Shared constants and helpers for the DefGraph module

local constants = {}

-- Shared helpers
function constants.default(value, fallback)
    if value == nil then return fallback end
    return value
end

function constants.distance(source, destination)
    local dx = source.x - destination.x
    local dy = source.y - destination.y
    return math.sqrt(dx * dx + dy * dy)
end

constants.NODETYPE = {
    SINGLE       = hash("defgraph_nodetype_single"),
    DEADEND      = hash("defgraph_nodetype_deadend"),
    INTERSECTION = hash("defgraph_nodetype_intersection")
}

constants.ROUTETYPE = {
    ONETIME = hash("defgraph_routetype_onetime"),
    SHUFFLE = hash("defgraph_routetype_shuffle"),
    CYCLE   = hash("defgraph_routetype_cycle"),
    PATROL  = hash("defgraph_routetype_patrol")
}

constants.CollisionBehavior = {
    Cautious  = hash("defgraph_collision_behavior_cautious"),
    Balanced  = hash("defgraph_collision_behavior_balanced"),
    Reactive  = hash("defgraph_collision_behavior_reactive")
}

constants.COLLISION_BEHAVIOR_PRESETS = {
    [constants.CollisionBehavior.Cautious] = {
        lookahead_min           = 0.38,
        lookahead_max           = 0.78,
        lookahead_speed_factor  = 0.032,
        predictive_scale        = 0.53,
        reactive_scale          = 0.30,
        predictive_slow         = 0.94,
        reactive_slow           = 0.84,
        queue_spacing_factor    = 1.85,
        queue_slow              = 0.96,
        path_recentering        = 0.62,
        path_recentering_collision_scale = 0.35,
        dir_smoothing           = 0.30,
        speed_smoothing         = 0.24,
        density_radius_factor   = 2.9,
        density_slow_factor     = 0.48,
    },

    [constants.CollisionBehavior.Balanced] = {
        lookahead_min           = 0.28,
        lookahead_max           = 0.65,
        lookahead_speed_factor  = 0.022,
        predictive_scale        = 0.48,
        reactive_scale          = 0.38,
        predictive_slow         = 0.88,
        reactive_slow           = 0.78,
        queue_spacing_factor    = 1.65,
        queue_slow              = 0.92,
        path_recentering        = 0.28,
        path_recentering_collision_scale = 0.35,
        dir_smoothing           = 0.35,
        speed_smoothing         = 0.28,
        density_radius_factor   = 2.8,
        density_slow_factor     = 0.45,
    },

    [constants.CollisionBehavior.Reactive] = {
        lookahead_min           = 0.18,
        lookahead_max           = 0.48,
        lookahead_speed_factor  = 0.013,
        predictive_scale        = 0.38,
        reactive_scale          = 0.42,
        predictive_slow         = 0.82,
        reactive_slow           = 0.72,
        queue_spacing_factor    = 1.25,
        queue_slow              = 0.87,
        path_recentering        = 0.22,
        path_recentering_collision_scale = 0.28,
        dir_smoothing           = 0.28,
        speed_smoothing         = 0.22,
        density_radius_factor   = 2.3,
        density_slow_factor     = 0.18,
    },
}

-- Default values taken from Balanced preset (used for CustomBehavior fallback)
local BALANCED_DEFAULTS = constants.COLLISION_BEHAVIOR_PRESETS[constants.CollisionBehavior.Balanced]

-- Enhanced helper: supports presets (hashes) OR custom tables with validation + defaults
function constants.get_collision_preset(behavior)
    if type(behavior) == "table" then
        -- Custom behavior table → apply validation + fill missing values with Balanced defaults
        local preset = {}

        preset.lookahead_min                    = behavior.lookahead_min or BALANCED_DEFAULTS.lookahead_min
        preset.lookahead_max                    = behavior.lookahead_max or BALANCED_DEFAULTS.lookahead_max
        preset.lookahead_speed_factor           = behavior.lookahead_speed_factor or BALANCED_DEFAULTS.lookahead_speed_factor
        preset.predictive_scale                 = behavior.predictive_scale or BALANCED_DEFAULTS.predictive_scale
        preset.reactive_scale                   = behavior.reactive_scale or BALANCED_DEFAULTS.reactive_scale
        preset.predictive_slow                  = behavior.predictive_slow or BALANCED_DEFAULTS.predictive_slow
        preset.reactive_slow                    = behavior.reactive_slow or BALANCED_DEFAULTS.reactive_slow
        preset.queue_spacing_factor             = behavior.queue_spacing_factor or BALANCED_DEFAULTS.queue_spacing_factor
        preset.queue_slow                       = behavior.queue_slow or BALANCED_DEFAULTS.queue_slow
        preset.path_recentering                 = behavior.path_recentering or BALANCED_DEFAULTS.path_recentering
        preset.path_recentering_collision_scale = behavior.path_recentering_collision_scale or BALANCED_DEFAULTS.path_recentering_collision_scale
        preset.dir_smoothing                    = behavior.dir_smoothing or BALANCED_DEFAULTS.dir_smoothing
        preset.speed_smoothing                  = behavior.speed_smoothing or BALANCED_DEFAULTS.speed_smoothing
        preset.density_radius_factor            = behavior.density_radius_factor or BALANCED_DEFAULTS.density_radius_factor
        preset.density_slow_factor              = behavior.density_slow_factor or BALANCED_DEFAULTS.density_slow_factor

        -- Basic validation for custom table
        assert(type(preset.lookahead_min) == "number" and preset.lookahead_min > 0,
            "Custom collision_behavior: lookahead_min must be a positive number")
        assert(type(preset.lookahead_max) == "number" and preset.lookahead_max >= preset.lookahead_min,
            "Custom collision_behavior: lookahead_max must be >= lookahead_min")
        assert(type(preset.lookahead_speed_factor) == "number",
            "Custom collision_behavior: lookahead_speed_factor must be a number")

        return preset
    end

    -- Built-in preset
    local preset = constants.COLLISION_BEHAVIOR_PRESETS[behavior]
    assert(preset ~= nil, "Invalid collision_behavior: unknown preset (must be one of constants.CollisionBehavior.* or a custom table)")
    return preset
end

return constants