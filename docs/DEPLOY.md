# Rasa ECS 启动/上线手册

面向本项目（Rasa Pro + Flow + GraphRAG + Action Server）的本地/内网部署步骤，按顺序一次跑通。

## 0. 前置条件
- Python 3.10+，已创建/激活 `conda` 环境 `rasa-ecs`（或同等虚拟环境）。
- `.env` 已配置：`RASA_LICENSE`、`API_KEY`（DashScope/self-hosted LLM Key），可选 `LLM_API_HEALTH_CHECK=true`。
- 依赖服务准备：MySQL、Neo4j；嵌入模型 `bge-base-zh-v1.5`：默认读取仓库内 `models/bge-base-zh-v1.5`（存在即自动使用），也可用环境变量 `EMBED_MODEL_PATH` 指定；如均不存在会尝试从 HuggingFace 拉取 `BAAI/bge-base-zh-v1.5`（需网络）。
- 端口未占用：`10010`（嵌入）、`5055`（Action Server）、`5005`（主服务）。

## 架构示意

```mermaid
flowchart LR
  R[Rasa Pro\n- FlowPolicy\n- Enterprise Search\n- Rephraser]
  A[自定义 Action Server\n(SQLAlchemy + MySQL)]
  G[GraphRAG (Neo4j)\n- Hybrid Retriever\n- Cypher 生成/纠错\n- 自托管嵌入服务 FastAPI]
  L[通义/Qwen API (LLM)\nDashScope Compatible]

  R -->|slot/action 调用| A
  R -->|检索/图查询| G
  R -->|LLM 调用| L
  G -.->|生成/校验 Cypher 可用 LLM（可选）| L
```

## 1. 一键启动（推荐）
```bash
scripts/start-all.sh      # 前台输出主服务日志
```
- 自动加载 `.env`，先起嵌入服务（addons/embed_service.py，日志 `/tmp/embed_service.log`），再后台起 Action Server（日志 `/tmp/rasa_actions.log`），最后前台起主服务。
- 如端口冲突，可在命令前设置 `EMBED_HOST`/`EMBED_PORT`，或在启动前释放 10010/5055/5005。

## 2. 分步骤启动（需时序正确）
1) 嵌入服务（若不改端口，需确保 10010 空闲）
   ```bash
   python addons/embed_service.py --host 0.0.0.0 --port 10010
   ```
   - 若仓库内存在 `models/bge-base-zh-v1.5` 会自动使用；否则可用环境变量 `EMBED_MODEL_PATH=/abs/path/to/bge-base-zh-v1.5` 指定本地模型；缺省回退到在线模型 `BAAI/bge-base-zh-v1.5`。
2) Action Server（业务逻辑/数据库访问）
   ```bash
   scripts/start-actions.sh   # 默认端口 5055
   ```
3) 主服务（Flow + LLM + GraphRAG）
   ```bash
   scripts/start-assistant.sh -m models/<model>.tar.gz  # 默认选最新模型，端口 5005
   ```

## 3. 健康检查与常见阻塞
- 启动时若卡在 “Test call to the Embeddings API failed”：
  - 确认嵌入服务已启动并可通过 `curl http://localhost:10010/embeddings` 访问。
  - 如需暂时跳过启动探测，可在 `.env` 设 `LLM_API_HEALTH_CHECK=false`（不建议长期关闭）。
- 若报 Neo4j 认证失败：
  - `endpoints.yml` 的 `neo4j_auth` 需与实际账号密码一致；可用 `cypher-shell -u neo4j -p <pwd> "RETURN 1"` 验证。
- 若提示端口占用，先 `lsof -i tcp:10010` / `5055` / `5005` 查 PID 后释放端口。
- 未加载到模型会报 “No model found”；请先 `rasa train` 后放置于 `models/`，或用 `-m` 指定绝对路径。
- License 相关报错：确认 `RASA_LICENSE` 已在当前终端生效（`set -a && source .env`）再启动。

## 4. 运行后验证
- REST 检查：
  ```bash
  curl -X POST http://localhost:5005/webhooks/rest/webhook \
    -H "Content-Type: application/json" \
    -d '{"sender":"test-user","message":"查询我的订单"}'
  ```
- 日志位置：
  - 主服务：前台终端（或自行用 `--log-file` 指定）
  - Action：`/tmp/rasa_actions.log`
  - 嵌入：`/tmp/embed_service.log`

## 5. 关停
- 前台主服务 Ctrl+C；后台进程可用 `ps | grep rasa` / `kill <PID>`，`start-all.sh` 退出时会自动清理它启动的后台进程。

## 6. FAQ 对应入口
- “Ignoring message as there is no agent to handle it.” → 模型未成功加载，常见原因：嵌入服务健康检查失败/模型缺失/端口未起。
- GraphRAG 查询异常（HybridRetriever 报索引缺失）→ 先跑 `addons/create_indexing.py`，确保向量/全文索引存在且 Neo4j 认证正确。
- WebChat 无响应 → 主服务是否在 5005、`credentials.yml` socketio 配置、前端是否指向正确地址。
