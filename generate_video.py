"""Video generation using Wan 2.1 on Apple Silicon (MPS)
Memory-efficient: loads model on demand, unloads after generation"""
import torch, sys, time, os, gc

def generate(prompt, output_path="output.mp4", num_frames=17, height=480, width=832, steps=20):
    from diffusers import WanPipeline, AutoencoderKLWan
    from diffusers.utils import export_to_video

    device = "mps" if torch.backends.mps.is_available() else "cpu"
    print(f"Device: {device}")
    print(f"Prompt: {prompt}")
    print(f"Frames: {num_frames}, Size: {width}x{height}, Steps: {steps}")

    model_id = "Wan-AI/Wan2.1-T2V-1.3B-Diffusers"
    print(f"Loading {model_id}...")

    vae = AutoencoderKLWan.from_pretrained(
        model_id, subfolder="vae", torch_dtype=torch.float32
    )
    pipe = WanPipeline.from_pretrained(
        model_id, vae=vae, torch_dtype=torch.float32
    )
    pipe.to(device)
    pipe.enable_attention_slicing()

    print("Generating...")
    t0 = time.time()

    output = pipe(
        prompt=prompt,
        num_frames=num_frames,
        height=height,
        width=width,
        num_inference_steps=steps,
        guidance_scale=5.0,
    ).frames[0]

    elapsed = time.time() - t0
    print(f"Generated in {elapsed:.1f}s ({elapsed/num_frames:.1f}s/frame)")

    os.makedirs(os.path.dirname(output_path) if os.path.dirname(output_path) else ".", exist_ok=True)
    export_to_video(output, output_path, fps=8)
    print(f"Saved: {output_path}")

    # Free memory
    del pipe, vae, output
    gc.collect()
    if device == "mps":
        torch.mps.empty_cache()
    print("Memory released")

if __name__ == "__main__":
    prompt = sys.argv[1] if len(sys.argv) > 1 else "A cat walking on a beach at sunset"
    output = sys.argv[2] if len(sys.argv) > 2 else f"generated/video_{int(time.time())}.mp4"
    generate(prompt, output)
