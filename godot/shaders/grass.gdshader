// Touffes d'herbe qui ondulent au vent (déformation du sommet), dégradé du pied vers la pointe.
shader_type spatial;
render_mode cull_disabled, specular_disabled;
uniform vec3 base_col : source_color = vec3(0.30, 0.48, 0.18);
uniform vec3 tip_col : source_color = vec3(0.66, 0.80, 0.36);
uniform float wind = 0.22;
varying float h;
#include "res://shaders/toon.gdshaderinc"

void vertex() {
	h = UV.y;
	vec3 w = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float s = sin(TIME * 1.6 + w.x * 0.31 + w.z * 0.23) * 0.6 + sin(TIME * 2.7 + w.x * 0.8 - w.z * 0.5) * 0.25;
	VERTEX.x += s * wind * h * h;
	VERTEX.z += s * wind * 0.55 * h * h;
	NORMAL = vec3(0.0, 1.0, 0.0);
}

void fragment() {
	ALBEDO = mix(base_col, tip_col, h) * COLOR.rgb;
	ROUGHNESS = 1.0;
}
