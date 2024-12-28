#version 330 core

in vec2 frag_uv0;

out vec4 out_frag_color;

uniform vec4 base_color_factor;
uniform int base_color_texture_enable = 0;
uniform sampler2D base_color_texture;

void main() {
    vec4 base_color = base_color_factor;

    if (base_color_texture_enable != 0) {
        base_color *= texture(base_color_texture, frag_uv0);
    }

    out_frag_color = base_color;
}
