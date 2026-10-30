// Éclairage peint : lumière en deux bandes douces, ombres teintées de violet-bleu (pas de noir), liseré de lumière sur les bords.
uniform vec3 shade_tint : source_color = vec3(0.47, 0.44, 0.68);
uniform float rim_strength = 0.22;

void light() {
	float wrap = clamp(dot(NORMAL, LIGHT) * 0.5 + 0.5, 0.0, 1.0);
	float band = smoothstep(0.40, 0.56, wrap) * 0.7 + smoothstep(0.70, 0.86, wrap) * 0.3;
	float lit = band * ATTENUATION;
	vec3 shade = mix(shade_tint * 0.55, vec3(1.0), lit);
	DIFFUSE_LIGHT += LIGHT_COLOR / PI * shade;
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	SPECULAR_LIGHT += LIGHT_COLOR / PI * rim * rim_strength * (0.35 + 0.65 * lit);
}
