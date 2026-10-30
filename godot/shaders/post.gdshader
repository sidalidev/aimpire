// Passe plein écran : contours dessinés à l'encre brune (différences de profondeur et de normales),
// plus fins au loin, et un léger vignetage chaud. Rendu avant les textes du monde (render_priority très bas).
shader_type spatial;
render_mode unshaded, depth_draw_never, depth_test_disabled, cull_disabled, fog_disabled;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform sampler2D normal_tex : hint_normal_roughness_texture, filter_nearest;
uniform vec3 line_col : source_color = vec3(0.18, 0.11, 0.07);
uniform float strength = 0.6;
uniform float vignette = 0.16;

float lin(vec2 uv, mat4 inv_proj) {
	float d = texture(depth_tex, uv).r;
	vec4 v = inv_proj * vec4(uv * 2.0 - 1.0, d, 1.0);
	return -v.z / v.w;
}

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

void fragment() {
	vec2 px = 1.25 / VIEWPORT_SIZE;
	float d0 = lin(SCREEN_UV, INV_PROJECTION_MATRIX);
	float dd = 0.0;
	vec3 n0 = texture(normal_tex, SCREEN_UV).xyz * 2.0 - 1.0;
	float dn = 0.0;
	vec2 offs[4] = vec2[](vec2(px.x, 0.0), vec2(-px.x, 0.0), vec2(0.0, px.y), vec2(0.0, -px.y));
	for (int i = 0; i < 4; i++) {
		dd += abs(lin(SCREEN_UV + offs[i], INV_PROJECTION_MATRIX) - d0);
		dn += length((texture(normal_tex, SCREEN_UV + offs[i]).xyz * 2.0 - 1.0) - n0);
	}
	float edge = max(smoothstep(0.09, 0.18, dd / max(d0, 0.001)), smoothstep(1.1, 1.8, dn) * 0.6);
	edge *= 1.0 - smoothstep(55.0, 130.0, d0);
	vec3 c = texture(screen_tex, SCREEN_UV).rgb;
	c = mix(c, line_col, edge * strength);
	float v = smoothstep(0.85, 0.3, length(SCREEN_UV - 0.5));
	c *= mix(1.0 - vignette, 1.0, v);
	ALBEDO = c;
}
