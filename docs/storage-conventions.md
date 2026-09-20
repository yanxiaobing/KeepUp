# 本地存储封装参考与落地清单

2026-09-20：根据用户要求，学习 QuitSmoke 的 Defaults 和业务 Service，并对照 KeepUp。此文档作为后续落地依据保留，不属于临时产物。

## 参考来源

当前本地 QuitSmoke 未检索到 WCDB 实现；WCDB 参考来自 SmokingCount，不混淆两个项目。

- `/Users/xbingo/Developer/Projects/quit-smoking/QuitSmoke/QuitSmoke/Defaults.swift`：通过 `extension Defaults.Keys` 声明强类型 Key、默认值和 App Group suite；业务使用 `Defaults[.key]`。
- 同项目 `Defaults+App.swift`：App 专用 Key 与 Widget 共享 Key 分开，App 专用 Key 使用默认 suite。
- 同项目 `Module/Models/UserM.swift`、`Module/Models/QuitRecordM.swift`：模型采用 `Codable, Defaults.Serializable`。
- 同项目 `Module/Login/UserService.swift`、`Module/QuitSmoking/QuitRecordService.swift`：按业务组织 Service，集中处理状态判断、清理与记录更新；更新成功后写回 Defaults。
- `/Users/xbingo/Developer/Projects/smoking/SmokingCount/SmokingCount/Common/DBService.swift`：统一数据库路径、监控、建表与 `table(Model.self)` 类型化入口。
- 同项目 `CigModels/CigRecordM.swift`：模型在 extension 中遵循 `TableCodable`，通过 `CodingKeys` 声明字段映射。
- SmokingCount 使用 `SwiftyUserDefaults` 和 `Defaults[\.key]`；QuitSmoke 使用 `Defaults` 和 `Defaults[.key]`。两者不是同一个库，不混用接口。

## 已确认的问题

1. KeepUp 的 `CalendarTheme.swift` 直接访问 `UserDefaults.standard`，其他页面使用字符串 `@AppStorage`，`KeepUpApp.swift` 又重复列出重置 Key。读写、默认值和重置入口需要统一。
2. `LocalStore.swift` 重复书写数据库表名和 JSON 编解码，同时承载档案、体重、计划、内容、自定义卡片等业务。需要收拢重复部分，并评估职责划分。
3. `DatabaseRows.swift` 集中定义映射和 schema，但模型与表名的对应关系未形成统一的访问入口。

## 落地顺序与验收

### 一、统一偏好设置

- [x] 核对现有依赖、部署版本与 Defaults 的 SwiftUI 观察和绑定能力；固定到 QuitSmoke 已使用的 Defaults revision `00a7465a0668a87fa159e779b9d80f1f9652357e`，使用 `@Default`。
- [x] 在 `KeepUp/Defaults.swift` 集中声明强类型 Key、默认值和存储范围。
- [x] 统一语言、日历模式、主题的读取、写入、观察与重置入口。
- [x] 保留原 standard suite；因 Defaults 观察不支持含点号的 Key，将 `preference.monthMode`、`preference.themeID` 迁移至 `monthMode`、`themeID`，语言 Key 不变。验证旧值、页面刷新、重启与重置。

App Group 仅在实际需要跨 Target 共享时配置，不能复制参考项目的 group ID。

### 二、收拢 WCDB 公共访问

- [x] 在 `StoreTables.swift` 统一模型与表名，查询通过 `database.table(StoreTables.xxx)`。事务内继续使用原 handle，并引用统一表名。
- [x] 使用 `StoredJSON` 收拢存储编解码，继续向调用方抛出原始错误。
- [x] 保持数据库路径、表名、字段、schema 版本与数据语义。
- [x] 现有存储测试通过，覆盖 schema 1/2/5 升级、重开读取、并发写入、体重联动、内容发布删除与计划完成等行为。

SmokingCount 根据类型名生成表名的规则不能直接套用到 KeepUp 已有数据库。其 `try?`、可选数据库访问，以及迁移后清空旧数据的写法也不直接照搬。

### 三、按实际职责评估业务拆分

- [x] 将现有扩展按卡片与内容、计划、体重拆到 `LocalStore+*.swift`；核心生命周期、快照和跨业务入口保留在 `LocalStore`。没有额外引入 Service 层。
- [x] 拆分后仍属于同一 actor，保留事务边界、错误传递和 schema 版本保护；数据库属性仅可由主体修改。

代码长、存在 Row 层或 JSON 字段，本身不构成重构理由。是否让业务模型直接遵循 `TableCodable`，取决于业务类型与表结构是否一致；需要查询和索引的字段再评估列映射。避免为了形式一致机械删除 Row 层或新增通用抽象。

## 当前状态

已完成代码调整与验证（iPhone 17 Pro / iOS 26.5 模拟器）：

- 全部 36 项单元测试通过，包括新增的旧偏好迁移、已有新值保护、重复迁移、重置及重开读取测试。
- 语言切换、日历模式与补签、主题预览和会员门槛共 3 项 UI 测试通过；语言测试增加了退出重启后仍保留选择的断言，并重新通过。
- 工程引用、entitlements、生成脚本语法及 diff 空白检查通过。
- 已提交：`c428f30`。后续计步和跑步存储继续沿用本笔记中的表注册、编解码和 actor 事务约定。

偏好迁移只检查 persistent domain，避免注册的默认值被误认为已保存的用户选择；已有新值优先，迁移后删除旧 Key，重复运行不会覆盖设置或使重置后的值复活。

App Group `group.com.bestlife.keepup` 已配置 entitlement 和工程 capability，生成脚本同步维护。此次尚未将偏好或数据库移入共享容器；Apple 后台注册与真机签名未验证。
