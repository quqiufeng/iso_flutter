// mobilesam.cpp — MobileSAM (TinyViT + prompt decoder) via ONNX Runtime.
//
// Encoder: input_image [H,W,3] f32, ImageNet-normalized; output embeddings [1,256,64,64].
// Decoder: image_embeddings + point_coords/labels -> masks + iou + low_res_masks.
#include "mobilesam.hpp"

#include <onnxruntime_cxx_api.h>

#define STB_IMAGE_IMPLEMENTATION
#include "stb_image.h"
#define STB_IMAGE_RESIZE_IMPLEMENTATION
#include "stb_image_resize.h"
#define STB_IMAGE_WRITE_IMPLEMENTATION
#include "stb_image_write.h"

#include <algorithm>
#include <array>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <sstream>
#include <stdexcept>
#include <vector>

namespace msam {
namespace {

constexpr int kSize = 1024;
constexpr int kLow = 256;
const float kMean[3] = {0.485f, 0.456f, 0.406f};
const float kStd[3] = {0.229f, 0.224f, 0.225f};

struct Image {
    int w = 0, h = 0;
    std::vector<unsigned char> rgb;  // w*h*3
};

Image LoadRgbWhite(const std::string& path) {
    int w = 0, h = 0, c = 0;
    unsigned char* d = stbi_load(path.c_str(), &w, &h, &c, 4);
    if (!d) throw std::runtime_error("cannot read image: " + path);
    Image im;
    im.w = w;
    im.h = h;
    im.rgb.resize(static_cast<size_t>(w) * h * 3);
    for (size_t i = 0; i < static_cast<size_t>(w) * h; ++i) {
        const int a = d[i * 4 + 3];
        for (int k = 0; k < 3; ++k) {
            const int v = d[i * 4 + k];
            im.rgb[i * 3 + k] = static_cast<unsigned char>((v * a + 255 * (255 - a) + 127) / 255);
        }
    }
    stbi_image_free(d);
    return im;
}

float Sigmoid(float x) {
    if (x >= 0.0f) {
        const float e = std::exp(-x);
        return 1.0f / (1.0f + e);
    }
    const float e = std::exp(x);
    return e / (1.0f + e);
}

unsigned char To8(float p) {
    int v = static_cast<int>(std::lround(p * 255.0f));
    return static_cast<unsigned char>(std::max(0, std::min(255, v)));
}

std::vector<std::pair<float, float>> ParsePoints(const std::string& csv, int w, int h) {
    std::vector<std::pair<float, float>> pts;
    if (csv.empty()) {
        pts.emplace_back(w * 0.5f, h * 0.65f);
        return pts;
    }
    std::stringstream ss(csv);
    std::string item;
    while (std::getline(ss, item, ';')) {
        if (item.empty()) continue;
        std::stringstream is(item);
        std::string sx, sy;
        if (!std::getline(is, sx, ',') || !std::getline(is, sy, ',')) continue;
        try {
            pts.emplace_back(std::stof(sx), std::stof(sy));
        } catch (...) {
        }
    }
    if (pts.empty()) pts.emplace_back(w * 0.5f, h * 0.65f);
    return pts;
}

std::vector<float> ParseLabels(const std::string& csv, size_t n) {
    std::vector<float> labels;
    if (!csv.empty()) {
        std::stringstream ss(csv);
        std::string item;
        while (std::getline(ss, item, ';')) {
            if (item.empty()) continue;
            try {
                labels.push_back(std::stof(item));
            } catch (...) {
                labels.push_back(1.0f);
            }
        }
    }
    while (labels.size() < n) labels.push_back(1.0f);
    labels.resize(n);
    return labels;
}

struct Candidate {
    float iou = 0.0f;
    float area = 0.0f;
    float border = 0.0f;
    int gx = 0, gy = 0;
    std::vector<float> full_mask;  // H*W logits
};

}  // namespace

struct MobileSAM::Impl {
    Ort::Env env;
    Ort::SessionOptions enc_so;
    Ort::SessionOptions dec_so;
    std::unique_ptr<Ort::Session> enc;
    std::unique_ptr<Ort::Session> dec;
    Ort::MemoryInfo mi;
    std::string provider = "CPU";

