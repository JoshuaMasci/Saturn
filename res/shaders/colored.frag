#version 330 core

in vec3 fragColor;

out vec4 fragColorOutput;

void main() {
    // Output the vertex color as the fragment color
    fragColorOutput = vec4(fragColor, 1.0);
}
