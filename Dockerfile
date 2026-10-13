# syntax=docker/dockerfile:1
# ============================================================
# RAG_System 應用映像（RAG 容器）
# 目標架構：linux/arm64（NVIDIA Jetson AGX Orin）。
#   - 主要：GitHub Actions 原生 arm64 runner 建置（無 QEMU 模擬）：
#       .github/workflows/build-arm64.yml → 產出 artifact rag-app-arm64.tar
#   - 或本機 Windows (x86_64) 用 buildx 跨編譯：
#       docker buildx build --platform linux/arm64 -t rag-app:arm64 --load .
#     （所有依賴都是 pure-Python / manylinux_aarch64 wheel，可跨編譯，無需多階段編譯。）
#   - 在 Orin 上可直接原生 build（更快）。
#
# 設計要點：
#   - 只打包「程式碼 + 依賴」；data / storage / venv 一律不進映像，
#     由 docker-compose 用 bind mount 掛載（離線部署時手動放進容器旁邊的目錄）。
#   - 預設 OFFLINE：LLM/Embedding/VLM 全走本機 Ollama，無任何雲端呼叫。
# ============================================================
FROM python:3.12-slim

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    # 離線保護：不碰 HF Hub / transformers 下載
    HF_HUB_OFFLINE=1 \
    TRANSFORMERS_OFFLINE=1 \
    # llama-index 自訂 token 計數（sentence-splitter 內建 BPE，離線安全）
    # 這裡只是宣告，實際 tokenizer 由 llama-index-tokenizer 內建提供。
    LLM_MODEL="qwen2.5:7b" \
    EMBEDDING_MODEL="bge-m3" \
    # VLM 預設走本機 Ollama 多模態模型（離線）
    VLM_BACKEND="ollama" \
    VLM_OLLAMA_MODEL="qwen2.5vl:7b" \
    # Ollama 連線位址：Jetson 部署預設 host network（ollama 直接吃 host 網卡 + CUDA），
    # rag 用 localhost 連 ollama。若改用 bridge 網絡，改回 http://ollama:11434。
    OLLAMA_BASE_URL="http://127.0.0.1:11434"

WORKDIR /app

# 先裝依賴（利用 Docker layer cache：requirements 不變則跳過重裝）
COPY requirements.txt ./
# 明確補上 ollama python SDK（llama-index-llms-ollama 已附帶，但顯式聲明更穩）
RUN pip install --upgrade pip && \
    pip install -r requirements.txt

# 再拷源碼
COPY . .

# 預設跑主程式；compose 可用 command 覆蓋（如 python kg_cli.py）。
CMD ["python", "app.py"]
