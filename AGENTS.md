# 项目约定

- 当前优先与 PunchCard 对齐功能和交互；真机传感器、后台定位等验收集中后置，不作为继续实现本地功能的门槛。

## 项目内打包 Skills

- `app-archive`：[归档和签名 IPA 导出](.agents/skills/app-archive/SKILL.md)。
- `fir-publish`：[上传已有 IPA 到 fir 并发送 Lark 通知](.agents/skills/fir-publish/SKILL.md)。与 PunchCard 使用相同 fir 账号和机器人，应用短码独立。
- `store-publish`：[上传已有归档到 App Store Connect](.agents/skills/store-publish/SKILL.md)。

## 打包发布约定

- 默认构建号为北京时间 `yyyyMMddNN`，当日流水号从 `01` 递增；由归档脚本分配，仅作用于本次构建，不修改工程版本。

- 用户只说“打包”“打个包”，未指定渠道时，提供编号选项并等待选择：`1. fir（归档导出、上传、Lark 通知）`；`2. fir + Store（归档导出、上传 Store 和 fir、Lark 通知）`。
- 用户选择 `1` 或明确说“打 fir 包”，即授权并要求完成归档导出、fir 上传和配置群通知，无需再次确认。
- 用户选择 `2`，或明确说“打提审包”“打 Store 包”“fir + Store”，即授权按同一份归档依次完成导出 IPA、上传 App Store Connect、上传 fir、发送 Lark 通知，无需再次确认。
- 用户明确只要本地包／只归档时，仅使用 app-archive；明确只上传已有 IPA 或已有 archive 时，仅执行指定发布动作，不重新打包。
- Store 成功指 Apple 已接收构建并进入处理；不自动选择构建、编辑商店资料或提交审核。
- 更新说明只写实际包含在产物中的改动。上传结果不明确时先核查，不能自动重复上传；通知失败不能重新上传 IPA。
- Lark 通知直接请求配置的完整 `open.larksuite.com` webhook，不把 token 交给会改写域名的工具。创建／检查 skill 本身不触发任何上传或通知。
