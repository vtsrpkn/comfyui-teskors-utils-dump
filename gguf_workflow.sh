#!/bin/bash
set -euo pipefail

if [[ -f /venv/main/bin/activate ]]; then
    # RunPod / container setup.
    source /venv/main/bin/activate
fi

WORKSPACE=${WORKSPACE:-/workspace}
COMFYUI_DIR="${WORKSPACE}/ComfyUI"

echo "=== ComfyUI запускает (LTX2 GGUF workflow) ==="

APT_PACKAGES=(
    "ffmpeg"
)
PIP_PACKAGES=()

NODES=(
    "https://github.com/city96/ComfyUI-GGUF"
    "https://github.com/kijai/ComfyUI-KJNodes"
    "https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite"
    "https://github.com/rgthree/rgthree-comfy"
    "https://github.com/teskor-hub/comfyui-teskors-utils.git"
)

UNET_MODELS=(
    "https://huggingface.co/unsloth/LTX-2-GGUF/resolve/main/ltx-2-19b-dev-Q6_K.gguf"
)

TEXT_ENCODERS=(
    "https://huggingface.co/Comfy-Org/ltx-2/resolve/main/split_files/text_encoders/gemma_3_12B_it_fp8_scaled.safetensors"
    "https://huggingface.co/Kijai/LTXV2_comfy/resolve/main/text_encoders/ltx-2-19b-embeddings_connector_distill_bf16.safetensors"
)

VAE_MODELS=(
    "https://huggingface.co/Kijai/LTXV2_comfy/resolve/main/VAE/LTX2_video_vae_bf16.safetensors"
    "https://huggingface.co/Kijai/LTXV2_comfy/resolve/main/VAE/LTX2_audio_vae_bf16.safetensors"
)

LATENT_UPSCALE_MODELS=(
    "https://huggingface.co/Lightricks/LTX-2/resolve/main/ltx-2-spatial-upscaler-x2-1.0.safetensors"
)

LORAS=(
    "https://huggingface.co/Kijai/LTXV2_comfy/resolve/main/loras/ltx-2-19b-distilled-lora_resized_dynamic_fro09_avg_rank_175_fp8.safetensors"
)

function provisioning_start() {
    echo ""
    echo "##############################################"
    echo "# provisioning for LTX2 GGUF workflow        #"
    echo "# models + custom nodes for first/last frame #"
    echo "##############################################"
    echo ""

    provisioning_get_apt_packages
    provisioning_clone_comfyui
    provisioning_install_base_reqs
    provisioning_get_nodes
    provisioning_get_pip_packages

    provisioning_get_files "${COMFYUI_DIR}/models/unet" "${UNET_MODELS[@]}"
    provisioning_get_files "${COMFYUI_DIR}/models/text_encoders" "${TEXT_ENCODERS[@]}"
    provisioning_get_files "${COMFYUI_DIR}/models/vae" "${VAE_MODELS[@]}"
    provisioning_get_files "${COMFYUI_DIR}/models/latent_upscale_models" "${LATENT_UPSCALE_MODELS[@]}"
    provisioning_get_files "${COMFYUI_DIR}/models/loras/ltx2" "${LORAS[@]}"

    echo ""
    echo "LTX2 GGUF workflow готов -> Starting ComfyUI..."
    echo ""
}

function provisioning_clone_comfyui() {
    if [[ ! -d "${COMFYUI_DIR}" ]]; then
        echo "Клонируем ComfyUI..."
        git clone https://github.com/comfyanonymous/ComfyUI.git "${COMFYUI_DIR}"
    fi
    cd "${COMFYUI_DIR}"
}

function provisioning_install_base_reqs() {
    if [[ -f "${COMFYUI_DIR}/requirements.txt" ]]; then
        echo "Устанавливаем base requirements..."
        pip install --no-cache-dir -r "${COMFYUI_DIR}/requirements.txt"
    fi
}

function provisioning_get_apt_packages() {
    if [[ ${#APT_PACKAGES[@]} -gt 0 ]]; then
        echo "Устанавливаем apt packages..."
        sudo apt update
        sudo apt install -y "${APT_PACKAGES[@]}"
    fi
}

function provisioning_get_pip_packages() {
    if [[ ${#PIP_PACKAGES[@]} -gt 0 ]]; then
        echo "Устанавливаем extra pip packages..."
        pip install --no-cache-dir "${PIP_PACKAGES[@]}"
    fi
}

function provisioning_get_nodes() {
    mkdir -p "${COMFYUI_DIR}/custom_nodes"
    cd "${COMFYUI_DIR}/custom_nodes"

    for repo in "${NODES[@]}"; do
        local dir
        dir="$(basename "${repo}")"
        dir="${dir%.git}"
        local path="./${dir}"

        if [[ -d "${path}/.git" ]]; then
            echo "Updating node: ${dir}"
            (
                cd "${path}"
                git pull --ff-only || echo " [!] Could not fast-forward ${dir}, keeping current checkout"
            )
        elif [[ -d "${path}" ]]; then
            echo "Node dir exists, skipping clone: ${dir}"
        else
            echo "Cloning node: ${dir}"
            git clone --recursive "${repo}" "${path}" || echo " [!] Clone failed: ${repo}"
        fi

        local requirements="${path}/requirements.txt"
        if [[ -f "${requirements}" ]]; then
            echo "Installing deps for ${dir}..."
            pip install --no-cache-dir -r "${requirements}" || echo " [!] pip requirements failed for ${dir}"
        fi
    done
}

function provisioning_get_files() {
    if [[ $# -lt 2 ]]; then
        return
    fi

    local dir="$1"
    shift
    local files=("$@")

    mkdir -p "${dir}"
    echo "Скачивание ${#files[@]} file(s) -> ${dir}..."

    for url in "${files[@]}"; do
        echo "-> ${url}"

        local wget_args=(
            -nc
            --content-disposition
            --show-progress
            -e
            dotbytes=4M
            -P
            "${dir}"
        )

        if [[ -n "${HF_TOKEN:-}" && "${url}" =~ huggingface\.co ]]; then
            wget_args+=(--header="Authorization: Bearer ${HF_TOKEN}")
        elif [[ -n "${CIVITAI_TOKEN:-}" && "${url}" =~ civitai\.com ]]; then
            wget_args+=(--header="Authorization: Bearer ${CIVITAI_TOKEN}")
        fi

        wget "${wget_args[@]}" "${url}" || echo " [!] Download failed: ${url}"
        echo ""
    done
}

if [[ ! -f /.noprovisioning ]]; then
    provisioning_start
fi

echo "=== Запускаем ComfyUI ==="
cd "${COMFYUI_DIR}"
python main.py --listen 0.0.0.0 --port 8188
