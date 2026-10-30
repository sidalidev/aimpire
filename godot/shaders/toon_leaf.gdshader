// Feuillage peint : texture découpée (alpha), double face, normales arrondies autour du houppier
// (ombrage en boule comme dans les jeux de stratégie peints), et léger balancement au vent.
shader_type spatial;
render_mode cull_disabled, specular_disabled;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, hint_default_white;
uniform vec4 tint : source_color = vec4(1.0);
uniform float saturation = 1.25;
uniform float brightness = 1.22;
uniform float crown_y = 4.5;         // hauteur du centre du houppier, en unités du modèle
uniform float roundness = 0.9;
uniform float wind = 0.06;
uniform float ruin = 0.0;
#include "res://shaders/toon.gdshaderinc"

void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float k = clamp(VERTEX.y / max(crown_y, 0.5), 0.0, 2.0);
	float s = sin(TIME * 1.3 + w.x * 0.21 + w.z * 0.17 + VERTEX.y * 0.6);
	VERTEX.x += s * wind * k;
	VERTEX.z += s * wind * 0.6 * k;
	NORMAL = normalize(mix(NORMAL, normalize(VERTEX - vec3(0.0, crown_y, 0.0)), roundness));
}

void fragment() {
	vec4 t = texture(albedo_tex, UV);
	vec3 c = t.rgb * tint.rgb * COLOR.rgb;
	float g = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(vec3(g), c, saturation) * brightness;
	c = mix(c, vec3(g) * vec3(0.78, 0.8, 0.74), ruin);
	ALBEDO = c;
	ALPHA = t.a;
	ALPHA_SCISSOR_THRESHOLD = 0.45;
	ROUGHNESS = 1.0;
}
