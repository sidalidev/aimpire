// Kit romain procédural : couleurs par sommet (marbre, stuc, tuiles…), éclairage peint, variation de teinte par position
// pour casser l'uniformité des aplats, et mode ruine (couleurs passées).
shader_type spatial;
render_mode specular_disabled;
uniform float ruin = 0.0;
uniform float grain = 0.06;
#include "res://shaders/toon.gdshaderinc"

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float hash3(vec3 p) {
	return fract(sin(dot(p, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
}

void fragment() {
	vec3 c = pow(COLOR.rgb, vec3(2.2));   // les couleurs du kit sont données en sRGB : passage en linéaire, sinon tout est délavé
	// grain de peinture : petites variations de valeur par cellule de 0,4 m, comme des coups de pinceau
	float n = hash3(floor(wpos * 2.5)) - 0.5;
	c *= 1.0 + n * grain;
	float g = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(c, vec3(g) * vec3(0.80, 0.80, 0.74), ruin);
	ALBEDO = c;
	ROUGHNESS = 1.0;
}
