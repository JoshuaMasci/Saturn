pub const Transform = struct {};

pub const MeshHandle = u32;
pub const MaterialHandle = u32;

pub const Renderer = struct {
    const Self = @This();

    pub fn init() !Self {
        return Self{};
    }

    pub fn deinit(self: *Self) void {
        _ = self;
    }

    pub fn load_mesh(self: *Self, file_path: []const u8) !MeshHandle {
        _ = self;
        _ = file_path;
        return 0;
    }
    pub fn unload_mesh(self: *Self, mesh_handle: MeshHandle) void {
        _ = self;
        _ = mesh_handle;
    }

    pub fn load_material(self: *Self, file_path: []const u8) !MaterialHandle {
        _ = self;
        _ = file_path;
        return 0;
    }
    pub fn unload_material(self: *Self, material_handle: MaterialHandle) void {
        _ = self;
        _ = material_handle;
    }

    pub fn render_scene(self: Self, scene: *SceneData, camera_tranform: *const Transform) void {
        _ = self;
        _ = scene;
        _ = camera_tranform;
    }
};

pub const SceneInstanceHandle = u32;
pub const SceneData = struct {
    const Self = @This();

    pub fn init() !Self {
        return Self{};
    }

    pub fn deinit(self: *Self) void {
        _ = self;
    }

    pub fn add_instace(self: Self, mesh: MeshHandle, material: MaterialHandle, transform: *const Transform) SceneInstanceHandle {
        _ = self;
        _ = mesh;
        _ = material;
        _ = transform;
        return 0;
    }

    pub fn update_instance(self: Self, instance: SceneInstanceHandle, transform: *const Transform) void {
        _ = self;
        _ = instance;
        _ = transform;
    }

    pub fn remove_instance(self: Self, instance: SceneInstanceHandle) void {
        _ = self;
        _ = instance;
    }
};
