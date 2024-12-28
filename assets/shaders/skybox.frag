#version 450

in vec2 tex_coords;

out vec4 frag_color;

uniform mat4 inverse_view_projection_matrix;
uniform samplerCube skybox;

void main()
{
    // Compute the clip-space position from texture coordinates
    vec4 clip_space_position = vec4(tex_coords * 2.0 - 1.0, 1.0, 1.0);

    // Transform clip-space position into world-space using the inverse view-projection matrix
    vec4 world_space_position = inverse_view_projection_matrix * clip_space_position;

    // Convert from homogeneous coordinates to 3D world space
    vec3 direction = normalize(world_space_position.xyz / world_space_position.w);

    // Sample the cube map with the calculated direction
    frag_color = texture(skybox, direction);
}