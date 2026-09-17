# KeepUp 建议架构

日期：2026-09-16。本文是整体实现方案；已落地部分见[工程基础进度](foundation-status.md)，不能将下列候选模块视为全部已完成。

## 1. 客户端

- 使用 Swift 6 语言模式、SwiftUI 和 Observation；Deployment Target 为 iOS 26.0。
- 页面状态在 MainActor 更新；打卡规则、统计、模型转换与数据库访问不放在 View 中。
- 简单页面用局部 State，复杂流程再使用 Observable 状态模型；不强制一屏一层层包装。
- 页面导航使用 NavigationStack；底栏按 PunchCard 的“时间线—中间日历/打卡—我的”自定义实现；弹层保留原版数字键盘结构。
- 原项目的日历、时间线、我的和打卡入口作为 UI 基准；直接复用原图，按原版层级、尺寸比例与颜色实现。
- iOS 26 适配以保持原版 UI 为前提，不用系统浮动 TabView 或通用卡片替换原版界面。
- 编译 SDK 与最低系统分开管理。本机当前 Xcode 27 / SDK 27，不得无保护地使用 iOS 27 专属 API。

## 2. 模块边界

建议正式工程按目录组织，暂不把每个模块拆成独立 Package。

| 模块 | 职责 |
| --- | --- |
| App | 启动、依赖组装、主导航、生命周期 |
| Features/Calendar | 日历、日期选择、当天卡片 |
| Features/CheckIn | 卡片目录、普通/补打卡、自定义卡、目标、日程 |
| Features/Activity | 步数、室内外跑步、骑行、运动设置 |
| Features/History | 时间线、详情、附加文字照片、统计和分享 |
| Features/Profile | 资料、主题、提醒、设置 |
| Features/Membership | 会员页面和权益展示 |
| Domain | 值类型、日期归属、完成状态和统计等纯业务规则 |
| Data | WCDB、表结构升级、预置数据、附件文件与数据访问接口 |
| Services | CloudKit、StoreKit、通知、定位、计步、JSON 配置读取、广告和统计 |
| Resources | String Catalog、图片、主题、配置资源 |

依赖方向：页面 → 页面状态/业务服务 → 数据访问接口 → WCDB。
当前页面只从本地读取数据；云同步服务在后续阶段再实现。

## 3. WCDB 使用边界

1. WCDB 数据库实例封装在存储 actor 内，对外只传 Sendable 的值类型。
2. 模型绑定初始化和建表统一串行完成，然后开放业务读写。原型已发现多 store 并行首次初始化绑定时出现重复主键约束，详见验证报告。
3. WCDB 是同步 I/O；actor 隔离保证访问边界，不会自动把阻塞 I/O 变成异步 I/O。大量轨迹/附件处理应拆批，并按性能结果考虑专用串行执行器。
4. 关联的本地业务写入使用事务保持一致；当前不引入待同步队列。
5. 开始只保留一个业务数据库。原项目的 FMDB 配置与 Realm 用户数据不要求继续用两套数据库。
6. 数据库结构有明确版本。新增可空字段可利用 WCDB 的支持，但改名、类型变化、约束变化、重构关联需显式迁移。
7. 不使用 `@unchecked Sendable` 把整个 Database 强行跨 actor 共享。原型只对 WCDB ORM 静态绑定使用局部 `nonisolated(unsafe)`，并用初始化锁限制实际访问。

## 4. 建议数据模型

最终字段在功能行为验收后确定；不要直接复制 Realm 的对象继承结构。

| 实体 | 内容 | 要点 |
| --- | --- | --- |
| CardDefinition | 预置卡、自定义卡、类型、单位和图标引用 | 预置名称存本地化标识，自定义名称存用户原文 |
| CheckIn | 一次记录、完成状态、发生时间、归属日期、补录信息 | 稳定 UUID；索引覆盖日期和卡片查询 |
| Goal | 常驻、每周次数、计步目标等 | 目标修改不重写历史记录 |
| Schedule | 待办日期与描述 | 与打卡完成记录的关联显式建模 |
| Reminder | 时间与星期规则 | 明确跟随当地时间的行为；系统通知标识不作为云端业务主键 |
| StepSummary | 日步数及派生结果 | 多设备传感器来源与去重规则需单独验证 |
| Workout / WorkoutSegment | 运动类型、状态、时间、距离、配速、分段 | 未完成运动可恢复；持续记录与结果统计分开 |
| WeightEntry / WeightGoal | 体重与目标 | 内部标准单位，显示时换算 |
| EntryNote / Attachment | 文字、照片与附件引用 | 大图片和轨迹数据避免反复更新为一个巨大记录 |
| UserProfile / ThemeSelection | 个人资料、主题选择 | 不继承旧账号/Keychain；购买权益不信任资料字段 |

