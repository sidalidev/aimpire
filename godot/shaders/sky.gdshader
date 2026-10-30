// Ciel peint : dégradé chaud vers l'horizon, nuages doux qui dérivent, halo du soleil.
shader_type sky;
uniform vec3 top : source_color = vec3(0.33, 0.58, 0.86);
uniform vec3 horizon : source_color = vec3(0.97, 0.86, 0.68);
uniform vec3 ground : source_color = vec3(0.37, 0.49, 0.27);
uniform sampler2D clouds : filter_linear_mipmap, repeat_enable;

void sky() {
	float y = EYEDIR.y;
	vec3 c = mix(horizon, top, smoothstep(0.0, 0.6, y));
	if (y < 0.0) {
		c = mix(horizon, ground, smoothstep(0.0, -0.2, y));
	}
	vec2 uv = EYEDIR.xz / max(y, 0.07) * 0.16 + vec2(TIME * 0.004, TIME * 0.002);
	float cl = smoothstep(0.5, 0.76, texture(clouds, uv).r) * smoothstep(0.02, 0.3, y);
	c = mix(c, vec3(1.0, 0.97, 0.92), cl * 0.85);
	float sd = max(dot(EYEDIR, LIGHT0_DIRECTION), 0.0);
	c += LIGHT0_COLOR * pow(sd, 48.0) * 0.35;
	COLOR = c;
}
