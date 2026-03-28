#!/bin/bash
set -euo pipefail

# Wan 2.2 - SVI 2.0 Pro provisioning
# Собрано по workflow:
# - Wan 2.2 high/low noise fp16
# - umt5_xxl_fp16 text encoder
# - wan2.1 vae
# - SVI Pro high/low LoRA
# - LightX2V rank128 LoRA
# - custom nodes: Easy Use, KJNodes, VideoHelperSuite, SuperNodes, Use Everywhere

if [[ -f "/venv/main/bin/activate" ]]; then
    # shellcheck disable=SC1091
    source /venv/main/bin/activate
elif [[ -f "/opt/venv/bin/activate" ]]; then
    # shellcheck disable=SC1091
    source /opt/venv/bin/activate
fi

WORKSPACE="${WORKSPACE:-/workspace}"
COMFYUI_DIR="${WORKSPACE}/ComfyUI"

echo "Запуск установки Wan 2.2 - SVI 2.0 Pro"

NODES=(
    "https://github.com/yolain/ComfyUI-Easy-Use"
    "https://github.com/kijai/ComfyUI-KJNodes"
    "https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite"
    "https://github.com/sonnybox/ComfyUI-SuperNodes"
    "https://github.com/chrisgoringe/cg-use-everywhere"
)

MODEL_FILES=(
    "https://huggingface.co/Comfy-Org/Wan_2.2_ComfyUI_Repackaged/resolve/main/split_files/diffusion_models/wan2.2_i2v_high_noise_14B_fp16.safetensors|models/diffusion_models/wan/wan2.2_i2v_high_noise_14B_fp16.safetensors"
    "https://huggingface.co/Comfy-Org/Wan_2.2_ComfyUI_Repackaged/resolve/main/split_files/diffusion_models/wan2.2_i2v_low_noise_14B_fp16.safetensors|models/diffusion_models/wan/wan2.2_i2v_low_noise_14B_fp16.safetensors"
    "https://huggingface.co/Comfy-Org/Wan_2.1_ComfyUI_repackaged/resolve/main/split_files/text_encoders/umt5_xxl_fp16.safetensors|models/text_encoders/umt5_xxl_fp16.safetensors"
    "https://huggingface.co/Comfy-Org/Wan_2.2_ComfyUI_Repackaged/resolve/main/split_files/vae/wan_2.1_vae.safetensors|models/vae/wan2.1-vae.safetensors"
    "https://huggingface.co/Kijai/WanVideo_comfy/resolve/main/LoRAs/Stable-Video-Infinity/v2.0/SVI_v2_PRO_Wan2.2-I2V-A14B_HIGH_lora_rank_128_fp16.safetensors|models/loras/svi/SVI_v2_PRO_Wan2.2-I2V-A14B_HIGH_lora_rank_128_fp16.safetensors"
    "https://huggingface.co/Kijai/WanVideo_comfy/resolve/main/LoRAs/Stable-Video-Infinity/v2.0/SVI_v2_PRO_Wan2.2-I2V-A14B_LOW_lora_rank_128_fp16.safetensors|models/loras/svi/SVI_v2_PRO_Wan2.2-I2V-A14B_LOW_lora_rank_128_fp16.safetensors"
    "https://huggingface.co/Kijai/WanVideo_comfy/resolve/main/Lightx2v/lightx2v_I2V_14B_480p_cfg_step_distill_rank128_bf16.safetensors|models/loras/wan/lightx2v_I2V_14B_480p_cfg_step_distill_rank128_bf16.safetensors"
)

provisioning_start() {
    provisioning_clone_comfyui
    provisioning_install_base_reqs
    provisioning_get_nodes
    provisioning_get_model_files

    echo "Provisioning complete. Wan 2.2 - SVI 2.0 Pro готов к запуску."
}

provisioning_clone_comfyui() {
    if [[ ! -d "${COMFYUI_DIR}" ]]; then
        git clone -q https://github.com/comfyanonymous/ComfyUI.git "${COMFYUI_DIR}" > /dev/null 2>&1
    fi

    cd "${COMFYUI_DIR}"
}

provisioning_install_base_reqs() {
    if [[ -f "${COMFYUI_DIR}/requirements.txt" ]]; then
        pip install -q --no-cache-dir -r "${COMFYUI_DIR}/requirements.txt" > /dev/null 2>&1 || true
    fi
}

provisioning_get_nodes() {
    mkdir -p "${COMFYUI_DIR}/custom_nodes"
    cd "${COMFYUI_DIR}/custom_nodes"

    for repo in "${NODES[@]}"; do
        local dir path requirements
        dir="$(basename "${repo}" .git)"
        path="./${dir}"

        if [[ -d "${path}/.git" ]]; then
            (cd "${path}" && git pull -q --ff-only > /dev/null 2>&1 || true)
        else
            git clone -q --recursive "${repo}" "${path}" > /dev/null 2>&1 || true
        fi

        requirements="${path}/requirements.txt"
        if [[ -f "${requirements}" ]]; then
            pip install -q --no-cache-dir -r "${requirements}" > /dev/null 2>&1 || true
        fi
    done
}

download_file() {
    local url="$1"
    local dest="$2"

    mkdir -p "$(dirname "${dest}")"

    if [[ -f "${dest}" ]]; then
        return 0
    fi

    if command -v wget > /dev/null 2>&1; then
        if [[ -n "${HF_TOKEN:-}" && "${url}" =~ huggingface\.co ]]; then
            wget --header="Authorization: Bearer ${HF_TOKEN}" -q -O "${dest}" "${url}" || true
        elif [[ -n "${CIVITAI_TOKEN:-}" && "${url}" =~ civitai\.com ]]; then
            wget --header="Authorization: Bearer ${CIVITAI_TOKEN}" -q -O "${dest}" "${url}" || true
        else
            wget -q -O "${dest}" "${url}" || true
        fi
        return 0
    fi

    if command -v curl > /dev/null 2>&1; then
        if [[ -n "${HF_TOKEN:-}" && "${url}" =~ huggingface\.co ]]; then
            curl -L --fail --retry 3 --retry-delay 2 -H "Authorization: Bearer ${HF_TOKEN}" -o "${dest}" "${url}" > /dev/null 2>&1 || true
        elif [[ -n "${CIVITAI_TOKEN:-}" && "${url}" =~ civitai\.com ]]; then
            curl -L --fail --retry 3 --retry-delay 2 -H "Authorization: Bearer ${CIVITAI_TOKEN}" -o "${dest}" "${url}" > /dev/null 2>&1 || true
        else
            curl -L --fail --retry 3 --retry-delay 2 -o "${dest}" "${url}" > /dev/null 2>&1 || true
        fi
    fi
}

provisioning_get_model_files() {
    local item url relpath dest

    for item in "${MODEL_FILES[@]}"; do
        url="${item%%|*}"
        relpath="${item#*|}"
        dest="${COMFYUI_DIR}/${relpath}"

        download_file "${url}" "${dest}"
    done
}

if [[ ! -f "/.noprovisioning" ]]; then
    provisioning_start
fi

echo "Установка завершена"
