---
name: store-publish
description: 将 KeepUp 已有 xcarchive 上传到 App Store Connect。用户选择 Store 发布渠道或明确要求上传构建时使用；不重新归档，不自动提交审核。
---

# Store 发布

先读 [config.env](config.env)，使用其中的签名团队、预期 bundle identifier 和 `app-store-connect` 上传方式。沿用 Xcode 已登录账户及自动签名，不要求另建 API Key。

需要准确的已有 `.xcarchive` 路径。检查模式先核对包身份、版本和 build；上传使用同一归档，不重新打包、不改归档或工程版本。

```sh
.agents/skills/store-publish/scripts/publish.sh --archive /absolute/path/KeepUp.xcarchive --inspect-only
.agents/skills/store-publish/scripts/publish.sh --archive /absolute/path/KeepUp.xcarchive
```

选择项目 `fir + Store` 渠道或明确要求上传这个 archive，即授权一次上传，不再重复确认。只有上传命令正常完成才报告 `STORE_UPLOAD_SUCCEEDED=true`，它表示 Apple 接收构建并进入后续处理，不等于 TestFlight 已可用或审核通过。

上传失败或超时、结果不明确时，保留日志并先核实 App Store Connect 是否已接收；不自动重试或盲目改 build 号重传。脚本使用 `manageAppVersionAndBuildNumber=false` 保留归档 build 号。

报告实际版本、build、归档路径、上传结果及需要处理的非阻断校验警告。日志和 ExportOptions 保留在项目 `build/releases/store`。本 skill 不负责 fir 上传、选择处理后的构建、填写商店资料或提交审核；后续动作需要用户明确要求。

维护后可运行 `python3 Tests/AppPublish/test_publish.py`，离线验证上传参数、检查模式和失败停止；它不操作 Apple 账户。
