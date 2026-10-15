import os
from huggingface_hub import snapshot_download

ROOT = "/data/models/image/diffusers"
JOBS = [
    ("Lykon/dreamshaper-8", "dreamshaper-8", None),
    ("guoyww/animatediff-motion-adapter-v1-5-2", "animatediff-motion-adapter-v1-5-2", None),
    ("lllyasviel/control_v11p_sd15_openpose", "control_v11p_sd15_openpose", None),
    ("h94/IP-Adapter", "IP-Adapter",
     ["models/ip-adapter-plus_sd15.safetensors", "models/image_encoder/*"]),
]

for repo, name, patterns in JOBS:
    d = os.path.join(ROOT, name)
    print("==>", repo, "->", d, flush=True)
    snapshot_download(repo_id=repo, local_dir=d, allow_patterns=patterns,
                      max_workers=4)
    print("done", name, flush=True)

print("ALL DONE")
