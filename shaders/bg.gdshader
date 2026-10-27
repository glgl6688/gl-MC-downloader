shader_type canvas_item;
// 背景：两团很淡的蓝色光晕缓慢漂移，让静态界面有一点呼吸感。
// 用 source_color 让 Godot 把它当颜色处理（线性化），不会偏色。

uniform vec4 base_color : source_color = vec4(0.102, 0.110, 0.125, 1.0);
uniform vec4 glow_color : source_color = vec4(0.29, 0.62, 1.0, 1.0);
uniform float drift_speed : hint_range(0.0, 1.0) = 0.15;
uniform float glow_strength : hint_range(0.0, 0.5) = 0.20;

void fragment() {
	vec2 uv = UV;
	float t = TIME * drift_speed;

	// 两团光斑各自缓慢画圈
	vec2 p1 = vec2(0.22 + 0.16 * sin(t * 1.7), 0.18 + 0.14 * cos(t * 1.3));
	vec2 p2 = vec2(0.82 + 0.14 * cos(t * 1.1), 0.86 + 0.12 * sin(t * 1.9));

	float d1 = 1.0 - smoothstep(0.0, 0.78, distance(uv, p1));
	float d2 = 1.0 - smoothstep(0.0, 0.86, distance(uv, p2));

	// 右下角稍微暗一点，视觉上有层次
	float vignette = 1.0 - 0.25 * smoothstep(0.4, 1.0, distance(uv, vec2(0.5)));

	float g = (d1 * 1.0 + d2 * 0.7) * glow_strength;
	COLOR = vec4(base_color.rgb * vignette + glow_color.rgb * g, 1.0);
}
