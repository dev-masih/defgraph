# DefGraph v3  

<img src="example/banner.jpg" alt="routing gif" style="max-width:100%;" />

* <a href="https://github.com/dev-masih/defgraph/blob/master/Migrate_v3.md">**Changelog and migration guild from version 2 to 3**</a>  
* <a href="https://github.com/dev-masih/defgraph/blob/master/Migrate_v2.md">**Changelog and migration guild from version 1 to 2**</a>  

This module contains functions to create a world map as a shape of a graph and the ability to manipulate it at any time, easily see debug drawing of this graph and move go's inside of this graph with utilizing auto pathfinder.  

You can define a graph with several nodes and routes between them and the extension takes care of finding and moving your go inside this graph with just one call inside player update function.  
the gif bellow shows you this exactly when the destination for all red circles is node number 6.  

<img src="example/routing.gif" alt="routing gif" style="max-width:100%;" />

As you can see staying on the routes is the number one rule for red circles and they are going to the destination with minimum distance. all you have seen in this gif except for red circles, drawn by defGraph module and all of them are customizable.  
defGraph is adaptable to map change so even if you add or remove routes in the middle of the game extension tries to find the better road for you.  

<img src="example/dynamic-routing.gif" alt="routing gif" style="max-width:100%;" />

This is a community project you are welcome to contribute to it, sending PR, suggest a feature or report a bug.  

## Installation  
You can use DefGraph in your project by adding this project as a [Defold library dependency](http://www.defold.com/manuals/libraries/). Open your game.project file and in the dependencies field under project add:  

	https://github.com/dev-masih/defgraph/archive/master.zip
  
Once added, you must require the main Lua module via  

```
local defgraph = require("defgraph.defgraph")
```
Then you can use the DefGraph functions using this module.  

## Functions  
These are the list of available functions to use, for better understanding of how this module works, please take a look at project example.  

---  
### map_set_properties([settings_go_threshold], [settings_path_curve_tightness], [settings_path_curve_roundness], [settings_path_curve_max_distance_from_corner], [settings_allow_enter_on_route])  
Set the main path and move calculation properties, nil inputs will fall back to module default values. These values will overwrite default module values.  
#### **arguments:**  
* `optional number` settings_go_threshold `[default = 1]`  
* `optional number` settings_path_curve_tightness `[default = 4]`  
* `optional number` settings_path_curve_roundness `[default = 3]`  
* `optional number` settings_path_curve_max_distance_from_corner `[default = 10]`  
* `optional boolean` settings_allow_enter_on_route `[default = true]`  
---
### map_add_node(position)  
Adding a node at the given position (position.z will get ignored).  
#### **arguments:**  
* `vector3` position  
#### **return:**  
* `number` Newly added node id  
---  
### map_add_route(source_id, destination_id)  
Adding a two-way route between two nodes.  
#### **arguments:**  
* `number` source_id  
* `number` destination_id  
---  
### map_remove_route(source_id, destination_id)  
Removing an existing route between two nodes.  
#### **arguments:**  
* `number` source_id  
* `number` destination_id  
---  
### map_update_node_position(node_id, position)  
Update an existing node position.  
#### **arguments:**  
* `number` node_id  
* `vector3` position  
---  
### move_initialize(source_position, destination_id, initial_face_vector, settings_go_threshold, settings_path_curve_tightness, settings_path_curve_roundness, settings_path_curve_max_distance_from_corner, settings_allow_enter_on_route)  
Initialize moves from a source position to destination node inside the created map and using given threshold and initial face vector as game object initial face direction and path calculate settings, the optional value will fall back to module default values.    
#### **arguments:**  
* `vector3` source_position  
* `number` destination_id
* `optional vecotr3` initial_face_vector
* `optional number` settings_go_threshold
* `optional number` settings_path_curve_tightness
* `optional number` settings_path_curve_roundness
* `optional number` settings_path_curve_max_distance_from_corner
* `optional boolean` settings_allow_enter_on_route  
#### **return:**  
* `table` special movement data  
> **Note:** The returned special table consists of combined data to use later in `move_player` and `debug_draw_player_move` functions. If at any time you decided to change the destination of game object you have to call this function and overwrite old movement data with returned one.  
---  
### move_player(current_position, speed, move_data)  
Calculate movements from current position of the game object inside the created map considering given speed, using last calculated movement data.  
#### **arguments:**  
* `vector3` current_position
* `number` speed
* `table` move_data  
#### **return:**  
* `table` new movement data
* `table` move result
  * `position`: `vector3` next position of game object
  * `rotation`: `quat` next rotation of game object
  * `is_reached`: `boolean` is game object reached the destination  
> **Note:** The returned new movement data should overwrite old movement data. normally this function is placed inside go update function and you can set go position to `position` and rotation to `rotation` that is inside move result table. also, you should multiply `dt` with speed yourself before passing it to function.  
---  
### debug_set_properties(node_color, route_color, draw_scale)  
set debug drawing properties  
#### **arguments:**  
* `optional vector4` node_color `[vector4(1, 0, 1, 1)]`
* `optional vector4` route_color `[vector4(0, 1, 0, 1)]`
* `optional number` draw_scale `[5]`  
---  
### debug_draw_map_nodes(is_show_ids)  
Debug draw all map nodes and choose to show node ids or not.  
#### **arguments:**  
* `optional boolean` is_show_ids `[false]`   
---  
### debug_draw_map_routes()  
Debug draw all map routes.  

---  
### debug_draw_player_move(movement_data, color, is_show_intersection)
Debug draw player specific path with given color.  
#### **arguments:**  
* `table` movement_data
* `vector4` color
* `optional boolean` is_show_intersection `[false]` 
---  