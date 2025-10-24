struct Frustum {
    float4 planes[6];
    uint32_t plane_count;
};

float4 transformSphere(float4x4 model_matix, float4 sphere_pos_radius) {
    const float4 new_pos = mul(model_matix, float4(sphere_pos_radius.xyz, 1.0));
    const float max_scale = max(length(model_matix[0].xyz), max(length(model_matix[1].xyz), length(model_matix[2].xyz)));
    const float new_radius = sphere_pos_radius.w * max_scale;
    return float4(new_pos.xyz, new_radius);
}

bool calcSpherePlaneIntersect(float4 plane, float4 sphere_pos_radius)
{
    float distance = dot(plane.xyz, sphere_pos_radius.xyz) - plane.w;
    return distance > -sphere_pos_radius.w;
}

bool calcVisable(Frustum frustum, float4 sphere_pos_radius) {
    for (uint32_t i = 0; i < frustum.plane_count; i++) {
        if (calcSpherePlaneIntersect(frustum.planes[i], sphere_pos_radius)) {
            return false;
        }
    }
    return true;
}
