// Eau peinte : turquoise clair au bord, bleu profond au centre, reflets qui bougent, écume là où l'eau touche la berge.
shader_type spatial;
render_mode blend_mix, depth_draw_always, specular_schlick_ggx;
uniform sampler2D depth_tex : hint_depth_texture, filter_linear_mipmap;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform vec3 shallow : source_color = vec3(0.36, 0.78, 0.78);
uniform vec3 deep : source_color = vec3(0.10, 0.36, 0.55);
uniform vec3 foam : source_color = vec3(0.95, 0.97, 0.92);

void fragment() {
	float d = texture(depth_tex, SCREEN_UV).r;
	// profondeur en coordonnées normalisées : [-1, 1] en OpenGL (rendu Compatibilité du téléphone), [0, 1] ailleurs ; sans
	// cette conversion, le lac paraît tout blanc d'écume sur Android
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	vec4 v = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, d * 2.0 - 1.0, 1.0);
#else
	vec4 v = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, d, 1.0);
#endif
	v.xyz /= v.w;
	float below = VERTEX.z - v.z;
	float t = clamp(below / 2.2, 0.0, 1.0);
	vec3 wp = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float n = texture(noise_tex, wp.xz * 0.07 + TIME * vec2(0.018, 0.01)).r * texture(noise_tex, wp.xz * 0.12 - TIME * vec2(0.01, 0.016)).r;
	vec3 c = mix(shallow, deep, t);
	c += vec3(0.16) * smoothstep(0.30, 0.42, n);
	float f = 1.0 - smoothstep(0.0, 0.55, below - n * 0.6);
	c = mix(c, foam, f * 0.9);
	ALBEDO = c;
	ALPHA = mix(0.7, 0.94, t);
	ROUGHNESS = 0.12;
}
