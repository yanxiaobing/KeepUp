# KeepUp IAAP 客户端接入

## 配置来源与接口

`IAAPConfigurationStore` 启动同步读取包内 `iaap.json`，随后读取有效的 Application Support/KeepUp/iaap-cache-v1.json 缓存；`refresh()` 成功后更新内存和原子写入磁盘。`remoteURL` 默认 `nil`，不会发起网络请求。用户已提供 KeepUp 独立 OSS HTTPS 地址，`Config/Info.plist` 的 `KeepUpIAAPConfigurationURL` 已设置为 `https://assets.xbingo.top/keep-up/pro/iaap/1.0.0.json`，App 通过 `IAAPConfigurationStore.configuredRemoteURL` 注入。后续更换地址只需更新该键；删除该键则不发起远程请求。本次未修改 apps-admin 或线上 OSS，也未接入 Cloudflare。

Store 暴露 `configuration`、`knownSKUs`、`entitlementProductIDs`、`source`、`lastError`、`isRefreshing`。调用方在首次读取和每次刷新完成后，将 `configuration.membershipConfiguration(for:)` 与 `entitlementProductIDs` 交给 MembershipStore。页面入口为 `guide / launch / limited / vip`，按类型精确查找，不跨页回退；默认会员读取 `vip`。缺失入口时不展示其他入口的商品或激励参数。页面商品顺序来自 `iap.pids`，会员商品映射仅包含 `lifetime` 和 `subscribe`。新订阅的 UI 周期以 StoreKit 为准，旧商品的月份仅作原有 UI 兼容。

`system`、`ads` 在基础协议中保存为 JSONValue 字典，以兼容后台扩展；广告由新增 `IAAPAdConfiguration` 强类型映射，通过 `AppAdvertising` 同步到三个 SDK 实例、`AdPresentationCoordinator` 和激励入口，不根据未知字段开放业务能力。页面解析 `closeAlpha`、`priceAlpha`、`showGiveUp`、`hideFuncBtn`、既有 `reward` 对象和 `iap` 的 `pids/timeInterval/hidePageControl`。功能激励仅读取 `limited` 页面，不回退其他页面，沿用 `reward { rewardId, insertId, count, hideGiveUpWhenNoAd }`，不另建广告业务配置对象。

## 接收与回退规则

- 每次 `refresh()` 发起网络请求前，通过 URLComponents 移除所有已有 `v` 参数，再追加当前 Unix 毫秒整数时间戳 `v`。其他 query 参数及顺序保留；没有 query 时使用 `?v=...`，已有 query 时追加 `&v=...`，重复构造不会叠加多个 `v`。同时保留 `reloadIgnoringLocalCacheData` 请求策略。
- 请求只接受无用户名密码的 HTTPS URL；响应要求 HTTP 2xx、最终 URL 仍为 HTTPS、载荷不超过 1 MiB，并通过 JSON 结构与语义校验。
- `skus` 必须无重复、使用 KeepUp 独立商品前缀 `com.bestlife.keepup.`、类型为 `lifetime/subscribe/consumable`。页面引用必须存在于当前目录，页面类型仅允许 `guide / launch / limited / vip`，类型不能重复，页面按入口精确匹配；透明度和轮播时间需在有效范围。
- 网络失败、损坏 JSON、未知商品类型、不完整配置、历史 SKU 类型改变、写盘失败都保留最后有效状态，并记录错误。损坏磁盘缓存回退包内配置。
- 磁盘缓存的 `sourceURL` 始终记录配置注入的原始 `remoteURL.absoluteString`，不记录请求时生成的动态时间戳 URL；重启时仍以原始 URL 匹配，因此每次时间戳变化不会使有效磁盘缓存失效。只有切换或移除配置中的 URL 时，页面恢复包内配置，直到新地址成功返回；KeepUp 历史商品目录仍保留。
- SKU 目录与页面展示分离。`knownSKUs` 累加包内目录、缓存历史和新的有效目录，`entitlementProductIDs` 不会因商品从当前页面或当前目录移除而丢失。卸载后恢复历史权益仍需平台验证的交易和服务端维护完整历史目录；包内已知历史商品始终存在。
- 四个商品已在 KeepUp 独立 App Store Connect 应用创建，平台清单见进展文档。包内和交接配置记录三个独立 AdMob 广告位，不填写未确认的商品价格。`ads.enabled` 和各广告位 `enabled` 全为 false。资源映射要求 App ID 与独立广告位白名单匹配；功能激励还必须有有效的页面 `reward`。当前仅 `limited` 配置 `reward`，其余三个页面不配置；广告开关关闭时三个功能仍免费直达，不授予会员。

## 已执行验证

2026-09-22：核心文件 `swiftc -typecheck` 通过；用 `.build/IAAPValidation` 临时 Swift Package 运行同一份 `IAAPConfigurationTests.swift`，5 项 Swift Testing 测试全部通过，覆盖解析/兜底、缓存重启、隐藏商品历史权益、无 URL、HTTP 拒绝、网络/HTTP 失败、损坏远程不覆盖缓存、切换来源 URL、重复商品、商品类型冲突和取消下载。主任务随后完成完整模拟器测试与真机目标 Release 编译，结果见 [本轮验收记录](monetization-status.md)。

2026-09-22 17:38（北京时间）：真实 OSS 返回 HTTPS 200，服务端为 AliyunOSS，Content-Type 为 application/json; charset=utf-8，Content-Length 为 1798。实际 `skus` 与 `final/vip/guide` 的 `iap.pids` 均按顺序匹配 `com.bestlife.keepup.premium.{lifetime,year,quarter,month}`；`system`、`ads` 为空，没有价格字段。

