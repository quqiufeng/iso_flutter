import warnings; warnings.filterwarnings("ignore")
import os, glob, torch
from PIL import Image
from diffusers import AnimateDiffControlNetPipeline, MotionAdapter, ControlNetModel, DDIMScheduler
from diffusers.utils import export_to_gif

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

all_poses = sorted(glob.glob(os.path.join(POSES, "*.png")))
n = len(all_poses)
cond = []
for i in range(FRAMES):
    idx = i * n // FRAMES
    cond.append(Image.open(all_poses[idx]).convert("RGB").resize((W, H)))

ip_img = Image.open(REF).convert("RGB").resize((W, H)) if IP else None

frames = pipe(
    prompt=PROMPT, negative_prompt=NEG,
    num_frames=FRAMES, conditioning_frames=cond, controlnet_conditioning_scale=CNS,
    ip_adapter_image=ip_img,
    guidance_scale=CFG, num_inference_steps=STEPS,
    generator=torch.Generator("cpu").manual_seed(SEED),
).frames[0]

export_to_gif(frames, OUT, fps=int(os.environ.get("FPS", "8")))
print("saved", OUT, "frames", len(frames))
