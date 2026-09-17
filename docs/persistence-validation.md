# WCDB 与 CloudKit 接入验证报告

日期：2026-09-16。

## 结论

**WCDB 已确定用于 KeepUp 前期本地开发：Swift 6 编译及 iOS 26.5 模拟器上的 7 项本地验证通过。** 采用集中模型初始化和存储 actor，避免多个入口各自随意建表。

CloudKit 的本地 CKRecord 映射测试和 CKSyncEngine.Configuration API 编译通过，尚未连接独立容器。用户随后明确延后云服务：这些结果只保留作记录，不继续同步验证，不阻塞本地开发。

## 环境与产物

| 项目 | 实际值 |
| --- | --- |
| Xcode | 27.0，27A266a |
| Swift 编译器 | Apple Swift 6.4；项目语言模式为 6 |
| SDK | iOS / iOS Simulator 27.0 |
| 编译最低系统 | iOS 26.0 |
| 测试设备 | iPhone 17 Pro，iOS 26.5 Simulator（23F77），arm64 |
| WCDB | 2.1.16，提交 df808591b9f9a9ab42156006819c3550d5af13a3 |
| SQLCipher | 1.4.7，提交 5d8825c22feedb421ad6f9ecfc1399460e10d299 |
| 主机测试 | 7 通过，0 失败 |
| iOS 模拟器测试 | 7 通过，0 失败，0 跳过 |

原型：[Prototypes/PersistenceSpike](../Prototypes/PersistenceSpike/README.md)。依赖锁定：[Package.resolved](../Prototypes/PersistenceSpike/Package.resolved)。

本次本地证据（构建产物已 gitignore）：

- `Prototypes/PersistenceSpike/host-test.log`
- `Prototypes/PersistenceSpike/ios-test.log`
- `Prototypes/PersistenceSpike/.build/ios-tests.xcresult`

XCResult 摘要确认运行系统为 26.5；不是仅用 iOS 27 SDK 编译后就推断兼容 iOS 26。尚未验证 iOS 26.0 初始版本或物理 iPhone。

## 测试内容

| 测试 | 验证点 | 结果 |
| --- | --- | --- |
| unicodeDateQueryAndSQLAggregation | 中英文/Emoji、时区字符串保存；按日期过滤后数值求和，不混入其他日期 | 通过 |
| transactionRollsBackRecordAndQueueTogether | 在写记录后、写队列前主动回滚，两个表都不留下半成品 | 通过 |
| updatesDeletionAndQueueSurviveReopen | 同 ID 更新不重复，删除持久化待处理操作，数据库重开保留结果 | 通过 |
| concurrentCallersDoNotLoseWrites | 32 个异步调用经 actor 进入数据库，记录与队列均完整 | 通过 |
| concurrentStoreInitializationDoesNotDuplicateConstraints | 16 个独立 store 并行初始化，集中建表避免重复约束 | 通过 |
| addingOptionalColumnPreservesOldRows | 人工旧 schema 增加可空 note 列，保留旧值并允许新写入 | 通过 |
| cloudRecordRoundTripIsLocalAndPreservesIdentity | 内存 CKRecord 与值模型转换、必需字段校验 | 通过 |

## 验证中发现的问题

### 1. 模型绑定并行首用

初始并行测试出现 `table check_ins has more than one primary key`，生成 SQL 中主键声明重复。核查 WCDB 2.1.16 `src/swift/core/binding/TableBinding.swift`，发现 `innerBinding` 使用未加同步保护的 lazy 初始化，并在其中应用列约束。

原型通过单一 SchemaBootstrap 锁串行建表，避免不同 store 同时首次配置同一个静态绑定。之后并行测试及 iOS 模拟器测试通过。没有修改上游依赖源码，也没有通过关闭 Swift 6 检查或把全部测试串行化掩盖问题。

这验证的是当前模型/使用路径的规避方式，不是 WCDB 所有 ORM 并发行为都已验证。正式工程集中初始化后再开放数据库服务，继续通过 actor 限制访问。

### 2. 事务闭包的错误传播

普通 `run(transaction:)` 会捕获闭包中的 Swift 错误，再抛出数据库错误；人工注入的业务错误可能显示成之前的数据库诊断。原型改用 `run(controllableTransaction:)` 的布尔结果表达主动回滚，并在返回后抛出测试错误。

正式封装应明确区分业务主动取消与数据库失败，不依赖 WCDB 保留任意 Swift 错误类型。

### 3. 编译诊断

构建存在上游模块头文件相关警告。原型未全局屏蔽依赖警告；测试成功不表示依赖编译零警告。尚未进行发布归档和包体积评估。

## 留到后续阶段的验证（不阻塞本地开发）

| 项目 | 为什么本次未验证 | 后续验证 |
| --- | --- | --- |
| 实际双设备 CloudKit 同步 | 尚无配置好的 KeepUp 签名工程与独立容器 | 配置后验证首次下载、离线修改、重试、删除和冲突 |
| CKSyncEngine 状态持久化与上传确认 | 当前原型只验证配置 API 与本地待处理表 | 完整实现 stateSerialization、记录系统字段、变更序号及恢复 |
| iCloud 账号切换 | 必须使用真实授权环境 | 确保原账号数据不进入新账号 |
| 大照片与轨迹 | 当前只用少量文本/数值数据 | CKAsset 生命周期、附件清理、分批写入与内存占用 |
| 完整 schema 演进 | 只测试新增可空列 | 重命名、类型/索引变化、迁移失败恢复 |
| 真机运动与最低版本细节 | 模拟器不提供实际计步/GPS行为 | iPhone 上验证定位、CM/HealthKit、后台和语音 |

当前选型验证阶段结束，直接开始 WCDB 本地工程建设。以上云端项目留到后续接入阶段，不要求现在解决。
