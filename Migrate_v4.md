# Changelog and migration guild from version 3 to 4  

* Added ability to specify multiple destination node id as `destination_list` and type of route that the game object has to walk as `route_type` in `move_initialize` function.  
* Support 3 routing method when there is more than one destination: onetime, shuffle and cycle.  
* Added `destination_id` to move result table that returned from function `move_player` and you can get node id of current destination from it.  
* Fixed bug when game object failed to react when destination get inaccessible in middle of the way.  
* version 4 is tagged as `v4` in GitHub repository.  