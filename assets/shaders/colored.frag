#version 330 core

in vec3 frag_color;

out vec4 out_frag_color;

void main() {
    // Output the vertex color as the fragment color
    out_frag_color = vec4(frag_color, 1.0);
}
