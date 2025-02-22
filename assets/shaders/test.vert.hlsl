// Input structure
struct VertexInput
{
    float3 position : POSITION;
    float3 normal : NORMAL;
    float4 tangent : TANGENT;
    float2 uv0 : TEXCOORD0;
};

// Output structure
struct PixelInput
{
    float2 frag_uv0 : TEXCOORD0;
    float4 position : SV_Position;

};

// Uniforms
cbuffer ModelViewProjectionBuffer : register(b0, space1)
{
    float4x4 view_projection_matrix;
    float4x4 model_matrix;
};

// Main vertex shader function
PixelInput main(VertexInput input)
{
    PixelInput output;

    // Create normal matrix from the model matrix
    float3x3 normal_matrix = (float3x3)model_matrix;

    // Transform the vertex position
    float4 world_position = mul(model_matrix, float4(input.position, 1.0f));
    float3 world_normal = normalize(mul(normal_matrix, input.normal));
    float3 world_tangent = normalize(mul(normal_matrix, input.tangent.xyz));

    // Compute final vertex position in clip space
    output.position = mul(view_projection_matrix, world_position);

    // Pass UV to the fragment shader
    output.frag_uv0 = input.uv0;

    return output;
}