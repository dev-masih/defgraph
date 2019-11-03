# DefGraph v4.1  

<img src="https://raw.githubusercontent.com/dev-masih/my-media-bin/master/defgraph/hero.jpg" alt="defgraph banner" style="max-width:100%;" />

* <a href="https://github.com/dev-masih/defgraph/blob/master/Migrate_v4.md">**Changelog and migration guild from version 3.1 to 4.x**</a>  
* <a href="https://github.com/dev-masih/defgraph/blob/master/Migrate_v3.md">**Changelog and migration guild from version 2 to 3.x**</a>  
* <a href="https://github.com/dev-masih/defgraph/blob/master/Migrate_v2.md">**Changelog and migration guild from version 1 to 2**</a>  

This module contains functions to create a world map as a shape of a graph and the ability to manipulate it at any time, easily see debug drawing of this graph and move the game objects inside of this graph with utilizing auto pathfinder with different patterns.  

You can define a graph with several nodes and routes between them and the extension takes care of finding and moving your game object inside this graph with just one call inside player update function.  
The gif below shows you this exactly when the destination for all red circles will be selected shuffled between node numbers 6, 18, 14, 2, 4 and 10.  

<img src="https://raw.githubusercontent.com/dev-masih/my-media-bin/master/defgraph/static_routing_v4.gif" alt="static routing gif version 4" style="max-width:100%;" />

As you can see staying on the routes is the number one rule for red circles and they are going to the destination with minimum distance. all you have seen in this gif except for red circles, drawn by defGraph module debug functions and all of them are customizable.  
defGraph is adaptable to map change so even if you add or remove routes in the middle of the game, extension tries to find the better road for you.  
also, you can update nodes positions, in another word you can have dynamically moving routes ;)  
The gif below shows you this exactly when the destination for all red points is cycled between two ends of a dynamic route.  

<img src="https://raw.githubusercontent.com/dev-masih/my-media-bin/master/defgraph/dynamic_routing_v4.gif" alt="dynamic routing gif version 4" style="max-width:100%;" />

This is a community project you are welcome to contribute to it, sending PR, suggest a feature or report a bug.  

