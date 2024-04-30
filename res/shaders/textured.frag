#version 330 core

in vec2 frag_uv0;

out vec4 out_frag_color;

void main() {
    out_frag_color = vec4(frag_uv0, 0.0, 1.0);
}
