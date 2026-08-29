# Docker 镜像使用说明

本项目通过根目录 `Dockerfile` 打包成一个**单镜像**，同时承载前后端：

```
┌─────────────────────────── 容器 ───────────────────────────┐
│  nginx  (公网端口 7001)             Python 后端 (内部 9000)  │
│  ├─ 托管前端静态资源 (dist)          uvicorn main:app         │
│  └─ 反向代理 /api /local-assets     由 entrypoint.sh 后台启动 │
│     /generate-code (WebSocket)
└─────────────────────────────────────────────────────────────┘
```

- nginx 是唯一公网入口，端口 **7001**
- 前端 JS 默认同源调用后端（`window.location.origin`），无需额外配置
- 后端在容器内 `127.0.0.1:9000` 运行，不直接对外

---

## 一、构建镜像

```bash
docker build -t screenshot-to-code .
```

可在 `docker build` 时通过 `--build-arg` 覆盖镜像内的默认端口（如需修改）：

```bash
docker build \
  --build-arg BACKEND_PORT=9000 \
  -t screenshot-to-code .
```

> 构建需要联网：会执行 `pnpm build`（前端）、`poetry install`（后端依赖）以及
> `playwright install --with-deps chromium`（用于截图预览工具），首次构建较慢且体积较大。

---

## 二、运行

### 2.1 最小启动（官方 OpenAI）

```bash
docker run -p 7001:7001 -it \
  -e OPENAI_API_KEY=sk-xxx \
  screenshot-to-code
```

启动后浏览器访问：**http://localhost:7001**

### 2.2 使用环境变量文件（推荐）

建议把所有 `OPENAI_*/ANTHROPIC_*/GEMINI_*/...` 配置写进一个 `.env` 文件，再导入：

```bash
docker run -p 7001:7001 -it --env-file .env screenshot-to-code
```

`.env` 示例见 [第三节](#三环境变量参考)。

### 2.3 同时配置多家 / 图片编辑

```bash
docker run -p 7001:7001 -it \
  -e OPENAI_API_KEY=sk-xxx \
  -e ANTHROPIC_API_KEY=sk-ant-xxx \
  -e GEMINI_API_KEY=AIza-xxx \
  -e REPLICATE_API_KEY=xxx \
  screenshot-to-code
```

> 模型在 Web 界面右上角的设置面板里选择，无需改环境变量。
> `REPLICATE_API_KEY` 用于启用“图片编辑”工具（`edit_images`），不配置则界面不出现该选项。

---

## 三、环境变量参考

### 模型提供方（至少配置一个）

| 变量 | 必填 | 说明 |
|------|------|------|
| `OPENAI_API_KEY` | 二选一 | OpenAI 官方 key，或兼容端点的 key |
| `ANTHROPIC_API_KEY` | 二选一 | Anthropic Claude key |
| `GEMINI_API_KEY` | 二选一 | Google Gemini key |
| `OPENAI_BASE_URL` | 可选 | 覆盖 OpenAI 兼容的 base URL（详见第四节） |

### 能力 / 调试相关（可选）

| 变量 | 说明 |
|------|------|
| `REPLICATE_API_KEY` | 启用图片编辑工具 `edit_images` |
| `IS_DEBUG_ENABLED` / `DEBUG_DIR` | 后端调试日志开关与目录 |
| `PROMPT_REPORTS_ENABLED` | 开启 prompt 报告（`/evals/prompt-reports`） |
| `LOCAL_ASSET_DIR` / `LOCAL_ASSET_BASE_URL` | 本地素材目录 / 对外地址，默认已够用 |
| `SCREENSHOT_TO_CODE_DATA_DIR` | 设计系统数据目录 |
| `LOGS_PATH` / `EVALS_DIR` | 日志 / 评测相关 |

> ⚠️ 自托管时**不要设置** `IS_PROD=true`。开启后代码会忽略 `OPENAI_BASE_URL`，
> 并关闭设置面板里的自定义 base URL 输入框。

`.env` 参考模板：

```dotenv
OPENAI_API_KEY=sk-xxx
ANTHROPIC_API_KEY=sk-ant-xxx
GEMINI_API_KEY=AIza-xxx

# 兼容端点的 base url（见第四节）
# OPENAI_BASE_URL=https://your-provider.example.com/v1

# 图片编辑
# REPLICATE_API_KEY=xxx

# 调试 / 报告
# IS_DEBUG_ENABLED=false
# PROMPT_REPORTS_ENABLED=
```

> 前端另有 `VITE_WS_BACKEND_URL` / `VITE_HTTP_BACKEND_URL` / `VITE_IS_DEPLOYED`，
> 属于**构建期**变量，已在镜像构建时按同源默认值烘焙进产物，运行时无需配置。

---

## 四、使用第三方兼容 OpenAI 格式的服务

支持通过环境变量指向兼容端点，但有两个前提，否则连不上：

1. **设置后必须在 Web 界面选择 OpenAI 模型。** 客户端类型按所选模型分派，
   只有选择 `gpt-*` 系列才会走 OpenAI 客户端。选 Claude/Gemini 模型则不会命中该端点。

2. **端点需实现 OpenAI Responses API（`/v1/responses`），且接受固定的 GPT 模型名。**
   代码实际调用的是 `client.responses.create()`（带 streaming、`reasoning` 等参数），
   并发送硬编码的模型名（如 `gpt-5.5`、`gpt-5.4-2026-03-05`），模型名**无法**通过环境变量修改。

启动示例（适配实现了 Responses API 的网关）：

```bash
docker run -p 7001:7001 -it \
  -e OPENAI_API_KEY=your-provider-key \
  -e OPENAI_BASE_URL=https://your-provider.example.com/v1 \
  screenshot-to-code
```

> ❌ 不兼容说明：仅实现 `/v1/chat/completions` 的服务（许多本地/开源服务如 Ollama、
> vLLM 及部分国内厂商）无法直接使用；需要自定义模型名的场景在当前源码下
> 也无法仅靠环境变量实现，需改源码或通过网关做模型名/端点适配。

---

## 五、从 GitHub 发布并拉取镜像

仓库内的 `.github/workflows/docker-publish.yml` 提供了一个**手动触发**的 Action：

1. 在 GitHub 仓库 `Actions` 页签，点选 `Build and Publish Docker Image` → `Run workflow`；
2. 构建多架构镜像（`linux/amd64`、`linux/arm64`）并推送到
   `ghcr.io/<你的用户名>/screenshot-to-code`（标签：`latest` + commit SHA）。

拉取使用：

```bash
docker pull ghcr.io/<你的用户名>/screenshot-to-code:latest

docker run -p 7001:7001 -it \
  -e OPENAI_API_KEY=sk-xxx \
  ghcr.io/<你的用户名>/screenshot-to-code:latest
```

> 前置要求：仓库 `Settings → Actions → General` 中 Workflow 权限需设为
> “Read and write”，Action 才会拥有 `packages: write`，从而能推送到 GHCR。

---

## 六、常见问题

- **页面能打开但生成报错“API key is missing”**
  检查是否设置了对应所选模型的 `OPENAI_*`/`ANTHROPIC_*`/`GEMINI_*` key。

- **生成后没有代码只在转圈**
  检查第三方兼容端点是否支持 `/v1/responses` 与流式输出，以及 WebSocket 转发是否正常。

- **需要改监听端口**
  调整 `docker run -p 宿主机端口:7001`，把宿主端口映射到容器内的 `7001` 即可。