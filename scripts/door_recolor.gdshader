shader_type canvas_item;

uniform vec4 from_color : source_color = vec4(1.0, 0.0, 0.0, 1.0);
uniform vec4 to_color : source_color = vec4(0.0, 0.8, 1.0, 1.0);
uniform float tolerance = 0.18;
uniform bool keep_brightness = true;

void fragment() {
	vec4 tex = texture(TEXTURE, UV);

	float mask = 1.0 - smoothstep(
		tolerance * 0.5,
		tolerance,
		distance(tex.rgb, from_color.rgb)
	);

	vec3 replacement = to_color.rgb;

	if (keep_brightness) {
		float brightness = max(max(tex.r, tex.g), tex.b);
		replacement *= brightness;
	}

	tex.rgb = mix(tex.rgb, replacement, mask);

	COLOR = tex;
}