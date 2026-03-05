# Voxt Sparkle 发布接口与 CI 集成方案

本文档定义 `voxt.actnow.dev` 侧需要实现的发布接口，供 GitHub Actions 在发版时自动上传更新包并生成 Sparkle appcast。

- 站点域名：`https://voxt.actnow.dev`
- 包下载前缀：`https://voxt.actnow.dev/release/...`
- appcast 前缀：`https://voxt.actnow.dev/updates/...`

## 1. 目标

当前项目已经在 CI 内完成：
- 构建/签名/公证 `.pkg`
- 生成 Sparkle `edSignature`

需要把「发布到 GitHub + 在仓库写 `updates/appcast.xml`」扩展/迁移为：
- CI 调用业务站点 API 上传包与元信息
- CI 调用业务站点 API 生成/更新 appcast
- App 通过业务域名拉取更新

## 2. 渠道与路径约定

建议固定如下：

- Stable 包：`/release/stable/Voxt-{version}.pkg`
- Beta 包：`/release/beta/Voxt-{version}.pkg`
- Stable appcast：`/updates/stable/appcast.xml`
- Beta appcast：`/updates/beta/appcast.xml`

示例：
- `https://voxt.actnow.dev/release/stable/Voxt-1.3.0.pkg`
- `https://voxt.actnow.dev/updates/stable/appcast.xml`

## 3. 鉴权（简单且够用）

采用单一发布密钥（服务端校验，不做复杂签名）：

- Header：`Authorization: Bearer <VOXT_RELEASE_API_KEY>`
- 推荐附加 Header：`X-Voxt-Source: github-actions`

服务端要求：
- 只允许 HTTPS
- key 不写日志明文
- 失败统一返回 401/403

## 4. 接口设计

## 4.1 上传更新包

`POST /api/pkg/update`

### Content-Type
`multipart/form-data`

### 表单字段
- `channel`：`stable` | `beta`
- `version`：如 `1.3.0`
- `sparkleVersion`：Sparkle 整数版本号，如 `1003000`
- `file`：二进制 pkg 文件
- `sha256`：pkg sha256
- `size`：pkg 字节数（与 Sparkle length 一致）
- `edSignature`：Sparkle EdDSA 签名（CI 由 `sign_update` 产出）
- `releaseNotes`：发布说明（纯文本或 markdown）
- `releaseURL`：发布详情页 URL（可填 GitHub Release 链接）
- `publishedAt`：ISO8601 时间（UTC）

### 成功响应（200）

```json
{
  "ok": true,
  "data": {
    "channel": "stable",
    "version": "1.3.0",
    "packageURL": "https://voxt.actnow.dev/release/stable/Voxt-1.3.0.pkg",
    "sha256": "...",
    "size": 123456789
  }
}
```

### 失败响应

```json
{
  "ok": false,
  "error": {
    "code": "INVALID_REQUEST",
    "message": "missing field: edSignature"
  }
}
```

## 4.2 生成/更新 appcast

`POST /api/pkg/appcast`

### Content-Type
`application/json`

### 请求体

```json
{
  "channel": "stable",
  "version": "1.3.0",
  "mode": "replace-latest"
}
```

字段说明：
- `channel`：`stable` | `beta`
- `version`：必须已通过 `/api/pkg/update` 上传
- `mode`：建议固定 `replace-latest`

服务端行为：
- 从已保存的发布元信息读取 `packageURL / edSignature / size / releaseNotes / publishedAt`
- 生成 Sparkle 标准 RSS XML
- 写入：
  - stable -> `/updates/stable/appcast.xml`
  - beta -> `/updates/beta/appcast.xml`

### 成功响应（200）

```json
{
  "ok": true,
  "data": {
    "channel": "stable",
    "version": "1.3.0",
    "appcastURL": "https://voxt.actnow.dev/updates/stable/appcast.xml"
  }
}
```

## 5. 服务端最小校验清单

- `version` 格式：`X.Y.Z`（beta 可额外带 tag 信息，但 appcast 建议仍使用正式 semver）
- `channel` 必须在允许集合
- `size` > 0
- `edSignature` 非空
- `sha256` 64 hex
- 同版本重复上传策略：
  - 默认允许覆盖（`upsert`）
  - 响应里标注 `updated: true/false`

## 6. CI 调用顺序（建议）

