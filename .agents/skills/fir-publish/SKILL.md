---
name: fir-publish
description: 将 KeepUp 已有 IPA 上传到 fir.im，取得该包专属下载链接并发送 Lark 发布通知。用户要求发 fir 包或选择 fir 发布渠道时使用；不负责构建归档。
---

# fir 发布

先读 [config.env](config.env) 的固定配置。`credentials.env` 位于本 skill 目录，包含 `FIR_API_TOKEN` 和完整 `FIR_LARK_WEBHOOK_URL`，被 Git 忽略；也可通过环境变量提供。检查是否已配置即可，不输出密钥、不要求迁移到 Keychain，与 PunchCard 复用 fir 账号和 Lark 机器人，但不借用其应用短码。`FIR_SHORT` 默认留空，由 fir 按 KeepUp Bundle ID 返回应用链接；确认 KeepUp 自己的短码后才可固定。凭据不足时先准备好产物检查和更新说明，再报告缺失项。

需要明确的已有 IPA 路径和简洁中文更新说明。说明只能基于确实包含在该 IPA 中的变化；不能把打包之后的未提交改动写进去。用户明确不要说明时才用 `--no-changelog`。

项目根目录执行：

```sh
.agents/skills/fir-publish/scripts/publish.sh --artifact /absolute/path/KeepUp.ipa --inspect-only
.agents/skills/fir-publish/scripts/publish.sh --artifact /absolute/path/KeepUp.ipa --changelog '本次更新内容'
```

检查模式不需要上传凭据、不联网。脚本先用 `fir info` 校验 IPA 身份及版本；上传用 `--need-release-id` 获取包专属链接，再直接请求配置的完整 `open.larksuite.com` webhook。不能仅把 webhook token 传给 fir-cli 的飞书参数，否则工具会改写域名。通知格式：应用名称／版本／build、`下载地址:`、`相对上次测试包变更：`；每行更新说明自动编号。

发布脚本通过 [api.yml](api.yml) 使用官方接口的 HTTPS 地址；[scripts/fir_cli.rb](scripts/fir_cli.rb) 在当前进程启用证书校验，并兼容现有 fir-cli 2.0.25 开启校验时返回空配置的问题，不改全局 gem。它同时关闭 API 和发布回调的隐式重试，避免请求结果不明时再次写入。

明确要求发 fir 包或选择项目的 fir 发布渠道，表示授权一次 IPA 上传和配置群通知，无需重复确认。只要求查看或创建 skill 不授权发布。凭据、原始工具输出和通知响应不打印到对话；脚本日志保存在项目 build 下，日志可能含工具返回的临时上传信息，不能直接贴出。

上传结果不明确时停止，先查状态，不自动重传。上传成功但通知失败时报告已完成的上传及 `PACKAGE_URL`，不要重新上传；用户要求补发通知时使用 `--notify-only --package-url` 和此前已确认的包专属链接。补发不会重传 IPA。其他参数见 `--help`。

报告实际应用版本、build、更新说明、`PACKAGE_URL` 和通知是否成功。`FIR_UPLOAD_SUCCEEDED=true` 与 `LARK_NOTIFICATION_SUCCEEDED=true` 分别表示两步完成，不能相互代替。

维护后运行 `python3 Tests/AppPublish/test_publish.py` 与 `ruby Tests/AppPublish/test_fir_transport.rb`；这些是离线替身／异常注入测试，不证明真实上传或通知成功。
