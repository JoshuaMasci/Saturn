const std = @import("std");

const zm = @import("zmath");
const SceneCamera = @import("camera.zig").SceneCamera;
const Transform = @import("../transform.zig");

pub const CullData = extern struct {
    view_matrix: zm.Mat,
    p00_p11_znear_zfar: zm.Vec,
    frustum: zm.Vec,

    pub fn init(camera: SceneCamera, aspect_ratio: f32) @This() {
        // The following culling code is based on the magic found here: github.com/zeux/niagara
        const view_matrix = camera.transform.getViewMatrix();
        const camera_data = camera.settings.perspective; //Only works for perspective
        const projection_matrix = camera_data.getPerspectiveMatrix(aspect_ratio);
        const projection_t = zm.transpose(projection_matrix);
        const frustum_x = normalizePlane(projection_t[3] + projection_t[0]);
        const frustum_y = normalizePlane(projection_t[3] + projection_t[1]);
        return .{
            .view_matrix = view_matrix,
            .p00_p11_znear_zfar = .{ projection_matrix[0][0], projection_matrix[1][1], camera_data.near, camera_data.far orelse 1000.0 },
            .frustum = .{ frustum_x[0], frustum_x[2], frustum_y[1], frustum_y[2] },
        };
    }
};

fn normalizePlane(plane: zm.Vec) zm.Vec {
    return plane / zm.length3(plane);
}
