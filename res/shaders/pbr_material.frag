#version 330 core

in vec2 frag_uv0;

out vec4 out_frag_color;

uniform vec4 base_color_factor;

void main() {
    out_frag_color = base_color_factor;
}
