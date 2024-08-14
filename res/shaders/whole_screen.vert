#version 450

out vec2 tex_coords;

void main()
{
    // Create a full-screen quad with the following vertex positions
    vec2 positions[4] = vec2[4](
        vec2(-1.0, -1.0),
        vec2( 1.0, -1.0),
        vec2(-1.0,  1.0),
        vec2( 1.0,  1.0)
    );

    // Set the vertex position to the appropriate position from the list
    gl_Position = vec4(positions[gl_VertexID], 0.0, 1.0);

    // Set the texture coordinates to be in the range [0, 1]
    tex_coords = positions[gl_VertexID] * 0.5 + 0.5;
}