struct VertexData
{
    float2 frag_uv0 : TEXCOORD0;
    float2 frag_uv1 : TEXCOORD1;
    uint material_index: MAT;
    float4 position : SV_Position;
};
