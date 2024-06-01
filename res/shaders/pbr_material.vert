#version 330 core

layout(location = 0) in vec3 in_position;
layout(location = 1) in vec3 in_normal;
layout(location = 2) in vec4 in_tangent;
layout(location = 3) in vec2 in_uv0;

uniform mat4 view_projection_matrix;
uniform mat4 model_matrix;

//out vec3 frag_normal;
//out vec3 frag_tangent;
out vec2 frag_uv0;

void main() {
    mat3 normal_matrix = mat3(model_matrix);

    // Transform the vertex position
    vec4 world_position = model_matrix * vec4(in_position, 1.0);
    vec3 world_normal = normalize(normal_matrix * in_normal);
    vec3 world_tangent = normalize(normal_matrix * in_tangent.xyz);

    gl_Position = view_projection_matrix * world_position;

    //frag_normal = world_normal;
    //frag_tangent = world_tangent;
    frag_uv0 = in_uv0;
}
