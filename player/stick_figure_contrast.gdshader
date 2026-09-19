shader_type canvas_item;
// Draws the stick figure in ink over light backgrounds and in white over
// really dark ones, decided per pixel from what's behind it on screen - a
// figure straddling a dark photo and a white slide splits accordingly.

// Everything drawn before the figure (slides, stage), mipmapped so the
// sample can be blurred: fine detail like text under a limb shouldn't flip
// the color and make the figure flicker.
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform vec4 ink_color : source_color = vec4(0.08, 0.08, 0.08, 1.0);
uniform vec4 light_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
// Background luminance below which the figure turns white.
uniform float threshold = 0.25;
uniform float softness = 0.07;
uniform float blur_lod = 3.0;

void fragment() {
	vec3 bg = textureLod(screen_tex, SCREEN_UV, blur_lod).rgb;
	float lum = dot(bg, vec3(0.2126, 0.7152, 0.0722));
	float t = smoothstep(threshold - softness, threshold + softness, lum);
	COLOR = vec4(mix(light_color.rgb, ink_color.rgb, t), COLOR.a);
}
