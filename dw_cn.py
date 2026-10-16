import warnings; warnings.filterwarnings("ignore")
import os, glob, ctypes, torch
import imgproc_py as P   # StaticPy 版图像处理（替代 PIL；帧也走 imgproc）
from diffusers import AnimateDiffControlNetPipeline, MotionAdapter, ControlNetModel, DDIMScheduler

def read_resized(path, w, h):
    """读图→缩放→ torch 张量 (C,H,W) float[0,1]（走 imgproc，无 PIL / 无 numpy）。"""
    im = P.img_open(path.encode())
    c = P.img_convert(im, b"RGB")
    r = P.img_resize(c, w, h, b"bilinear")
    raw = ctypes.string_at(P.img_frame_ptr(r, 0), w * h * 4)   # RGBA
    t = (torch.frombuffer(bytearray(raw), dtype=torch.uint8)
         .reshape(h, w, 4)[:, :, :3].permute(2, 0, 1).float() / 255.0)
    P.img_free(im); P.img_free(c); P.img_free(r)
    return t

_D = "/data/models/image/diffusers"
BASE = os.environ.get("BASE", f"{_D}/dreamshaper-8")
MOTION = os.environ.get("MOTION", f"{_D}/animatediff-motion-adapter-v1-5-2")
CN = os.environ.get("CN", f"{_D}/control_v11p_sd15_openpose")
IPADAPTER = os.environ.get("IPADAPTER", f"{_D}/IP-Adapter")
LORA = os.environ.get("LORA", "/data/models/image/video/walkRL_diff.safetensors")
POSES = os.environ.get("POSES") or os.path.join(
    os.path.dirname(os.path.abspath(__file__)), "poses", "walk2")
OUT = os.environ.get("OUT") or os.path.join(
    os.path.dirname(os.path.abspath(__file__)), "diffwalk_arm2_regen.gif")
REF = os.environ.get("REF") or os.path.join(
    os.path.dirname(os.path.abspath(__file__)), "ref.png")
FRAMES = int(os.environ.get("FRAMES", "16"))
W = int(os.environ.get("W", "512")); H = int(os.environ.get("H", "768"))
STEPS = int(os.environ.get("STEPS", "25")); SEED = int(os.environ.get("SEED", "42"))
CNS = float(os.environ.get("CNSCALE", "1.0"))
IP = os.environ.get("IP", "1") == "1"; IPS = float(os.environ.get("IPSCALE", "0.7"))
CFG = float(os.environ.get("CFG", "7.5"))
LORASCALE = float(os.environ.get("LORASCALE", "1.0"))
FREEINIT = os.environ.get("FREEINIT", "0") == "1"
FREE_ITERS = int(os.environ.get("FREE_ITERS", "3"))

PROMPT = os.environ.get("PROMPT",
    "a cute chibi cartoon knight, silver armor, red plume, red cape, empty hands, "
    "walking to the right, side view, full body, arms swinging back and forth naturally in sync with the legs, "
    "plain white background, thick clean outline, flat colors, smooth 2d game character animation")
NEG = os.environ.get("NEG",
    "sword, weapon, shield, broom, brush, stick, object in hand, back accessory, arms crossed, folded arms, "
    "hands on hips, stiff arms, blurry, low quality, deformed limbs, extra limbs, extra arms, static, "
    "gray background, scenery, background objects, realistic, photo, 3d render")

adapter = MotionAdapter.from_pretrained(MOTION, torch_dtype=torch.float16)
controlnet = ControlNetModel.from_pretrained(CN, torch_dtype=torch.float16)
pipe = AnimateDiffControlNetPipeline.from_pretrained(
    BASE, motion_adapter=adapter, controlnet=controlnet, torch_dtype=torch.float16)
pipe.scheduler = DDIMScheduler.from_config(
    pipe.scheduler.config, beta_schedule="linear", clip_sample=False,
    timestep_spacing="linspace", steps_offset=1)
pipe.load_lora_weights(LORA, adapter_name="walk")
pipe.set_adapters(["walk"], adapter_weights=[LORASCALE])
if IP:
    pipe.load_ip_adapter(IPADAPTER, subfolder="models",
                         weight_name="ip-adapter-plus_sd15.safetensors",
                         image_encoder_folder="models/image_encoder")
    pipe.set_ip_adapter_scale(IPS)
if FREEINIT:
    pipe.enable_free_init(num_iters=FREE_ITERS, use_fast_sampling=True)
pipe.enable_model_cpu_offload()

# POSE_FLIP：把「输入骨架」水平翻转后再喂 ControlNet。
# 模型侧视恒把角色渲染成朝左，但腿的迈步方向照抄骨架 → 不翻骨会得到「太空步」
# （脸朝左、腿朝右迈）。翻转骨架使腿与脸同向 = 正常前走。（详见 WALK_ANIM.md）
POSE_FLIP = os.environ.get("POSE_FLIP", "0") == "1"
all_poses = sorted(glob.glob(os.path.join(POSES, "*.png")))
n = len(all_poses)
cond = []
for i in range(FRAMES):
    idx = i * n // FRAMES
    im = read_resized(all_poses[idx], W, H)
    if POSE_FLIP:
        im = torch.flip(im, dims=[2])   # 水平镜像（W 维）
    cond.append(im)

ip_img = read_resized(REF, W, H) if IP else None

res = pipe(
    prompt=PROMPT, negative_prompt=NEG,
    num_frames=FRAMES, conditioning_frames=cond, controlnet_conditioning_scale=CNS,
    ip_adapter_image=ip_img,
    height=H, width=W,
    guidance_scale=CFG, num_inference_steps=STEPS,
    generator=torch.Generator("cpu").manual_seed(SEED),
    output_type="pt",     # 直接出 torch 张量（避免 PIL）
)
fr = res.frames
if isinstance(fr, (list, tuple)):
    fr = fr[0]
while fr.dim() > 4:
    fr = fr[0]
fr = (fr.clamp(0, 1) * 255).to(torch.uint8)                       # (F,C,H,W)
frames_bytes = [bytes(fr[i].permute(1, 2, 0).contiguous().view(-1).tolist())
                for i in range(fr.shape[0])]

# FLIPOUT：输出水平镜像（走 imgproc）。先 POSE_FLIP 修好步态，再 FLIPOUT 换朝向。
P.build_gif_bytes(frames_bytes, W, H, OUT,
                  duration_ms=int(1000 / int(os.environ.get("FPS", "8"))),
                  flip=(os.environ.get("FLIPOUT", "0") == "1"))
print("saved", OUT, "frames", len(frames_bytes))
