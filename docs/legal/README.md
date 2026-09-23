# KeepUp 协议页面

`privacy.html` 和 `agreement.html` 是发布源文件，均包含简体中文和英文。页面优先读取 `?lang=zh-Hans` 或 `?lang=en`，未指定时读取浏览器语言。运营主体为 ShiYue Bu，联系邮箱为 `156788742@qq.com`。

线上对象位于 `xbingo-assets` 桶，与 IAAP 配置使用同一 KeepUp 正式环境前缀：

| 文件 | 对象名 | 公开地址 |
| --- | --- | --- |
| `privacy.html` | `keep-up/pro/pages/privacy.html` | `https://assets.xbingo.top/keep-up/pro/pages/privacy.html` |
| `agreement.html` | `keep-up/pro/pages/agreement.html` | `https://assets.xbingo.top/keep-up/pro/pages/agreement.html` |

App 首次启动、个人设置和会员购买页均指向这些地址，使用 App 当前语言参数。更新文本时同步更新本目录并重新发布；发布后用 HTTPS 回读两种语言，并确保 App Store Connect 的隐私政策与用户协议地址指向这些页面。

2026-09-23 已将两份文件上传至上述对象名，HTTP 回读均为 200，`Content-Type: text/html; charset=utf-8`，回读内容的 SHA-256 与本地源文件一致。浏览器已验证简体中文隐私页及英文用户协议的语言切换和联系方式。

文案依据当前 KeepUp 实现：个人资料及运动记录保存在设备本地；步数来自 Core Motion；户外活动使用 Core Location；购买由 StoreKit 处理；Google Mobile Ads/UMP 已接入但当前广告配置关闭；iCloud 同步尚未实现。功能或第三方处理方式改变时，需要重新核对文案。

参考：[《中华人民共和国个人信息保护法》第十七条](https://www.miit.gov.cn/jgsj/zfs/fl/art/2022/art_515a4b20c12f430eab54bb4f56d89f56.html)、[Apple App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)、[Apple 订阅说明](https://developer.apple.com/app-store/subscriptions/)、[Google UMP iOS 文档](https://developers.google.com/admob/ios/privacy)。
