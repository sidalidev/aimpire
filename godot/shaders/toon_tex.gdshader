// Objets Kenney (maisons, arbres, personnages) : leur texture d'origine, éclairée façon peinture.
shader_type spatial;
render_mode specular_disabled;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, hint_default_white;
uniform vec4 tint : source_color = vec4(1.0);
uniform float saturation = 1.12;
uniform float ruin = 0.0;
#include "res://shaders/toon.gdshaderinc"

void fragment() {
	vec3 c = texture(albedo_tex, UV).rgb * tint.rgb * COLOR.rgb;
	float g = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(vec3(g), c, saturation);
	c = mix(c, vec3(g) * vec3(0.78, 0.8, 0.74), ruin);   // ruine : couleurs passées, gris verdâtre
	ALBEDO = c;
	ROUGHNESS = 1.0;
}
