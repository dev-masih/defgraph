# Changelog and migration guild from version 1 to 2  

* Internal structure for storing routes changes to reduce process time in other functions for calculations and there are several improvements to local functions that calculate paths, now move_data table contains the path to the destination and not need to rethink every time to save processing power.  
* `move_initialize` function no longer need `threshold` as argument.  
* `move_player` function now gets `threshold` as an argument so you don't need to call `move_initialize` if you want to change it.  
* `move_player` function now returns two things, first is new movement data as a table that you should overwrite the old one and second is move result table with the structure like { `position`: next position of game object as vector3, `is_reached`: is game object reached the destination as boolean }  
* `debug_draw_player_move` function now draw game object route through the destination.  
  
<img src="https://raw.githubusercontent.com/dev-masih/my-media-bin/master/defgraph/debug_draw_player_move.png" alt="player move" style="max-width:100%;" />  

* version 2 is tagged as `v2` in GitHub repository.