## Installation  
You can use DefGraph in your project by adding this project as a [Defold library dependency](http://www.defold.com/manuals/libraries/). Open your game.project file and in the dependencies field under project add:  

	https://github.com/dev-masih/defgraph/archive/master.zip
  
Once added, you must require the main Lua module via  

```
local defgraph = require("defgraph.defgraph")
```
Then you can use the DefGraph functions using this module.  

[Official Defold game asset page for DefGraph](https://defold.com/assets/defgraph/)

## Module Settings  
There are several parameters for the module to works with, you can change these parameters one time for the entire module with `map_set_properties` and let each game object inherit those or set these parameters or each game object with `move_initialize` function. If you choose to not change any of them, the module uses it's own default values.  
#### **`Threshold`**  
This `number` value used as detection that an object is on a route or not. It's better to use a bigger value as object speed is getting higher to have better movement experience. The module default value is `1` and minimum for this value should be `1`.  
#### **`Path Curve Tightness`**  
This `number` value determines how tight a turn on the path should be. The module default value is `4` and minimum for this value should be `2`.  

<img src="https://raw.githubusercontent.com/dev-masih/my-media-bin/master/defgraph/tness_2.jpg" alt="Tightness 2"/> | <img src="https://raw.githubusercontent.com/dev-masih/my-media-bin/master/defgraph/tness_3.jpg" alt="Tightness 3"/> | <img src="https://raw.githubusercontent.com/dev-masih/my-media-bin/master/defgraph/tness_8.jpg" alt="Tightness 8"/>
:-------------: | :-------------: | :-------------:
Tightness: 2 | Tightness: 3 | Tightness: 8  

#### **`Path Curve Roundness`**  
This `number` value determines how round a turn on a path should be. The module default value is `3`. If this value equals `0` the path will not have any curve and the value of `settings_path_curve_tightness` and `settings_path_curve_max_distance_from_corner` will get ignored. The higher value for roundness will need more processing power especially when your map nodes are dynamically moving.  

<img src="https://raw.githubusercontent.com/dev-masih/my-media-bin/master/defgraph/round_0.jpg" alt="Roundness 0"/> | <img src="https://raw.githubusercontent.com/dev-masih/my-media-bin/master/defgraph/round_1.jpg" alt="Roundness 1"/> | <img src="https://raw.githubusercontent.com/dev-masih/my-media-bin/master/defgraph/round_5.jpg" alt="Roundness 5"/>
:-------------: | :-------------: | :-------------:
Roundness: 0 | Roundness: 1 | Roundness: 5  

#### **`Path Curve Max Distance From Corner`**  
This `number` value determines the maximum value of a turn distance to a corner. The module default value is `10`. If this value equals `0` the path will not have any curve but you should set `settings_path_curve_roundness` to `0` if this is what you want.  

<img src="https://raw.githubusercontent.com/dev-masih/my-media-bin/master/defgraph/max_10.jpg" alt="Max 10"/> | <img src="https://raw.githubusercontent.com/dev-masih/my-media-bin/master/defgraph/max_30.jpg" alt="Max 30"/> | <img src="https://raw.githubusercontent.com/dev-masih/my-media-bin/master/defgraph/max_50.jpg" alt="Max 50"/>
:-------------: | :-------------: | :-------------:
Max: 10 | Max: 30 | Max: 50  

#### **`Allow Enter on Route`**  
This `boolean` value determines is a game object can enter a map in the middle of a route or is should enter it from corners only. The module default value is `true`.  

<img src="https://raw.githubusercontent.com/dev-masih/my-media-bin/master/defgraph/allow_false.jpg" alt="False"/> | <img src="https://raw.githubusercontent.com/dev-masih/my-media-bin/master/defgraph/allow_true.jpg" alt="True"/>
:-------------: | :-------------:
False | True  

## ROUTETYPE  
This extension uses an enum named `ROUTETYPE` to specify how game objects are going to move inside the graph with multiple destinations.
#### **`ROUTETYPE.ONETIME`**  
This option allows the game object to go through destinations one by one and when it arrived at the last destination it will stop.  
#### **`ROUTETYPE.SHUFFLE`**  
This option allows the game object to go through destinations in the shuffled order none stop.  
#### **`ROUTETYPE.CYCLE`**  
This option allows the game object to go through destinations one by one and when it arrived at the last destination it will go back to the first one and cycle through all destinations none stop.  
> **Note:** These enums only affect when the game object has more than one destination.  

## Functions  
These are the list of available functions to use, for better understanding of how this module works, please take a look at project example.  

### `defgraph.map_set_properties([settings_gameobject_threshold], [settings_path_curve_tightness], [settings_path_curve_roundness], [settings_path_curve_max_distance_from_corner], [settings_allow_enter_on_route])`  
Set the main path and move calculation properties, nil inputs will fall back to module default values. These values will overwrite default module values.  
#### **arguments:**  
* **settings_gameobject_threshold** `(optional number)` - Optional threshold `[1]`  
* **settings_path_curve_tightness** `(optional number)` - Optional curve tightness `[4]`  
* **settings_path_curve_roundness** `(optional number)` - Optional curve roundness `[3]`  
* **settings_path_curve_max_distance_from_corner** `(optional number)` - Optional maximum distance from corner `[10]`  
* **settings_allow_enter_on_route** `(optional boolean)` - Optional Is game object allow entring on route `[true]`  

### `defgraph.map_add_node(position)`  
Adding a node at the given position (position.z will get ignored).  
#### **arguments:**  
* **position** `(vector3)` - New node position  
#### **return:**  
* `(number)` - Newly added node id  

> **Note:** Single nodes with no route attached to them are not participating in any routing calculations and it's better to remove them if you are not using them.  

### `defgraph.map_add_route(source_id, destination_id, [is_one_way])`  
Adding a two-way route between two nodes, you can set it as one way or two way.  
#### **arguments:**  
* **source_id** `(number)` - Source node id  
* **destination_id** `(number)` - Destination node id  
* **is_one_way** `(optional boolean)` - Optional Is adding just one-way route `[false]`  

> **Note:** If you never need to get pathfinding result in two way it's better to use a one-way path because it will be a bit computationally lighter.  

### `defgraph.map_remove_route(source_id, destination_id, [is_remove_one_way])`  
Removing an existing route between two nodes, you can set it to remove just one way or both ways.  
#### **arguments:**  
* **source_id** `(number)` - Source node id  
* **destination_id** `(number)` - Destination node id  
* **is_remove_one_way** `(optional boolean)` - Optional Is removing just one-way route `[false]`  

### `defgraph.map_remove_node(node_id)`  
Removing an existing node, attached routes to this node will remove.  
#### **arguments:**  
* **node_id** `(number)` - Node id   

### `defgraph.map_update_node_position(node_id, position)`  
Update an existing node position.  
#### **arguments:**  
* **node_id** `(number)` - Node id  
* **position** `(vector3)` - New node position  

### `defgraph.move_initialize(source_position, destination_list, [route_type], [initial_face_vector], [settings_gameobject_threshold], [settings_path_curve_tightness], [settings_path_curve_roundness], [settings_path_curve_max_distance_from_corner], [settings_allow_enter_on_route])`  
Initialize moves from a source position to destination node list inside the created map and using given threshold and initial face vector as game object initial face direction and path calculate settings considering the route type, **the optional value will fall back to module default values.**    
#### **arguments:**  
* **source_position** `(vector3)` - Node start position  
* **destination_list** `(table)` - Table of destinations id
* **route_type** `(optional ROUTETYPE)` - Optional Type of route `[ROUTETYPE.ONETIME]`
* **initial_face_vector** `(optional vecotr3)` - Optional Initial game object face vector `[nil]`
* **settings_gameobject_threshold** `(optional number)` - Optional threshold `[settings_main_gameobject_threshold]`
* **settings_path_curve_tightness** `(optional number)` - Optional curve tightness `[settings_main_path_curve_tightness]`
* **settings_path_curve_roundness** `(optional number)` - Optional curve roundness `[settings_main_path_curve_roundness]`
* **settings_path_curve_max_distance_from_corner** `(optional number)` - Optional maximum distance from corner `[settings_main_path_curve_max_distance_from_corner]`
* **settings_allow_enter_on_route** `(optional boolean)` - Optional Is game object allow entring on route `[settings_main_allow_enter_on_route]`  
#### **return:**  
* `(table)` - Special movement data table  
> **Note:** The returned special table consists of combined data to use later in `move_player` and `debug_draw_player_move` functions. If at any time you decided to change the destination of game object you have to call this function and overwrite old movement data with returned one.  

### `defgraph.move_player(current_position, speed, move_data)`  
Calculate movements from current position of the game object inside the created map considering given speed, using last calculated movement data.  
#### **arguments:**  
* **current_position** `(vector3)` - Game object current position
* **speed** `(number)` - Game object speed
* **move_data** `(table)` - Special movement data table  
#### **return:**  
* `(table)` - New movement data
* `(table)` - Move result table
  * **position** `(vector3)` - Next position of game object
  * **rotation** `(quat)` - Next rotation of game object
  * **is_reached** `(boolean)` - Is game object reached the destination  
  * **destination_id** `(number)` - Current node id of the game object's destination  

> **Note:** The returned new movement data should overwrite old movement data. normally this function is placed inside game object update function and you can set the game object position to `position` and rotation to `rotation` that is inside move result table. also, you should multiply `dt` with speed yourself before passing it to function.  

> **Note:** In case of a multidestination scenario, `is_reached` is going to be `true` when each time the game object reached destination with an id of `destination_id` after that `is_reached` is back to `false` and `destination_id` will set to next destination node id. 

### `defgraph.debug_set_properties([node_color], [two_way_route_color], [one_way_route_color], [draw_scale])`  
set debug drawing properties  
#### **arguments:**  
* **node_color** `(optional vector4)` - Optional debug color of nodes `[vector4(1, 0, 1, 1)]`
* **two_way_route_color** `(optional vector4)` - Optional debug color of two-way routes `[vector4(0, 1, 0, 1)]`
* **one_way_route_color** `(optional vector4)` - Optional debug color of one-way routes `[vector4(0, 1, 1, 1)]`
* **draw_scale** `(optional number)` - Optional drawing scale `[5]`  

### `defgraph.debug_draw_map_nodes([is_show_ids])`  
Debug draw all map nodes and choose to show node ids or not.  
#### **arguments:**  
* **is_show_ids** `(optional boolean)` - Optional Is draw nodes id `[false]`   

### `defgraph.debug_draw_map_routes()`  
Debug draw all map routes.  

### `defgraph.debug_draw_player_move(movement_data, color, [is_show_intersection])`
Debug draw player specific path with given color.  
#### **arguments:**  
* **movement_data** `(table)` - Special movement data table
* **color** `(vector4)` - Debug color of paths
* **is_show_intersection** `(optional boolean)` - Optional Is draw intersections `[false]` 

## Donations  
If you really like my work and want to support me, consider donating to me with BTC or ETH. All donations are optional and are greatly appreciated. 🙏  

BTC: `1EdDfXRuqnb5a8RmtT7ZnjGBcYeNzXLM3e`  
ETH: `0x99d3D5816e79bCfB2aE30d1e02f889C40800F141`  
  
## License  
DefGraph is released under the MIT License. See the [bundled LICENSE](https://github.com/dev-masih/defgraph/blob/master/LICENSE) file for details.  
