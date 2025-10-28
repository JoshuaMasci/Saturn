// The following culling code is based on the magic found here: github.com/zeux/niagara
struct CullData {
    float4x4 view_matrix;
   	float P00, P11, znear, zfar;
    float frustum[4];
};

bool isSphereVisable(CullData cull_data,  float4 sphere_pos_radius) {
    float3 center = mul(cull_data.view_matrix, float4(sphere_pos_radius.xyz, 1.0)).xyz;
    float radius = sphere_pos_radius.w;

    bool visible = true;

    //frustrum culling
    visible = visible && center.z * cull_data.frustum[1] - abs(center.x) * cull_data.frustum[0] > -radius;
    visible = visible && center.z * cull_data.frustum[3] - abs(center.y) * cull_data.frustum[2] > -radius;

    //this line doesnt work for some reason I will figure out later
   	//visible = visible && center.z + radius > cull_data.znear && center.z - radius < cull_data.zfar;

    return visible;
}

float4 transformSphere(float4x4 model_matix, float4 sphere_pos_radius) {
    const float4 new_pos = mul(model_matix, float4(sphere_pos_radius.xyz, 1.0));
    const float max_scale = max(length(model_matix[0].xyz), max(length(model_matix[1].xyz), length(model_matix[2].xyz)));
    const float new_radius = sphere_pos_radius.w * max_scale;
    return float4(new_pos.xyz, new_radius);
}
