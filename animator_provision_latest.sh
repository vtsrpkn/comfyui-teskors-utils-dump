#!/bin/bash
set -e

# === 1. ПОДГОТОВКА ОКРУЖЕНИЯ ===
if [ -f "/venv/main/bin/activate" ]; then
    source /venv/main/bin/activate
elif [ -f "/opt/venv/bin/activate" ]; then
    source /opt/venv/bin/activate
fi

WORKSPACE=${WORKSPACE:-/workspace}
COMFYUI_DIR="${WORKSPACE}/ComfyUI"

echo "Запуск установки"



# === СПИСКИ ПАКЕТОВ И МОДЕЛЕЙ ===
NODES=(
    "https://github.com/ltdrdata/ComfyUI-Manager"
    "https://github.com/kijai/ComfyUI-WanVideoWrapper"
    "https://github.com/ltdrdata/ComfyUI-Impact-Pack"
    "https://github.com/numz/ComfyUI-SeedVR2_VideoUpscaler"
    "https://github.com/chflame163/ComfyUI_LayerStyle"
    "https://github.com/rgthree/rgthree-comfy"
    "https://github.com/yolain/ComfyUI-Easy-Use"
    "https://github.com/kijai/ComfyUI-KJNodes"
    "https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite"
    "https://github.com/kijai/ComfyUI-segment-anything-2"
    "https://github.com/cubiq/ComfyUI_essentials"
    "https://github.com/fq393/ComfyUI-ZMG-Nodes"
    "https://github.com/kijai/ComfyUI-WanAnimatePreprocess"
    "https://github.com/jnxmx/ComfyUI_HuggingFace_Downloader"
    "https://github.com/plugcrypt/CRT-Nodes"
    "https://github.com/pythongosssss/ComfyUI-Custom-Scripts"
    "https://github.com/ClownsharkBatwing/RES4LYF"
    "https://github.com/chrisgoringe/cg-use-everywhere"
    "https://github.com/ltdrdata/ComfyUI-Impact-Subpack"
    "https://github.com/Smirnov75/ComfyUI-mxToolkit"
    "https://github.com/crystian/ComfyUI-Crystools"
    "https://github.com/teskor-hub/comfyui-teskors-utils.git"
)
WRAPER=("https://raw.githubusercontent.com/gaziko/valentin/refs/heads/main/animator.json")
CLIP_MODELS=("https://huggingface.co/wdsfdsdf/OFMHUB/resolve/main/klip_vision.safetensors")
CLIPS=("https://huggingface.co/Comfy-Org/Wan_2.1_ComfyUI_repackaged/resolve/main/split_files/clip_vision/clip_vision_h.safetensors")
TEXT_ENCODERS=("https://huggingface.co/wdsfdsdf/OFMHUB/resolve/main/text_enc.safetensors")
UNET_MODELS=("https://huggingface.co/Comfy-Org/z_image_turbo/resolve/main/split_files/diffusion_models/z_image_turbo_bf16.safetensors")
VAE_MODELS=("https://huggingface.co/wdsfdsdf/OFMHUB/resolve/main/vae.safetensors")
DETECTION_MODELS=("https://huggingface.co/Wan-AI/Wan2.2-Animate-14B/resolve/main/process_checkpoint/det/yolov10m.onnx"
"https://huggingface.co/Kijai/vitpose_comfy/resolve/main/onnx/vitpose_h_wholebody_data.bin"
"https://huggingface.co/Kijai/vitpose_comfy/resolve/main/onnx/vitpose_h_wholebody_model.onnx")
LORAS=("https://huggingface.co/wdsfdsdf/OFMHUB/resolve/main/WanFun.reworked.safetensors"
"https://huggingface.co/wdsfdsdf/OFMHUB/resolve/main/light.safetensors"
"https://huggingface.co/wdsfdsdf/OFMHUB/resolve/main/light.safetensors"
"https://huggingface.co/wdsfdsdf/OFMHUB/resolve/main/WanPusa.safetensors"
"https://huggingface.co/wdsfdsdf/OFMHUB/resolve/main/wan.reworked.safetensors"
"https://huggingface.co/Kijai/WanVideo_comfy/resolve/main/Wan21_Uni3C_controlnet_fp16.safetensors")
CLIP_VISION=("https://huggingface.co/wdsfdsdf/OFMHUB/resolve/main/klip_vision.safetensors")
DEFFUSION=("https://huggingface.co/wdsfdsdf/OFMHUB/resolve/main/WanModel.safetensors")
CONTROLNET=("https://huggingface.co/Kijai/WanVideo_comfy/resolve/main/Wan21_Uni3C_controlnet_fp16.safetensors")