新增显式启用的真实下载测试 `iaapLiveEndpointDownloadsValidKeepUpCatalogAndCachesIt`，通过实际 URLSession 调用 Store.refresh()，验证商品/页面解析、远程状态、磁盘缓存和重启恢复。执行 `KEEPUP_IAAP_LIVE_URL=https://assets.xbingo.top/keep-up/pro/iaap/1.0.0.json swift test --package-path .build/IAAPValidation`，最新一轮于 17:40 带动态 `v` 完成真实 OSS 下载与缓存恢复，7 项测试全部通过。新增时间戳测试覆盖原地址没有 query、保留既有 query、替换多个旧 `v` 及重复构造不叠加参数。普通测试不设置该环境变量，真实网络测试自动跳过；UI 测试应注入 nil URL 和 nil cache，隔离网络与历史状态。

真实 OSS 下载解析和缓存已验收；真实 StoreKit 交易与真实广告播放仍需各自独立验收。

## 当前四页修订与发布状态

完整待发布配置见 [keepup-iaap.1.0.0.json](config/keepup-iaap.1.0.0.json)，后台执行说明见 [更新提示词](config/keepup-apps-admin-update-prompt.md)。本轮已统一包内、完整交接和初始模板的页面顺序为 `guide → launch → limited → vip`。`launch / limited` 继承旧普通页的参数与商品，其他字段不变，不新增价格、奖励或广告开关；三份配置均设置用户指定的 `system.isBanana=false`。

新客户端拒绝含旧 `final / limited_funcs` 类型的远程配置，继续使用有效配置或四页包内兜底；旧缓存中的历史 SKU 目录仍保留，避免展示协议迁移丢失历史购买识别。按入口精确查找，缺页不会串用其他页面。

此前移除额外字段后的 HTTP 200 回读文件 `.build/iaap-policy-removal-remote.json` 对应旧三页版本，当时与本地语义一致；这是历史状态。当前四页更新仅在本地，尚未由本会话发布，需 apps-admin 更新发布后再回读核验。没有修改后台或 OSS，也不接入 Cloudflare。

配置不含 `ads.policy`，广告总开关和各广告位开关保持 false，仅 `limited` 有 `reward`，开关关闭时不启用功能激励。通用冷启动、后台停留至少 30 秒后的热启动，以及引导/启动会员页关闭后的插屏由客户端入口衔接并受 `ads` 开关控制。最新四页结构的单元测试、3项UI回归和无签名Release构建已通过，记录见monetization-status.md；上文验证记录仅证明对应历史版本。

`iaaps[].place` 已补为可选字符串，支持远程/缓存/包内解析及 Codable 往返，旧配置缺失时仍兼容；当前四页名称为引导页、冷启动、功能拦截、会员页。`type` 仍是入口匹配键。参考项目在运行时用场景名与具体来源组成购买通知文本；KeepUp 本次仅补齐该字段与静态名称，未接入购买通知或来源上报。

## 网络与加解密统一（2026-09-23）

网络传输统一使用 Alamofire 5.12.2（SPM 固定版本），通过 `serializingData().response` 接入 async/await。`HTTPClient` 负责 HTTPS、HTTP 状态、取消与载荷大小检查；IAAP 仍保留 15 秒超时、动态 v 参数、语义校验、历史 SKU 和原子缓存写入。测试可注入 Fetch，显式注入 URLSession 的兼容入口保留，默认生产路径使用 Alamofire。

`JSONPayloadCodec` 兼容 QuitSmoke 的 `_xb_encrypted` JSON 外层、Base64 和 RSA PKCS#1 v1.5 分块格式；SwiftyRSA 1.8.0（SPM 固定版本）完成 RSA 分块运算，与 QuitSmoke 统一使用该库。共用旧协议密钥沿用 QuitSmoke，独立封装在 LegacyRSAKeys，未改动 KeepUp 的地址、商品和应用标识。客户端携带的旧协议密钥用于兼容，不作为服务端身份认证或配置签名；传输仍要求 HTTPS。

远程 IAAP、包内 IAAP 和 BundledJSON 使用相同的明文/密文解码入口。外层出现 `_xb_encrypted` 但类型、Base64、块长度或解密失败时直接报错，不尝试按明文解析；请求要求加密时，加密失败不会发送请求。远程配置解密失败保留最后有效配置与磁盘缓存。有效配置缓存仍为原有的明文结构，不做缓存格式迁移；未转换现有包内资源或发布远程配置。

验证：iPhone 17 Pro / iOS 26.5 模拟器完整 KeepUpTests 通过（275 项 Swift Testing + 9 项 XCTest）。新增 8 项测试覆盖明文与多块中文密文、畸形外层、错误密钥、加密失败不发请求、请求加密与响应解密、HTTP/HTTPS/大小限制、IAAP 密文与缓存回退、独立 OpenSSL 兼容样本以及包内 JSON 解密。配置资源校验与 git diff --check 通过。日志：`.build/network-ios-tests-final.log`。

切换至 SwiftyRSA 1.8.0 后重新执行上述完整测试，全部通过；真机目标 Release 无签名构建通过，日志 `.build/network-release-build.log`。未执行归档或上传。


2026-09-23 01:18（北京时间）真实 OSS 密文验收：对 Info.plist 配置地址带动态 v 下载，HTTP 200、AliyunOSS、4550 字节，外层仅 `_xb_encrypted`。iOS 模拟器通过现有 Alamofire + SwiftyRSA 链路成功解密并校验 4 个 SKU 与 `guide / launch / limited / vip` 四页；Store.refresh() 返回 source=remote、无错误并写入缓存，重新创建 Store 后 source=cache 且配置一致。验证日志 `.build/oss-encrypted-ios-verification.log`。此结果更新前文“尚未由本会话发布”的历史状态：远端四页密文当前已可用，本次仅执行读取验证，没有上传修改。
