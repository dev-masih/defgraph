-- defgraph/constants.lua

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

return constants