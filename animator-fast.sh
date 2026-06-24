#!/bin/bash
set -e
source /venv/main/bin/activate

WORKSPACE=${WORKSPACE:-/workspace}
COMFYUI_DIR="${WORKSPACE}/ComfyUI"
HF_CACHE_DIR="${HF_CACHE_DIR:-${WORKSPACE}/.cache/huggingface}"

echo "=== Starting ComfyUI provisioning (x-mode) ==="

APT_PACKAGES=()           # Optional APT packages to install during provisioning.
PIP_PACKAGES=("huggingface_hub" "hf_xet")           # Optional global pip packages beyond requirements files.

NODES=(
    "https://github.com/kijai/ComfyUI-WanVideoWrapper"
    "https://github.com/chflame163/ComfyUI_LayerStyle"
    "https://github.com/yolain/ComfyUI-Easy-Use"
    "https://github.com/kijai/ComfyUI-KJNodes"
    "https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite"
    "https://github.com/kijai/ComfyUI-segment-anything-2"
    "https://github.com/cubiq/ComfyUI_essentials"
    "https://github.com/fq393/ComfyUI-ZMG-Nodes"
    "https://github.com/kijai/ComfyUI-WanAnimatePreprocess"
    "https://github.com/rgthree/rgthree-comfy"
    "https://github.com/jnxmx/ComfyUI_HuggingFace_Downloader"
    "https://github.com/teskor-hub/NEW-UTILS.git"
    "https://github.com/teskor-hub/comfyui-teskors-utils.git"
)

# Required model and checkpoint files.
CLIP_MODELS=(
    "https://huggingface.co/wdsfdsdf/OFMHUB/resolve/main/klip_vision.safetensors"
)
CLIPS=(
"https://huggingface.co/Comfy-Org/Wan_2.1_ComfyUI_repackaged/resolve/main/split_files/clip_vision/clip_vision_h.safetensors"
)

TEXT_ENCODERS=(
"https://huggingface.co/wdsfdsdf/OFMHUB/resolve/main/text_enc.safetensors"
)

UNET_MODELS=(
    "https://huggingface.co/Comfy-Org/z_image_turbo/resolve/main/split_files/diffusion_models/z_image_turbo_bf16.safetensors"
)

VAE_MODELS=(
    "https://huggingface.co/wdsfdsdf/OFMHUB/resolve/main/vae.safetensors"
)

DETECTION_MODELS=(
"https://huggingface.co/Wan-AI/Wan2.2-Animate-14B/resolve/main/process_checkpoint/det/yolov10m.onnx"
"https://huggingface.co/Kijai/vitpose_comfy/resolve/main/onnx/vitpose_h_wholebody_data.bin"
"https://huggingface.co/Kijai/vitpose_comfy/resolve/main/onnx/vitpose_h_wholebody_model.onnx"
)

LORAS=(
"https://huggingface.co/wdsfdsdf/OFMHUB/resolve/main/WanFun.reworked.safetensors"
"https://huggingface.co/wdsfdsdf/OFMHUB/resolve/main/light.safetensors"
"https://huggingface.co/wdsfdsdf/OFMHUB/resolve/main/light.safetensors"
"https://huggingface.co/wdsfdsdf/OFMHUB/resolve/main/WanPusa.safetensors"
"https://huggingface.co/wdsfdsdf/OFMHUB/resolve/main/wan.reworked.safetensors"
)

CLIP_VISION=(
"https://huggingface.co/wdsfdsdf/OFMHUB/resolve/main/klip_vision.safetensors"
)

DEFFUSION=(
"https://huggingface.co/wdsfdsdf/OFMHUB/resolve/main/WanModel.safetensors"

)
### ------------------------------------------------------------
### Provisioning workflow. Edit with care.
### ------------------------------------------------------------

function provisioning_start() {
    echo ""
    echo "##############################################"
    echo "# ComfyUI provisioning                       #"
    echo "# Custom node and model setup                #"
    echo "# Environment preparation                    #"
    echo "##############################################"
    echo ""

    provisioning_get_apt_packages
    provisioning_clone_comfyui
    provisioning_install_base_reqs
    provisioning_get_nodes
    provisioning_get_pip_packages

    provisioning_get_files "${COMFYUI_DIR}/models/clip"               "${CLIP_MODELS[@]}"
    provisioning_get_files "${COMFYUI_DIR}/models/clip_vision"        "${CLIP_VISION[@]}"
    provisioning_get_files "${COMFYUI_DIR}/models/text_encoders"      "${TEXT_ENCODERS[@]}"
    provisioning_get_files "${COMFYUI_DIR}/models/vae"                "${VAE_MODELS[@]}"
    provisioning_get_files "${COMFYUI_DIR}/models/diffusion_models"   "${DIFFUSION_MODELS[@]}"

    provisioning_get_files "${COMFYUI_DIR}/models/detection"   "${DETECTION_MODELS[@]}"
    provisioning_get_files "${COMFYUI_DIR}/models/loras"   "${LORAS[@]}"
    provisioning_get_files "${COMFYUI_DIR}/models/diffusion_models"     "${DEFFUSION[@]}"

    echo ""
    echo "Provisioning complete. Starting ComfyUI..."
    echo ""
}

function provisioning_clone_comfyui() {
    if [[ ! -d "${COMFYUI_DIR}" ]]; then
        echo "Cloning ComfyUI..."
        git clone https://github.com/comfyanonymous/ComfyUI.git "${COMFYUI_DIR}"
    fi
    cd "${COMFYUI_DIR}"
}

function provisioning_install_base_reqs() {
    if [[ -f requirements.txt ]]; then
        echo "Installing base requirements..."
        pip install --no-cache-dir -r requirements.txt
    fi
}

