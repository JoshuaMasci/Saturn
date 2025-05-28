#include <codecvt>
#include <cstring>
#include <dxc/dxcapi.h>
#include <locale>
#include <string>
#include <vector>

std::wstring stringToWstring(const std::string &str) {
  std::wstring_convert<std::codecvt_utf8<wchar_t>> converter;
  return converter.from_bytes(str);
}

extern "C" {

struct DxcCompileResult {
  uint8_t *data;
  size_t size;
  char *error_message;
  int success;
};

struct DxcCompiler {
  IDxcCompiler3 *compiler;
  IDxcUtils *utils;
  IDxcIncludeHandler *include_handler;
};

DxcCompiler *dxc_create_compiler() {
  DxcCompiler *ctx = new DxcCompiler();

  HRESULT hr =
      DxcCreateInstance(CLSID_DxcCompiler, IID_PPV_ARGS(&ctx->compiler));
  if (FAILED(hr)) {
    delete ctx;
    return nullptr;
  }

  hr = DxcCreateInstance(CLSID_DxcUtils, IID_PPV_ARGS(&ctx->utils));
  if (FAILED(hr)) {
    ctx->compiler->Release();
    delete ctx;
    return nullptr;
  }

  hr = ctx->utils->CreateDefaultIncludeHandler(&ctx->include_handler);
  if (FAILED(hr)) {
    ctx->utils->Release();
    ctx->compiler->Release();
    delete ctx;
    return nullptr;
  }

  return ctx;
}

DxcCompileResult dxc_compile_hlsl_to_spirv(DxcCompiler *ctx,
                                           const char *source_code,
                                           size_t source_size,
                                           const char *entry_point,
                                           const char *target_profile) {
  DxcCompileResult result = {0};

  if (!ctx || !source_code || !entry_point || !target_profile) {
    result.error_message = strdup("Invalid parameters");
    return result;
  }

  IDxcBlobEncoding *source_blob = nullptr;
  HRESULT hr = ctx->utils->CreateBlob(
      source_code, static_cast<UINT32>(source_size), CP_UTF8, &source_blob);

  if (FAILED(hr) || !source_blob) {
    result.error_message = strdup("Failed to create source blob");
    return result;
  }

  std::wstring w_entry_point = stringToWstring(std::string(entry_point));
  std::wstring w_target_profile = stringToWstring(std::string(target_profile));

  std::vector<LPCWSTR> arguments = {
      L"-spirv",                     // Generate SPIR-V
      L"-fspv-target-env=vulkan1.3", // Target Vulkan 1.3
      L"-Zi",                        // Debug info
  };

  arguments.push_back(L"-E");
  arguments.push_back(w_entry_point.c_str());

  arguments.push_back(L"-T");
  arguments.push_back(w_target_profile.c_str());

  DxcBuffer source_buffer = {};
  source_buffer.Ptr = source_blob->GetBufferPointer();
  source_buffer.Size = source_blob->GetBufferSize();
  source_buffer.Encoding = CP_UTF8;

  IDxcResult *compile_result = nullptr;
  hr = ctx->compiler->Compile(
      &source_buffer, arguments.data(), static_cast<UINT32>(arguments.size()),
      ctx->include_handler, IID_PPV_ARGS(&compile_result));

  source_blob->Release();

  if (FAILED(hr) || !compile_result) {
    result.error_message = strdup("Compilation failed");
    return result;
  }

  HRESULT compile_status;
  hr = compile_result->GetStatus(&compile_status);

  if (FAILED(hr)) {
    compile_result->Release();
    result.error_message = strdup("Failed to get compilation status");
    return result;
  }

  if (FAILED(compile_status)) {
    // Get error messages
    IDxcBlobEncoding *error_blob = nullptr;
    hr = compile_result->GetErrorBuffer(&error_blob);

    if (SUCCEEDED(hr) && error_blob && error_blob->GetBufferSize() > 0) {
      size_t error_size = error_blob->GetBufferSize();
      result.error_message = static_cast<char *>(malloc(error_size + 1));
      memcpy(result.error_message, error_blob->GetBufferPointer(), error_size);
      result.error_message[error_size] = '\0';
      error_blob->Release();
    } else {
      result.error_message = strdup("Compilation failed with unknown error");
    }

    compile_result->Release();
    return result;
  }

  // Get the compiled output
  IDxcBlob *output_blob = nullptr;
  hr = compile_result->GetOutput(DXC_OUT_OBJECT, IID_PPV_ARGS(&output_blob),
                                 nullptr);

  if (FAILED(hr) || !output_blob) {
    compile_result->Release();
    result.error_message = strdup("Failed to get compiled output");
    return result;
  }

  // Copy the result
  result.size = output_blob->GetBufferSize();
  result.data = static_cast<uint8_t *>(malloc(result.size));
  memcpy(result.data, output_blob->GetBufferPointer(), result.size);
  result.success = 1;

  output_blob->Release();
  compile_result->Release();

  return result;
}

void dxc_free_result(DxcCompileResult *result) {
  if (result) {
    if (result->data) {
      free(result->data);
      result->data = nullptr;
    }
    if (result->error_message) {
      free(result->error_message);
      result->error_message = nullptr;
    }
    result->size = 0;
    result->success = 0;
  }
}

void dxc_destroy_compiler(DxcCompiler *ctx) {
  if (ctx) {
    if (ctx->include_handler) {
      ctx->include_handler->Release();
    }
    if (ctx->utils) {
      ctx->utils->Release();
    }
    if (ctx->compiler) {
      ctx->compiler->Release();
    }
    delete ctx;
  }
}

} // extern "C"
