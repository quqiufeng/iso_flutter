#pragma once

#include <memory>
#include <string>

namespace msam {

// Output background handling, aligned with birefnet's modes where useful.
enum Mode {
    MODE_RGBA = 0,     // transparent RGBA
    MODE_WHITE = 1,    // RGB composite on white
    MODE_BLACK = 2,    // RGB composite on black
    MODE_MASK = 3,     // grayscale alpha matte
};

class MobileSAM {
  public:
    struct Impl;

    MobileSAM(const std::string& encoder_path, const std::string& decoder_path, bool use_cuda);
    ~MobileSAM();
    MobileSAM(const MobileSAM&) = delete;
    MobileSAM& operator=(const MobileSAM&) = delete;

    // points_csv: "x,y;x,y" in original pixel coordinates (empty -> center point).
    // labels_csv: "1;0"; empty -> all positive.
    void Segment(const std::string& in_path, const std::string& out_path,
                 const std::string& mask_path, const std::string& points_csv,
                 const std::string& labels_csv, int mode);

    // Automatic: grid points, filter by IoU/area/border, pick largest valid subject.
    void Auto(const std::string& in_path, const std::string& out_path,
              const std::string& mask_path, int grid, float iou_thr,
              float min_area, float max_area, int mode);

    const std::string& provider() const;

  private:
    std::unique_ptr<Impl> impl_;
};

}  // namespace msam
