#version 330 core

layout(location = 0) in vec3 inPosition;
layout(location = 1) in vec3 inColor;

uniform mat4 view_projection_matrix;
uniform mat4 model_matrix;

out vec3 fragColor;

void main() {
    // Transform the vertex position
    vec4 world_position = model_matrix * vec4(inPosition, 1.0);
    gl_Position = view_projection_matrix * world_position;

    // Pass the vertex color to the fragment shader
    fragColor = inColor;
}
