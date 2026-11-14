shader_type canvas_item;
// Draws only the soft ink edge of the texture's alpha; interior is transparent.

uniform vec4 ink_color : source_color = vec4(0.14, 0.10, 0.08, 0.6);
uniform float width = 2.0;

void fragment() {
    vec2 px = TEXTURE_PIXEL_SIZE * width;
    float a = texture(TEXTURE, UV).a;
    float hi = a;
    float lo = a;
    for (int i = 0; i < 8; i++) {
        float ang = float(i) * 0.785398;
        float n = texture(TEXTURE, UV + vec2(cos(ang), sin(ang)) * px).a;
        hi = max(hi, n);
        lo = min(lo, n);
    }
    float edge = smoothstep(0.0, 1.0, hi - lo);
    COLOR = vec4(ink_color.rgb, ink_color.a * edge);
}
