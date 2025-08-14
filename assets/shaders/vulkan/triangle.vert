float2 positions[3] = {
    float2(0.0, -0.5),
    float2(0.5, 0.5),
    float2(-0.5, 0.5)
};

float3 colors[3] = {
    float3(1.0, 0.0, 0.0),
    float3(0.0, 1.0, 0.0),
    float3(0.0, 0.0, 1.0)
};

struct VertexData {
    uint index : SV_VertexID;
};

struct PixelData
{
    float3 color : COLOR;
    float4 position : SV_Position;
};

PixelData main(VertexData vertex_data)
{
    PixelData output;

    output.position = float4(positions[vertex_data.index], 0.0, 1.0);
    output.color = colors[vertex_data.index];

    return output;
}
