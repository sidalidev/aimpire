// Feuillage du kit romain (cyprès, pins parasols, oliviers) : couleurs par sommet, normales arrondies autour du houppier
// (ombrage en boule), léger balancement au vent, grain de peinture.
shader_type spatial;
render_mode specular_disabled, cull_disabled;
uniform float ruin = 0.0;
uniform float grain = 0.10;
uniform float wind = 0.05;
#include "res://shaders/toon.gdshaderinc"

varying vec3 wpos;

void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float k = clamp(VERTEX.y / 4.0, 0.0, 2.0);
	float s = sin(TIME * 1.1 + w.x * 0.21 + w.z * 0.17 + VERTEX.y * 0.5);
	VERTEX.x += s * wind * k;
	VERTEX.z += s * wind * 0.6 * k;
	// UV.x porte la hauteur du centre du houppier (écrite par le kit) : normales arrondies vers ce centre
	vec3 centre = vec3(0.0, UV.x, 0.0);
	NORMAL = normalize(mix(NORMAL, normalize(VERTEX - centre), UV.y));
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float hash3(vec3 p) {
	return fract(sin(dot(p, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
}

void fragment() {
	vec3 c = pow(COLOR.rgb, vec3(2.2));
	float n = hash3(floor(wpos * 3.0)) - 0.5;
	c *= 1.0 + n * grain;
	float g = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(vec3(g), c, 1.2) * 1.1;   // feuillage un peu plus saturé et lumineux, comme les arbres Quaternius
	c = mix(c, vec3(g) * vec3(0.80, 0.80, 0.74), ruin);
	ALBEDO = c;
	ROUGHNESS = 1.0;
}
