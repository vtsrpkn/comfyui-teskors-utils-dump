#!/bin/bash

set -euo pipefail

WORKSPACE_DIR="${WORKSPACE:-/workspace}"
COMFYUI_DIR="${WORKSPACE_DIR}/ComfyUI"
MODELS_DIR="${COMFYUI_DIR}/models"
CUSTOM_NODES_DIR="${COMFYUI_DIR}/custom_nodes"
INPUTS_DIR="${COMFYUI_DIR}/input"
WORKFLOWS_DIR="${COMFYUI_DIR}/user/default/workflows"
MODEL_LOG="${MODEL_LOG:-/var/log/portal/comfyui.log}"
WORKFLOW_API_URL="${WORKFLOW_API_URL:-}"
BENCHMARK_WORKFLOW_API_URL="${BENCHMARK_WORKFLOW_API_URL:-$WORKFLOW_API_URL}"
HF_SEMAPHORE_DIR="${WORKSPACE_DIR}/hf_download_sem_$$"
HF_MAX_PARALLEL=3

REQUIRED_NODES=(
    "https://github.com/kijai/ComfyUI-WanVideoWrapper"
    "https://github.com/kijai/ComfyUI-KJNodes"
    "https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite"
    "https://github.com/kijai/ComfyUI-WanAnimatePreprocess"
    "https://github.com/rgthree/rgthree-comfy"
    "https://github.com/teskor-hub/comfyui-teskors-utils.git"
)

# The workflow file references these exact filenames, so keep the output names stable.
HF_MODELS=(
    "https://huggingface.co/wdsfdsdf/OFMHUB/resolve/main/klip_vision.safetensors|$MODELS_DIR/clip_vision/klip_vision.safetensors"
    "https://huggingface.co/wdsfdsdf/OFMHUB/resolve/main/text_enc.safetensors|$MODELS_DIR/text_encoders/text_enc.safetensors"
    "https://huggingface.co/wdsfdsdf/OFMHUB/resolve/main/vae.safetensors|$MODELS_DIR/vae/vae.safetensors"
    "https://huggingface.co/wdsfdsdf/OFMHUB/resolve/main/WanModel.safetensors|$MODELS_DIR/diffusion_models/WanModel.safetensors"
    "https://huggingface.co/wdsfdsdf/OFMHUB/resolve/main/WanFun.reworked.safetensors|$MODELS_DIR/loras/WanFun.reworked.safetensors"
    "https://huggingface.co/wdsfdsdf/OFMHUB/resolve/main/light.safetensors|$MODELS_DIR/loras/light.safetensors"
    "https://huggingface.co/wdsfdsdf/OFMHUB/resolve/main/WanPusa.safetensors|$MODELS_DIR/loras/WanPusa.safetensors"
    "https://huggingface.co/wdsfdsdf/OFMHUB/resolve/main/wan.reworked.safetensors|$MODELS_DIR/loras/wan.reworked.safetensors"
    "https://huggingface.co/Wan-AI/Wan2.2-Animate-14B/resolve/main/process_checkpoint/det/yolov10m.onnx|$MODELS_DIR/detection/yolov10m.onnx"
    "https://huggingface.co/Kijai/vitpose_comfy/resolve/main/onnx/vitpose_h_wholebody_model.onnx|$MODELS_DIR/detection/vitpose_h_wholebody_model.onnx"
    "https://huggingface.co/Kijai/vitpose_comfy/resolve/main/onnx/vitpose_h_wholebody_data.bin|$MODELS_DIR/detection/vitpose_h_wholebody_data.bin"
)

mkdir -p "$(dirname "$MODEL_LOG")"

log() {
    local message="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
    echo "$message" | tee -a "$MODEL_LOG"
}

script_cleanup() {
    rm -rf "$HF_SEMAPHORE_DIR"
    find "$MODELS_DIR" -name "*.lock" -type f -mmin +60 -delete 2>/dev/null || true
}

script_error() {
    local exit_code=$?
    local line_number=$1
    log "[ERROR] Provisioning failed at line $line_number with exit code $exit_code"
    exit "$exit_code"
}

trap script_cleanup EXIT
trap 'script_error $LINENO' ERR

acquire_slot() {
    local prefix="$1"
    local max_slots="$2"

    while true; do
        local count
        count=$(find "$(dirname "$prefix")" -name "$(basename "$prefix")_*" 2>/dev/null | wc -l)
        if [[ "$count" -lt "$max_slots" ]]; then
            local slot="${prefix}_$$_$RANDOM"
            touch "$slot"
            echo "$slot"
            return 0
        fi
        sleep 0.5
    done
}

release_slot() {
    rm -f "$1"
}

