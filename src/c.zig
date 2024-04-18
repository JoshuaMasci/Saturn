pub usingnamespace @cImport({
    @cInclude("SDL3/SDL.h");
    @cInclude("glad/glad.h");

    @cDefine("CIMGUI_DEFINE_ENUMS_AND_STRUCTS", {});
    @cInclude("cimgui/cimgui.h");
});