上述为本地模型候选；同步队列和同步元数据在后续接入云服务时再设计，不加入当前阶段。

预置卡数据当前为 46 条，包括模板；主题配置 14 条。首版需保留对应产品能力，但复用原版图片和主题资源；中文文案对应原版，英文文案进行本地化适配。

## 5. 云同步延后

用户已明确：前期开发直接存 WCDB，不把 CloudKit 作为前置条件。

- 当前只实现本地数据库、附件保存和页面刷新，不创建云容器、不注册 CKSyncEngine、不实现同步队列。
- 数据访问集中封装，使用稳定 ID；这是正常本地工程设计，无需提前构建完整同步协议。
- 后续进入云服务阶段再接 CloudKit，届时处理账号隔离、上传下载、删除与冲突。
- 已完成的 CKRecord 本地映射验证仅作参考，不继续开展云同步验证，也不阻塞本地开发。

## 6. 全球化规则

- 开发语言英文，首发 `en` 与 `zh-Hans`，使用 `.xcstrings`；用户内容不自动翻译。
- 语言、地区、时区与商店分别处理，不能通过中文语言判断用户在中国，也不能据此选择广告服务。
- 建议记录 UTC 时间戳、当时 IANA 时区、固定归属日键；补打卡另存真实录入时间。
- 建议历史记录归属日不随旅行重分配；这是待以样例验收的业务规则，不是数据库自动决定的行为。
- 展示使用系统地区格式；业务日键采用稳定规则，不用本地化字符串作为标识。
- 跨天按 Calendar 计算，不使用固定 86400 秒代表所有自然日；测试夏令时、跨年和周起始日。
- 内部统一米、千克、秒等单位，展示按地区/设置换算；转换后不反写损失精度的显示值。
- 价格使用 StoreKit 本地化值，不把币种或价格字符串写死。
- 自定义卡名称按字符和布局能力设计限制，取代“5 汉字/10 字母”的旧限制。
- 语音提示、权限说明、预置卡描述、主题描述、分享图、协议与客服页面都在本地化范围内。

远程配置只是一份 JSON：URLSession 下载、Codable 解析、校验后替换本地缓存，失败使用缓存或随包默认值。接入时配置独立 URL，不为它引入后端架构。

计步具体采用 CM 还是 HealthKit，遵循[计步评估](step-counting.md)。用户已明确：如果 HealthKit 满足实时体验，可以替换 CM；不以旧项目依赖作为选择理由。

## 7. 开发阶段与完成条件

这些阶段是实现顺序，不缩减首发的完整功能范围。

1. **选型验证（本次已完成）**：源码盘点、决策文档、WCDB 构建/本地读写/事务/升级验证。
2. **工程基础（已完成）**：正式 iPhone 工程、Bundle ID、SwiftUI 导航、中英文资源、存储访问与领域模型；6 张基础卡支持保存、补录、查看和删除。
3. **普通记录闭环**：目录、自定义、打卡、补打卡、目标、待办、日历、时间线、统计、提醒。
4. **运动与内容**：计步、跑步/骑行、体重、照片、主题、分享、个人资料。
5. **服务与发布准备**：云同步、StoreKit、远程配置、海外广告/统计、独立资源配置与完整行为对照。

第 2 阶段已落地，接下来继续第 3 阶段的卡片目录和普通记录能力；所有用户数据落 WCDB。第 5 阶段的云服务和发布配置不阻塞前期开发。

## 官方资料

- [SwiftUI Observation](https://developer.apple.com/documentation/swiftui/managing-model-data-in-your-app)
- [Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass)
- [WCDB](https://github.com/Tencent/wcdb)、[2.1.16 发布说明](https://github.com/Tencent/wcdb/releases/tag/v2.1.16)
- [CKSyncEngine](https://developer.apple.com/documentation/cloudkit/cksyncengine-4b4w9)、[Apple 同步示例](https://github.com/apple/sample-cloudkit-sync-engine)
- [StoreKit](https://developer.apple.com/storekit/)
- [String Catalog](https://developer.apple.com/documentation/xcode/localizing-and-varying-text-with-a-string-catalog)
- [Google Mobile Ads](https://developers.google.com/admob/ios/quick-start)、[UMP](https://developers.google.com/admob/ios/privacy)
