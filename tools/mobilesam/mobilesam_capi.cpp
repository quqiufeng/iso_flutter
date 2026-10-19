// mobilesam_capi.cpp — C ABI for StaticPy FFI.
#include "mobilesam.hpp"

#include <cstdlib>
#include <memory>
#include <mutex>
#include <string>

namespace {
std::mutex g_mutex;
msam::MobileSAM* g_model = nullptr;
std::string g_enc, g_dec;

std::string EnvOr(const char* key, const char* def) {
    const char* v = std::getenv(key);
    return (v && *v) ? std::string(v) : std::string(def);
}

bool UseCuda() {
    const char* v = std::getenv("MOBILESAM_CUDA");
    return !(v && v[0] == '0');
}
}  // namespace

extern "C" {

int mobilesam_segment(const char* in_path, const char* out_path, const char* mask_path,
                      const char* points_csv, const char* labels_csv, int mode) {
    if (!in_path || !out_path) return -1;
    try {
        std::lock_guard<std::mutex> lock(g_mutex);
        const std::string enc = EnvOr("MOBILESAM_ENCODER", "/models/mobilesam/mobilesam.encoder.onnx");
        const std::string dec = EnvOr("MOBILESAM_DECODER", "/models/mobilesam/mobilesam.decoder.onnx");
        if (!g_model || g_enc != enc || g_dec != dec) {
            g_model = new msam::MobileSAM(enc, dec, UseCuda());
            g_enc = enc;
            g_dec = dec;
        }
        g_model->Segment(in_path, out_path, mask_path ? mask_path : "",
                         points_csv ? points_csv : "", labels_csv ? labels_csv : "", mode);
        return 0;
    } catch (...) {
        return -1;
    }
}

int mobilesam_auto(const char* in_path, const char* out_path, const char* mask_path,
                   int grid, float iou_thr, float min_area, float max_area, int mode) {
    if (!in_path || !out_path) return -1;
    try {
        std::lock_guard<std::mutex> lock(g_mutex);
        const std::string enc = EnvOr("MOBILESAM_ENCODER", "/models/mobilesam/mobilesam.encoder.onnx");
        const std::string dec = EnvOr("MOBILESAM_DECODER", "/models/mobilesam/mobilesam.decoder.onnx");
        if (!g_model || g_enc != enc || g_dec != dec) {
            g_model = new msam::MobileSAM(enc, dec, UseCuda());
            g_enc = enc;
            g_dec = dec;
        }
        g_model->Auto(in_path, out_path, mask_path ? mask_path : "",
                      grid, iou_thr, min_area, max_area, mode);
        return 0;
    } catch (...) {
        return -1;
    }
}

}  // extern "C"