function provisioning_get_apt_packages() {
    if [[ ${#APT_PACKAGES[@]} -gt 0 ]]; then
        echo "Installing APT packages..."
        sudo apt update && sudo apt install -y "${APT_PACKAGES[@]}"
    fi
}

function provisioning_get_pip_packages() {
    if [[ ${#PIP_PACKAGES[@]} -gt 0 ]]; then
        echo "Installing additional pip packages..."
        pip install --no-cache-dir "${PIP_PACKAGES[@]}"
    fi
}

function provisioning_get_nodes() {
    mkdir -p "${COMFYUI_DIR}/custom_nodes"
    cd "${COMFYUI_DIR}/custom_nodes"

    for repo in "${NODES[@]}"; do
        dir="${repo##*/}"
        path="./${dir}"

        if [[ -d "$path" ]]; then
            echo "Updating node: $dir"
            (cd "$path" && git pull --ff-only 2>/dev/null || { git fetch && git reset --hard origin/main; })
        else
            echo "Cloning node: $dir"
            git clone "$repo" "$path" --recursive || echo " [!] Clone failed: $repo"
        fi

        requirements="${path}/requirements.txt"
        if [[ -f "$requirements" ]]; then
            echo "Installing deps for $dir..."
            pip install --no-cache-dir -r "$requirements" || echo " [!] pip requirements failed for $dir"
        fi
    done
}

function provisioning_get_files() {
    if [[ $# -lt 2 ]]; then return; fi
    local dir="$1"
    shift
    local files=("$@")

    mkdir -p "$dir"
    echo "Downloading ${#files[@]} file(s) to $dir..."

    for url in "${files[@]}"; do
        echo "→ $url"
        local auth_header=""
        if [[ -n "$HF_TOKEN" && "$url" =~ huggingface\.co ]]; then
            auth_header="--header=Authorization: Bearer $HF_TOKEN"
        elif [[ -n "$CIVITAI_TOKEN" && "$url" =~ civitai\.com ]]; then
            auth_header="--header=Authorization: Bearer $CIVITAI_TOKEN"
        fi

        if [[ "$url" =~ huggingface\.co ]]; then
            provisioning_get_hf_file "$dir" "$url" || wget $auth_header -nc --content-disposition --show-progress -e dotbytes=4M -P "$dir" "$url" || echo " [!] Download failed: $url"
        else
            wget $auth_header -nc --content-disposition --show-progress -e dotbytes=4M -P "$dir" "$url" || echo " [!] Download failed: $url"
        fi
        echo ""
    done
}

function provisioning_get_hf_file() {
    local dir="$1"
    local url="$2"
    local path="${url#https://huggingface.co/}"
    local owner="${path%%/*}"
    local rest="${path#*/}"
    local repo="${rest%%/*}"
    rest="${rest#*/}"

    if [[ "$path" == "$url" || "$rest" != resolve/* ]]; then
        echo "unsupported Hugging Face URL: $url"
        return 1
    fi

    local after_resolve="${rest#resolve/}"
    local revision="${after_resolve%%/*}"
    local filename="${after_resolve#*/}"
    local repo_id="${owner}/${repo}"
    local target="${dir}/${filename##*/}"

    if [[ -s "$target" ]]; then
        echo "Already exists: $target"
        return 0
    fi

    local hf_args=(
        download "$repo_id" "$filename"
        --revision "$revision"
        --cache-dir "$HF_CACHE_DIR"
        --max-workers "$(provisioning_hf_max_workers)"
    )
    if [[ -n "$HF_TOKEN" ]]; then
        hf_args+=(--token "$HF_TOKEN")
    fi

    local output
    if provisioning_has_high_memory; then
        output=$(HF_XET_HIGH_PERFORMANCE=1 hf "${hf_args[@]}")
    else
        output=$(hf "${hf_args[@]}")
    fi

    local downloaded
    downloaded="$(printf '%s\n' "$output" | tail -n 1)"
    if [[ ! -f "$downloaded" ]]; then
        printf '%s\n' "$output"
        echo "hf download did not return a file path for $url"
        return 1
    fi

    mkdir -p "$dir"
    ln "$downloaded" "$target" 2>/dev/null || cp -p "$downloaded" "$target"
    echo "Downloaded: $target"
}

function provisioning_has_high_memory() {
    awk '/MemTotal:/ { exit !($2 > 67108864) }' /proc/meminfo
}

function provisioning_hf_max_workers() {
    if provisioning_has_high_memory; then
        echo "${HF_DOWNLOAD_MAX_WORKERS:-32}"
    else
        echo "${HF_DOWNLOAD_MAX_WORKERS:-8}"
    fi
}

function apply_node_20_fix() {
    local settings_path="${COMFYUI_DIR}/user/default/comfy.settings.json"

    python - "$settings_path" <<'PY'
import json
import sys
from pathlib import Path

settings_path = Path(sys.argv[1])
settings_path.parent.mkdir(parents=True, exist_ok=True)

settings = {}
if settings_path.exists():
    try:
        loaded = json.loads(settings_path.read_text())
        if isinstance(loaded, dict):
            settings = loaded
    except json.JSONDecodeError:
        settings = {}

settings["Comfy.VueNodes.Enabled"] = False
settings_path.write_text(json.dumps(settings, indent=2, sort_keys=True) + "\n")
PY
}

# Run provisioning unless it is disabled.
if [[ ! -f /.noprovisioning ]]; then
    provisioning_start
fi

apply_node_20_fix

# Start ComfyUI.
echo "=== Starting ComfyUI ==="
cd "${COMFYUI_DIR}"
python main.py --listen 0.0.0.0 --port 8188
