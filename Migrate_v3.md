# Changelog and migration guild from version 2 to 3  

* Added separate examples for static and dynamic map nodes.  
* Added `map_update_node_position` function to update node positions. now entire map can move dynamically.  
* `move_initialize` function gets `initial_face_vector` as an vector3 to calculate game object face direction based on this value.
* `move_player` function no longer need `threshold` as argument.  
* `move_initialize` function now gets `threshold` as an number and you do need to call `move_initialize` if you want to change it. This allows us to prevent situations that a game object always moves with a moving destination node without reaching it, forever.  
* Fixed bug that caused a game object to get stuck in an complex intersection.  
* Added `rotation` to move result table that returned from function `move_player` and you can set game object rotation to it.
* version 3 is tagged as `v3` in GitHub repository.  