# Changelog and migration guild from version 2 to 3  

* Added ability for game objects to have curved corner paths.
* Added ability to track game object rotation as move result.
* Added only one ways routes, and added separate arguments `two_way_route_color` and `one_way_route_color` in `debug_draw_map_nodes` function.  
* Added separate examples for static and dynamic map nodes.  
* Added documentation for module settings.  
* Added `is_one_way` argument to `map_add_route` function, to able to add just one way route.  
* Added `is_remove_one_way` argument to `map_remove_route` function, to able to remove just one way route or both between two nodes.  
* Added `map_remove_node` function to remove a node and it's connected routes to it.  
* Added `map_update_node_position` function to update node positions. now entire map can move dynamically.  
* Added `map_set_properties` function to replace module default settings.  
* `move_initialize` function gets `initial_face_vector` as an vector3 to calculate game object face direction based on this value. setting this value to `nil` will disable rotation tracking system and `rotation` field in move result table will always be `nil`.  
* `move_player` function no longer need `threshold` as argument.  
* `move_initialize` function now gets `settings_go_threshold` as an number and you do need to call `move_initialize` if you want to change it. This allows us to prevent situations that a game object always moves with a moving destination node without reaching it, forever. setting this value to `nil` will fall back to module default value.  
* Adding `settings_path_curve_tightness`, `settings_path_curve_roundness`, `settings_path_curve_max_distance_from_corner` and `settings_allow_enter_on_route` to `move_initialize` arguments. you can overwrite these values for a single game object by them. setting these value to `nil` will fall back to module default value.  
* Added `rotation` to move result table that returned from function `move_player` and you can set game object rotation to it.  
* Fixed bug that caused a game object to get stuck in an complex intersection.  
* Added `is_show_intersection` argument to `debug_draw_player_move` function to allow debugger mark/not mark intersections of game object path.  
* version 3 is tagged as `v3` in GitHub repository.  