    Impl(const std::string& enc_path, const std::string& dec_path, bool use_cuda)
        : env(ORT_LOGGING_LEVEL_ERROR, "mobilesam"),
          mi(Ort::MemoryInfo::CreateCpu(OrtArenaAllocator, OrtMemTypeDefault)) {
        auto setup = [&](Ort::SessionOptions& so) {
            so.SetGraphOptimizationLevel(GraphOptimizationLevel::ORT_ENABLE_ALL);
            so.SetLogSeverityLevel(ORT_LOGGING_LEVEL_ERROR);
            if (use_cuda) {
                try {
                    OrtCUDAProviderOptions cuda_options{};
                    cuda_options.device_id = 0;
                    so.AppendExecutionProvider_CUDA(cuda_options);
                    provider = "CUDA";
                } catch (const std::exception&) {
                    provider = "CPU";
                }
            }
        };
        setup(enc_so);
        setup(dec_so);
        try {
            enc = std::make_unique<Ort::Session>(env, enc_path.c_str(), enc_so);
            dec = std::make_unique<Ort::Session>(env, dec_path.c_str(), dec_so);
        } catch (const std::exception&) {
            if (provider == "CUDA") {
                provider = "CPU";
                Ort::SessionOptions cpu_enc;
                Ort::SessionOptions cpu_dec;
                cpu_enc.SetGraphOptimizationLevel(GraphOptimizationLevel::ORT_ENABLE_ALL);
                cpu_dec.SetGraphOptimizationLevel(GraphOptimizationLevel::ORT_ENABLE_ALL);
                cpu_enc.SetLogSeverityLevel(ORT_LOGGING_LEVEL_ERROR);
                cpu_dec.SetLogSeverityLevel(ORT_LOGGING_LEVEL_ERROR);
                enc = std::make_unique<Ort::Session>(env, enc_path.c_str(), cpu_enc);
                dec = std::make_unique<Ort::Session>(env, dec_path.c_str(), cpu_dec);
            } else {
                throw;
            }
        }
    }
};

MobileSAM::MobileSAM(const std::string& encoder_path, const std::string& decoder_path, bool use_cuda)
    : impl_(std::make_unique<Impl>(encoder_path, decoder_path, use_cuda)) {}

MobileSAM::~MobileSAM() = default;

const std::string& MobileSAM::provider() const { return impl_->provider; }

namespace {

// Run encoder once; return embeddings [1,256,64,64].
std::vector<float> Encode(MobileSAM::Impl& im, const Image& img) {
    std::vector<unsigned char> resized(static_cast<size_t>(kSize) * kSize * 3);
    stbir_resize_uint8(img.rgb.data(), img.w, img.h, 0, resized.data(), kSize, kSize, 0, 3);

    std::vector<float> pix(static_cast<size_t>(kSize) * kSize * 3);
    for (size_t i = 0; i < static_cast<size_t>(kSize) * kSize; ++i) {
        for (int c = 0; c < 3; ++c) {
            const float v = resized[i * 3 + c] / 255.0f;
            pix[i * 3 + c] = (v - kMean[c]) / kStd[c];
        }
    }

    std::vector<int64_t> shape{kSize, kSize, 3};
    Ort::Value in = Ort::Value::CreateTensor<float>(im.mi, pix.data(), pix.size(), shape.data(), shape.size());
    const char* in_names[] = {"input_image"};
    const char* out_names[] = {"image_embeddings"};
    auto outs = im.enc->Run(Ort::RunOptions{nullptr}, in_names, &in, 1, out_names, 1);
    auto info = outs[0].GetTensorTypeAndShapeInfo();
    const size_t n = info.GetElementCount();
    std::vector<float> emb(n);
    std::memcpy(emb.data(), outs[0].GetTensorData<float>(), n * sizeof(float));
    return emb;
}

struct DecodeResult {
    std::vector<float> full;   // H*W logits
    std::vector<float> low;    // 256*256 logits
    float iou = 0.0f;
};

DecodeResult Decode(MobileSAM::Impl& im, const std::vector<float>& emb,
                    const std::vector<std::pair<float, float>>& pts,
                    const std::vector<float>& labels, int W, int H) {
    const size_t n = pts.size();
    std::vector<float> coords(n * 2);
    for (size_t i = 0; i < n; ++i) {
        coords[i * 2 + 0] = pts[i].first * static_cast<float>(kSize) / W;
        coords[i * 2 + 1] = pts[i].second * static_cast<float>(kSize) / H;
    }
    std::vector<float> label_data = labels;
    std::vector<float> zero_mask(static_cast<size_t>(kLow) * kLow, 0.0f);
    std::vector<float> has_mask{0.0f};
    std::vector<float> orig_size{static_cast<float>(H), static_cast<float>(W)};

    std::vector<int64_t> emb_shape{1, 256, 64, 64};
    std::vector<int64_t> coord_shape{1, static_cast<int64_t>(n), 2};
    std::vector<int64_t> label_shape{1, static_cast<int64_t>(n)};
    std::vector<int64_t> mask_shape{1, 1, kLow, kLow};
    std::vector<int64_t> has_shape{1};
    std::vector<int64_t> orig_shape{2};

    std::vector<Ort::Value> inputs;
    inputs.push_back(Ort::Value::CreateTensor<float>(im.mi, const_cast<float*>(emb.data()), emb.size(), emb_shape.data(), emb_shape.size()));
    inputs.push_back(Ort::Value::CreateTensor<float>(im.mi, coords.data(), coords.size(), coord_shape.data(), coord_shape.size()));
    inputs.push_back(Ort::Value::CreateTensor<float>(im.mi, label_data.data(), label_data.size(), label_shape.data(), label_shape.size()));
    inputs.push_back(Ort::Value::CreateTensor<float>(im.mi, zero_mask.data(), zero_mask.size(), mask_shape.data(), mask_shape.size()));
    inputs.push_back(Ort::Value::CreateTensor<float>(im.mi, has_mask.data(), has_mask.size(), has_shape.data(), has_shape.size()));
    inputs.push_back(Ort::Value::CreateTensor<float>(im.mi, orig_size.data(), orig_size.size(), orig_shape.data(), orig_shape.size()));

    const char* in_names[] = {"image_embeddings", "point_coords", "point_labels",
                              "mask_input", "has_mask_input", "orig_im_size"};
    const char* out_names[] = {"masks", "iou_predictions", "low_res_masks"};
    auto outs = im.dec->Run(Ort::RunOptions{nullptr}, in_names, inputs.data(), inputs.size(), out_names, 3);

    DecodeResult r;
    const size_t full_n = outs[0].GetTensorTypeAndShapeInfo().GetElementCount();
    r.full.resize(full_n);
    std::memcpy(r.full.data(), outs[0].GetTensorData<float>(), full_n * sizeof(float));
    r.iou = outs[1].GetTensorData<float>()[0];
    const size_t low_n = outs[2].GetTensorTypeAndShapeInfo().GetElementCount();
    r.low.resize(low_n);
    std::memcpy(r.low.data(), outs[2].GetTensorData<float>(), low_n * sizeof(float));
    return r;
}


// Refine SAM's soft mask for direct asset cutout:
// - keep the largest 4-connected foreground component
// - fill enclosed holes (background regions not reachable from the border)
// - output a hard alpha edge (1024px; engines can alpha-test / filter)
std::vector<unsigned char> RefineMask(const std::vector<float>& logits, int W, int H) {
    const size_t n = static_cast<size_t>(W) * H;
    std::vector<unsigned char> fg(n, 0);
    for (size_t i = 0; i < n; ++i) fg[i] = Sigmoid(logits[i]) > 0.5f ? 1 : 0;

    std::vector<int> label(n, -1);
    std::vector<int> stack;
    int best = -1;
    int best_count = 0;
    int cur = 0;
    for (size_t start = 0; start < n; ++start) {
        if (!fg[start] || label[start] >= 0) continue;
        label[start] = cur;
        stack.clear();
        stack.push_back(static_cast<int>(start));
        int count = 0;
        while (!stack.empty()) {
            int p = stack.back();
            stack.pop_back();
            ++count;
            const int x = p % W;
            const int y = p / W;
            if (x > 0 && fg[p - 1] && label[p - 1] < 0) { label[p - 1] = cur; stack.push_back(p - 1); }
            if (x + 1 < W && fg[p + 1] && label[p + 1] < 0) { label[p + 1] = cur; stack.push_back(p + 1); }
            if (y > 0 && fg[p - W] && label[p - W] < 0) { label[p - W] = cur; stack.push_back(p - W); }
            if (y + 1 < H && fg[p + W] && label[p + W] < 0) { label[p + W] = cur; stack.push_back(p + W); }
        }
        if (count > best_count) { best_count = count; best = cur; }
        ++cur;
    }

    std::vector<unsigned char> keep(n, 0);
    if (best >= 0) {
        for (size_t i = 0; i < n; ++i) if (label[i] == best) keep[i] = 1;
    }

    // Flood background from the border; anything unreachable is a hole.
    std::vector<unsigned char> seen(n, 0);
    stack.clear();
    auto push = [&](int x, int y) {
        if (x < 0 || x >= W || y < 0 || y >= H) return;
        const int p = y * W + x;
        if (!keep[p] && !seen[p]) { seen[p] = 1; stack.push_back(p); }
    };
    for (int x = 0; x < W; ++x) { push(x, 0); push(x, H - 1); }
    for (int y = 0; y < H; ++y) { push(0, y); push(W - 1, y); }
    while (!stack.empty()) {
        int p = stack.back();
        stack.pop_back();
        const int x = p % W;
        const int y = p / W;
        push(x - 1, y); push(x + 1, y); push(x, y - 1); push(x, y + 1);
    }
    for (size_t i = 0; i < n; ++i) if (!keep[i] && !seen[i]) keep[i] = 1;

    std::vector<unsigned char> alpha(n, 0);
    for (size_t i = 0; i < n; ++i) alpha[i] = keep[i] ? 255 : 0;
    return alpha;
}

void WriteResult(const Image& img, const std::vector<float>& logits,
                 const std::string& out_path, const std::string& mask_path, int mode) {
    const int W = img.w, H = img.h;
    if (logits.size() != static_cast<size_t>(W) * H) {
        throw std::runtime_error("unexpected mask size");
    }
    std::vector<unsigned char> alpha = RefineMask(logits, W, H);

    if (!mask_path.empty() && mode != MODE_MASK) {
        stbi_write_png(mask_path.c_str(), W, H, 1, alpha.data(), W);
    }
    if (mode == MODE_MASK) {
        stbi_write_png(out_path.c_str(), W, H, 1, alpha.data(), W);
        return;
    }
    if (mode == MODE_RGBA) {
        std::vector<unsigned char> rgba(static_cast<size_t>(W) * H * 4);
        for (size_t i = 0; i < static_cast<size_t>(W) * H; ++i) {
            rgba[i * 4 + 0] = img.rgb[i * 3 + 0];
            rgba[i * 4 + 1] = img.rgb[i * 3 + 1];
            rgba[i * 4 + 2] = img.rgb[i * 3 + 2];
            rgba[i * 4 + 3] = alpha[i];
        }
        stbi_write_png(out_path.c_str(), W, H, 4, rgba.data(), W * 4);
        return;
    }
    unsigned char bg[3] = {255, 255, 255};
    if (mode == MODE_BLACK) bg[0] = bg[1] = bg[2] = 0;
    std::vector<unsigned char> rgb(static_cast<size_t>(W) * H * 3);
    for (size_t i = 0; i < static_cast<size_t>(W) * H; ++i) {
        const float a = alpha[i] / 255.0f;
        for (int c = 0; c < 3; ++c) {
            rgb[i * 3 + c] = To8(img.rgb[i * 3 + c] / 255.0f * a + bg[c] / 255.0f * (1.0f - a));
        }
    }
    stbi_write_png(out_path.c_str(), W, H, 3, rgb.data(), W * 3);
}

}  // namespace

void MobileSAM::Segment(const std::string& in_path, const std::string& out_path,
                        const std::string& mask_path, const std::string& points_csv,
                        const std::string& labels_csv, int mode) {
    Impl& im = *impl_;
    Image img = LoadRgbWhite(in_path);
    auto emb = Encode(im, img);
    auto pts = ParsePoints(points_csv, img.w, img.h);
    auto labels = ParseLabels(labels_csv, pts.size());
    auto r = Decode(im, emb, pts, labels, img.w, img.h);
    WriteResult(img, r.full, out_path, mask_path, mode);
}

void MobileSAM::Auto(const std::string& in_path, const std::string& out_path,
                     const std::string& mask_path, int grid, float iou_thr,
                     float min_area, float max_area, int mode) {
    Impl& im = *impl_;
    Image img = LoadRgbWhite(in_path);
    auto emb = Encode(im, img);
    if (grid < 4) grid = 4;
    if (grid > 32) grid = 32;

    Candidate best;
    const float border_n = 4.0f * static_cast<float>(kLow);
    for (int gy = 0; gy < grid; ++gy) {
        for (int gx = 0; gx < grid; ++gx) {
            const float px = (gx + 0.5f) * img.w / grid;
            const float py = (gy + 0.5f) * img.h / grid;
            std::vector<std::pair<float, float>> pts{{px, py}};
            std::vector<float> labels{1.0f};
            auto r = Decode(im, emb, pts, labels, img.w, img.h);
            if (r.low.size() != static_cast<size_t>(kLow) * kLow) continue;
            if (r.iou < iou_thr) continue;

            int fg = 0, border_fg = 0;
            for (int y = 0; y < kLow; ++y) {
                for (int x = 0; x < kLow; ++x) {
                    const float v = Sigmoid(r.low[y * kLow + x]);
                    if (v > 0.5f) {
                        ++fg;
                        if (x == 0 || y == 0 || x == kLow - 1 || y == kLow - 1) ++border_fg;
                    }
                }
            }
            const float area = static_cast<float>(fg) / (kLow * kLow);
            const float border = static_cast<float>(border_fg) / border_n;
            if (area < min_area || area > max_area) continue;
            if (border > 0.5f) continue;
            if (area > best.area || (area == best.area && r.iou > best.iou)) {
                best.iou = r.iou;
                best.area = area;
                best.border = border;
                best.gx = gx;
                best.gy = gy;
                best.full_mask = std::move(r.full);
            }
        }
    }

    if (best.full_mask.empty()) {
        // Fallback: center-torso point.
        std::vector<std::pair<float, float>> pts{{img.w * 0.5f, img.h * 0.65f}};
        std::vector<float> labels{1.0f};
        auto r = Decode(im, emb, pts, labels, img.w, img.h);
        WriteResult(img, r.full, out_path, mask_path, mode);
        return;
    }
    WriteResult(img, best.full_mask, out_path, mask_path, mode);
}

}  // namespace msam
