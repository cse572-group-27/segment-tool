shader_type canvas_item;

void fragment() {
	vec4 color = texture(TEXTURE, UV);
	float factor = abs(2.0 * (UV.y - 0.5));
	factor = pow(factor, 1.8);
	factor = 1.0 - factor;
	factor = smoothstep(0.0, 0.8, factor);
	color.a = factor;
	COLOR = color;
}
