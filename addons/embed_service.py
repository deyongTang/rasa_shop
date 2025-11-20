"""提供嵌入模型服务接口，方便 rasa 中调用该 Embedding 模型。"""

import os
from pathlib import Path
from fastapi import FastAPI
from pydantic import BaseModel
from sentence_transformers import SentenceTransformer

# 支持通过环境变量配置模型路径/名称，默认优先本项目内的 models 目录，不存在则回退到 HuggingFace 名称
ENV_MODEL = os.getenv("EMBED_MODEL_PATH")
DEFAULT_CANDIDATES = [
    Path(__file__).resolve().parent.parent / "models" / "bge-base-zh-v1.5",
    Path(__file__).resolve().parent.parent.parent / "models" / "bge-base-zh-v1.5",  # 兼容此前 ../models
]
PRIMARY_MODEL_ID = str(Path(ENV_MODEL).expanduser()) if ENV_MODEL else next(
    (str(p) for p in DEFAULT_CANDIDATES if p.exists()),
    "BAAI/bge-base-zh-v1.5",
)
FALLBACK_MODEL_ID = os.getenv("EMBED_MODEL_FALLBACK", "BAAI/bge-base-zh-v1.5")


def load_model():
    try:
        print(f"[embed_service] Loading model: {PRIMARY_MODEL_ID}")
        return SentenceTransformer(PRIMARY_MODEL_ID)
    except FileNotFoundError:
        if PRIMARY_MODEL_ID == FALLBACK_MODEL_ID:
            raise
        print(
            f"[embed_service] Primary model not found: {PRIMARY_MODEL_ID}, "
            f"fallback to: {FALLBACK_MODEL_ID}"
        )
        return SentenceTransformer(FALLBACK_MODEL_ID)


# 加载模型（启动时执行）
model = load_model()


# 请求格式
class EmbeddingRequest(BaseModel):
    model: str
    input: str | list[str]


app = FastAPI()


@app.post("/embeddings")
def embed(request: EmbeddingRequest):
    embed_batch_size = 64  # 每次处理64个句子
    # 统一转成list
    texts = [request.input] if isinstance(request.input, str) else request.input
    # 使用模型对文本进行编码，批量大小为64，同时进行向量归一化
    embeddings = model.encode(
        texts, batch_size=embed_batch_size, normalize_embeddings=True
    )
    embeddings = embeddings.tolist()

    # 按照OpenAI Embedding API的格式返回结果
    return {
        "object": "list",
        "data": [
            {
                "object": "embedding",
                "embedding": embed,
                "index": i,
            }
            for i, embed in enumerate(embeddings)
        ],
    }


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(app, host="0.0.0.0", port=10010)
