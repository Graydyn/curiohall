shader_type canvas_item;
// A missing structure drawn as a faint ink sketch of its own painting: the
// strong colour edges of the texture (its walls, roof lines, glazing bars),
// only where the texture's alpha mask is solid. Interior is transparent.

uniform vec4 ink_color : source_color = vec4(0.14, 0.10, 0.08, 0.6);
uniform float width = 1.5;      // sample distance, texels
uniform float edge_lo = 0.12;   // luma gradient where ink starts
uniform float edge_hi = 0.35;   // ... and is full
uniform float core = 0.75;      // alpha above which the mask counts as the building

void fragment() {
    vec2 px = TEXTURE_PIXEL_SIZE * width;
    // (Inline: passing TEXTURE into a helper function errors in Godot 4.)
    vec3 w = vec3(0.299, 0.587, 0.114);
    float tl = dot(texture(TEXTURE, UV + vec2(-px.x, -px.y)).rgb, w);
    float t = dot(texture(TEXTURE, UV + vec2(0.0, -px.y)).rgb, w);
    float tr = dot(texture(TEXTURE, UV + vec2(px.x, -px.y)).rgb, w);
    float l = dot(texture(TEXTURE, UV + vec2(-px.x, 0.0)).rgb, w);
    float r = dot(texture(TEXTURE, UV + vec2(px.x, 0.0)).rgb, w);
    float bl = dot(texture(TEXTURE, UV + vec2(-px.x, px.y)).rgb, w);
    float b = dot(texture(TEXTURE, UV + vec2(0.0, px.y)).rgb, w);
    float br = dot(texture(TEXTURE, UV + vec2(px.x, px.y)).rgb, w);
    float gx = (tr + 2.0 * r + br) - (tl + 2.0 * l + bl);
    float gy = (bl + 2.0 * b + br) - (tl + 2.0 * t + tr);
    float edge = smoothstep(edge_lo, edge_hi, length(vec2(gx, gy)));
    float inside = smoothstep(core - 0.1, core + 0.1, texture(TEXTURE, UV).a);
    COLOR = vec4(ink_color.rgb, ink_color.a * edge * inside);
}