### ─────────────────────────────────────────────
### ФУНКЦИИ УСТАНОВКИ
### ─────────────────────────────────────────────

 function provisioning_start() {
    provisioning_clone_comfyui
    provisioning_install_base_reqs
    provisioning_get_nodes

    # ВАЖНО: Качаем wraperx.json прямо в папку web, чтобы кнопка могла его мгновенно получить
    provisioning_get_files "${COMFYUI_DIR}/web"                       "${WRAPER[@]}"
	provisioning_get_files "${COMFYUI_DIR}/user/default/workflows"    "${WRAPER[@]}"
    provisioning_get_files "${COMFYUI_DIR}/models/clip"               "${CLIP_MODELS[@]}"
    provisioning_get_files "${COMFYUI_DIR}/models/clip_vision"        "${CLIP_VISION[@]}"
    provisioning_get_files "${COMFYUI_DIR}/models/text_encoders"      "${TEXT_ENCODERS[@]}"
    provisioning_get_files "${COMFYUI_DIR}/models/vae"                "${VAE_MODELS[@]}"
    provisioning_get_files "${COMFYUI_DIR}/models/diffusion_models"   "${DIFFUSION_MODELS[@]}"
    provisioning_get_files "${COMFYUI_DIR}/models/detection"          "${DETECTION_MODELS[@]}"
    provisioning_get_files "${COMFYUI_DIR}/models/loras"              "${LORAS[@]}"
    provisioning_get_files "${COMFYUI_DIR}/models/diffusion_models"   "${DEFFUSION[@]}"
    provisioning_get_files "${COMFYUI_DIR}/models/controlnet"   "${CONTROLNET[@]}"

    echo "Газик настроил → Provisioning complete. Image will now start natively."
}

# Клонируем тихо (-q)
function provisioning_clone_comfyui() {
    if [[ ! -d "${COMFYUI_DIR}" ]]; then
        git clone -q https://github.com/comfyanonymous/ComfyUI.git "${COMFYUI_DIR}" > /dev/null 2>&1
    fi
    cd "${COMFYUI_DIR}"
}

# Ставим зависимости тихо (-q)
function provisioning_install_base_reqs() {
    if [[ -f requirements.txt ]]; then
        pip install -q --no-cache-dir -r requirements.txt > /dev/null 2>&1 || true
    fi
}

# Клонируем кастомные ноды тихо (-q)
function provisioning_get_nodes() {
    mkdir -p "${COMFYUI_DIR}/custom_nodes"
    cd "${COMFYUI_DIR}/custom_nodes"

    for repo in "${NODES[@]}"; do
        dir="${repo##*/}"
        path="./${dir}"

        if [[ -d "$path" ]]; then
            (cd "$path" && git pull -q --ff-only > /dev/null 2>&1 || { git fetch -q > /dev/null 2>&1 && git reset -q --hard origin/main > /dev/null 2>&1; })
        else
            git clone -q "$repo" "$path" --recursive > /dev/null 2>&1 || true
        fi

        requirements="${path}/requirements.txt"
        if [[ -f "$requirements" ]]; then
            pip install -q --no-cache-dir -r "$requirements" > /dev/null 2>&1 || true
        fi
    done
}

# Качаем файлы тихо (-q)
function provisioning_get_files() {
    if [[ $# -lt 2 ]]; then return; fi
    local dir="$1"
    shift
    local files=("$@")

    mkdir -p "$dir"

    for url in "${files[@]}"; do
        if [[ -n "$HF_TOKEN" && "$url" =~ huggingface\.co ]]; then
            wget --header="Authorization: Bearer $HF_TOKEN" -q -nc --content-disposition -P "$dir" "$url" || true
        elif [[ -n "$CIVITAI_TOKEN" && "$url" =~ civitai\.com ]]; then
            wget --header="Authorization: Bearer $CIVITAI_TOKEN" -q -nc --content-disposition -P "$dir" "$url" || true
        else
            wget -q -nc --content-disposition -P "$dir" "$url" || true
        fi
    done
}

# Запуск provisioning
if [[ ! -f /.noprovisioning ]]; then
    provisioning_start
fi

echo "Установка завершена"