1. 构建、签名、公证 pkg
2. 生成 `sha256`
3. 生成 Sparkle `edSignature`
4. 调用 `/api/pkg/update` 上传包+元信息
5. 调用 `/api/pkg/appcast` 更新 appcast
6. （可选）仍保留 GitHub Release 资产上传

## 7. GitHub Actions 调用示例

```bash
API_BASE="${VOXT_UPDATE_API_BASE}"
CHANNEL="stable" # 或 beta
VERSION="1.3.0"
PKG_PATH="build/Voxt-${VERSION}.pkg"
SHA256="$(cat build/Voxt-${VERSION}.pkg.sha256)"
SIZE="${SPARKLE_ED_LENGTH}"
SIG="${SPARKLE_ED_SIGNATURE}"
NOTES="${RELEASE_NOTES}"
RELEASE_URL="${RELEASE_URL}"
PUBLISHED_AT="${PUBLISHED_AT}"

curl --fail --silent --show-error \
  -X POST "${API_BASE}/api/pkg/update" \
  -H "Authorization: Bearer ${VOXT_RELEASE_API_KEY}" \
  -H "X-Voxt-Source: github-actions" \
  -F "channel=${CHANNEL}" \
  -F "version=${VERSION}" \
  -F "sparkleVersion=${SPARKLE_VERSION}" \
  -F "sha256=${SHA256}" \
  -F "size=${SIZE}" \
  -F "edSignature=${SIG}" \
  -F "releaseNotes=${NOTES}" \
  -F "releaseURL=${RELEASE_URL}" \
  -F "publishedAt=${PUBLISHED_AT}" \
  -F "file=@${PKG_PATH};type=application/octet-stream"

curl --fail --silent --show-error \
  -X POST "${API_BASE}/api/pkg/appcast" \
  -H "Authorization: Bearer ${VOXT_RELEASE_API_KEY}" \
  -H "Content-Type: application/json" \
  -d "{\"channel\":\"${CHANNEL}\",\"version\":\"${VERSION}\",\"mode\":\"replace-latest\"}"
```

## 8. App 侧配置建议

稳定版建议：
- `SUFeedURL = https://voxt.actnow.dev/updates/stable/appcast.xml`

Beta 构建建议：
- `SUFeedURL = https://voxt.actnow.dev/updates/beta/appcast.xml`

继续保留：
- `SUPublicEDKey`（Sparkle 公钥）

## 9. 需要配置的 GitHub Secrets

现有 workflow 已用（你们当前已有的大部分）：
- `DEVELOPER_ID_APP_CERT_P12`
- `DEVELOPER_ID_APP_CERT_PASSWORD`
- `DEVELOPER_ID_INSTALLER_CERT_P12`
- `DEVELOPER_ID_INSTALLER_CERT_PASSWORD`
- `DEVELOPER_ID_APP_IDENTITY`
- `DEVELOPER_ID_INSTALLER_IDENTITY`
- `KEYCHAIN_PASSWORD`
- `APPLE_NOTARIZATION_ISSUER` / `APPLE_NOTARIZATION_KEY_ID` / `APPLE_NOTARIZATION_KEY`
  - 或 `APPLE_ID` / `APPLE_TEAM_ID` / `APPLE_APP_SPECIFIC_PASSWORD`
- `SPARKLE_PRIVATE_KEY`

新增（站点 API 发布）：
- `VOXT_UPDATE_API_BASE` = `https://voxt.actnow.dev`
- `VOXT_RELEASE_API_KEY` = 站点发布接口密钥

可选：
- `VOXT_UPDATE_CHANNEL`
  - 默认可由 tag/分支推断，不一定需要 secret

## 10. 推荐发布策略

- `vX.Y.Z` -> stable
- `vX.Y.Z-beta.N` 或 workflow_dispatch 指定 -> beta

并在 workflow 内显式映射 channel，避免手工误传。

## 11. 回滚方案

若站点发布失败：
- CI 直接 fail（不要 silent）
- 已上传包可再次调用 appcast 接口回滚到上一版本
- 必要时手工指定 `version` 重建 appcast

---

如果后续要我直接改 `.github/workflows/release.yml`：
- 我可以把现有 `update_appcast_main` 作业替换为 `publish_to_voxt_api` 作业
- 并保留 GitHub Release 资产上传作为备份分发通道
