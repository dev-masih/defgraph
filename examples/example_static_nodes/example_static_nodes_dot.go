components {
  id: "dot"
  component: "/examples/example_static_nodes/example_static_nodes_dot.script"
}
embedded_components {
  id: "sprite"
  type: "sprite"
  data: "default_animation: \"dot\"\n"
  "material: \"/builtins/materials/sprite.material\"\n"
  "textures {\n"
  "  sampler: \"texture_sampler\"\n"
  "  texture: \"/examples/assets/atlas.atlas\"\n"
  "}\n"
  ""
}
