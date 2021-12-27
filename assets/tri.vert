#version 450

layout(location = 0) in vec3 vertPos;
layout(location = 1) in vec3 vertColor;

layout(location = 0) out vec3 fragColor;

layout(push_constant) uniform Offset
{ 
	mat4 mvp;
} matrix;

void main() {
    gl_Position = matrix.mvp * vec4(vertPos, 1.0);
    fragColor = vertColor;
}