download_hf_file() {
    local url="$1"
    local output_path="$2"
    local lockfile="${output_path}.lock"
    local max_retries=5
    local retry_delay=2
    local slot
    slot=$(acquire_slot "$HF_SEMAPHORE_DIR/hf" "$HF_MAX_PARALLEL")

    mkdir -p "$(dirname "$output_path")"

    (
        if ! flock -x -w 300 200; then
            log "[ERROR] Could not acquire lock for $output_path after 300s"
            release_slot "$slot"
            exit 1
        fi

        if [[ -f "$output_path" ]]; then
            log "File already exists: $output_path"
            release_slot "$slot"
            exit 0
        fi

        local repo file_path
        repo=$(echo "$url" | sed -n 's|https://huggingface.co/\([^/]*/[^/]*\)/resolve/.*|\1|p')
        file_path=$(echo "$url" | sed -n 's|https://huggingface.co/[^/]*/[^/]*/resolve/[^/]*/\(.*\)|\1|p')

        if [[ -z "$repo" || -z "$file_path" ]]; then
            log "[ERROR] Invalid Hugging Face URL: $url"
            release_slot "$slot"
            exit 1
        fi

        local temp_dir
        temp_dir=$(mktemp -d)
        local attempt=1
        local current_delay=$retry_delay

        while [[ $attempt -le $max_retries ]]; do
            log "Downloading $repo/$file_path (attempt $attempt/$max_retries)"

            if hf download "$repo" \
                "$file_path" \
                --local-dir "$temp_dir" \
                --cache-dir "$temp_dir/.cache" 2>&1 | tee -a "$MODEL_LOG"; then
                if [[ -f "$temp_dir/$file_path" ]]; then
                    mv "$temp_dir/$file_path" "$output_path"
                    rm -rf "$temp_dir"
                    release_slot "$slot"
                    log "Downloaded: $output_path"
                    exit 0
                fi
            fi

            log "Retrying $url in ${current_delay}s"
            sleep "$current_delay"
            current_delay=$((current_delay * 2))
            attempt=$((attempt + 1))
        done

        rm -rf "$temp_dir"
        release_slot "$slot"
        exit 1
    ) 200>"$lockfile"

    local result=$?
    rm -f "$lockfile"
    return $result
}

install_custom_nodes() {
    mkdir -p "$CUSTOM_NODES_DIR"

    for repo in "${REQUIRED_NODES[@]}"; do
        local dir path
        dir="$(basename "$repo" .git)"
        path="${CUSTOM_NODES_DIR}/${dir}"

        if [[ -d "$path/.git" ]]; then
            log "Updating node repo: $dir"
            git -C "$path" pull --ff-only || true
        else
            log "Cloning node repo: $dir"
            git clone --recursive "$repo" "$path"
        fi

        if [[ -f "$path/requirements.txt" ]]; then
            log "Installing Python deps for $dir"
            pip install --no-cache-dir -r "$path/requirements.txt"
        fi
    done
}

download_models() {
    local pids=()

    for model in "${HF_MODELS[@]}"; do
        local url output_path
        url="${model%%|*}"
        output_path="${model##*|}"

        download_hf_file "$url" "$output_path" &
        pids+=($!)
    done

    local failed=0
    for pid in "${pids[@]}"; do
        if ! wait "$pid"; then
            log "[ERROR] Download process $pid failed"
            failed=1
        fi
    done

    if [[ "$failed" -ne 0 ]]; then
        exit 1
    fi
}

write_payload_examples() {
    if [[ -z "$WORKFLOW_API_URL" ]]; then
        log "WORKFLOW_API_URL is not set; skipping payload example and benchmark workflow."
        return 0
    fi

    local workflow_json
    workflow_json="$(curl -fsSL "$WORKFLOW_API_URL")"
    echo "$workflow_json" | python -m json.tool >/dev/null

    rm -f /opt/comfyui-api-wrapper/payloads/*
    cat > /opt/comfyui-api-wrapper/payloads/ofmbando.json <<EOF
{
  "input": {
    "request_id": "",
    "workflow_json": ${workflow_json}
  }
}
EOF

    if [[ -n "$BENCHMARK_WORKFLOW_API_URL" ]]; then
        local benchmark_json
        benchmark_json="$(curl -fsSL "$BENCHMARK_WORKFLOW_API_URL")"
        echo "$benchmark_json" | python -m json.tool >/dev/null

        local benchmark_dir="$WORKSPACE_DIR/vast-pyworker/workers/comfyui-json/misc"
        while [[ ! -d "$benchmark_dir" ]]; do
            sleep 1
        done

        echo "$benchmark_json" > "$benchmark_dir/benchmark.json"
        log "Wrote benchmark workflow to $benchmark_dir/benchmark.json"
    fi
}

main() {
    log "Starting ofmbando serverless provisioning"

    if [[ ! -d "$COMFYUI_DIR" ]]; then
        log "[ERROR] Expected ComfyUI at $COMFYUI_DIR. Use a comfy image, not a generic base image."
        exit 1
    fi

    if [[ -f /venv/main/bin/activate ]]; then
        # shellcheck source=/dev/null
        . /venv/main/bin/activate
    fi

    mkdir -p "$HF_SEMAPHORE_DIR"
    mkdir -p "$INPUTS_DIR"
    mkdir -p "$WORKFLOWS_DIR"
    mkdir -p "$MODELS_DIR"/{clip_vision,text_encoders,vae,diffusion_models,loras,detection}

    install_custom_nodes
    download_models
    write_payload_examples

    log "Provisioning complete. Supervisor will launch ComfyUI and the API wrapper."
}

main
