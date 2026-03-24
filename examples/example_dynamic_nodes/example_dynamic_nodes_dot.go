components {
  id: "dot"
  component: "/examples/example_dynamic_nodes/example_dynamic_nodes_dot.script"
}
embedded_components {
  id: "sprite"
  type: "sprite"
  data: "default_animation: \"pointy_dot\"\n"
  "material: \"/builtins/materials/sprite.material\"\n"
  "textures {\n"
  "  sampler: \"texture_sampler\"\n"
  "  texture: \"/examples/assets/atlas.atlas\"\n"
  "}\n"
  ""
}
