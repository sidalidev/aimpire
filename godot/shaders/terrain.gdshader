// Sol peint : grandes taches d'herbe de trois verts, coups de pinceau étirés, plaques de terre et de fleurs,
// roche grise sur les hauteurs, et ombres de nuages qui passent.
shader_type spatial;
render_mode specular_disabled;
uniform sampler2D noise_a : filter_linear_mipmap, repeat_enable;
uniform sampler2D noise_b : filter_linear_mipmap, repeat_enable;
uniform vec3 grass_dark : source_color = vec3(0.24, 0.42, 0.15);
uniform vec3 grass_mid : source_color = vec3(0.36, 0.55, 0.20);
uniform vec3 grass_light : source_color = vec3(0.52, 0.68, 0.28);
uniform vec3 dirt : source_color = vec3(0.56, 0.45, 0.29);
uniform vec3 rock : source_color = vec3(0.55, 0.55, 0.52);
uniform vec3 flower : source_color = vec3(0.93, 0.86, 0.48);
varying vec3 wpos;
#include "res://shaders/toon.gdshaderinc"

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = wpos.xz;
	float big = texture(noise_a, p * 0.011).r;
	float stroke = texture(noise_b, vec2(p.x * 0.022 + p.y * 0.008, p.y * 0.011)).r;   // coups de pinceau étirés en diagonale
	float small = texture(noise_a, p * 0.07).r;
	vec3 c = mix(grass_dark, grass_mid, smoothstep(0.32, 0.62, big));
	c = mix(c, grass_light, smoothstep(0.55, 0.8, stroke) * 0.4);
	c = mix(c, dirt, smoothstep(0.24, 0.16, big) * 0.65);
	c = mix(c, flower, smoothstep(0.80, 0.86, small) * 0.45 * smoothstep(0.4, 0.6, big));
	c = mix(c, rock, smoothstep(5.0, 16.0, wpos.y) * 0.85);
	float cloud = texture(noise_a, p * 0.0045 + vec2(TIME * 0.006, TIME * 0.0035)).r;
	c *= mix(1.0, 0.8, smoothstep(0.58, 0.74, cloud));
	ALBEDO = c;
	ROUGHNESS = 1.0;
}
