# PersistenceSpike

KeepUp 存储选型验证，非正式 App，也不是完整同步引擎。

## 环境与依赖

- Swift 6 语言模式；iOS 最低 26.0。
- WCDB 固定 2.1.16，传递依赖 SQLCipher 1.4.7，保留 Package.resolved。
- macOS 26 目标仅用于主机快速测试，不表示 KeepUp 支持 Mac。
- 所有测试用随机临时目录，结束后清理；不读取真实用户数据。
- CloudKit 仅构造内存中的 CKRecord 并验证类型接口，不创建容器、不发网络请求。

## 执行

在本目录运行主机测试：

```sh
swift test
```

在已安装的 iOS 26.5 模拟器运行：

```sh
xcodebuild -scheme KeepUpPersistenceSpike \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -derivedDataPath .build/ios-derived test
```

可用 `xcrun simctl list devices available` 找到其他 iOS 26+ 模拟器，并替换 destination。

## 覆盖范围

1. 中英文/Emoji 保存、日期条件查询、SQL 聚合。
2. 业务记录与待同步队列原子提交、主动回滚。
3. 同 ID 更新、删除意图与关闭重开恢复。
4. 32 个并发调用经过存储 actor 后不丢记录。
5. 多个独立 store 同时初始化时不重复注册主键。
6. 人工 V1 表新增可空字段后保留旧数据。
7. CKRecord 本地转换保留 ID、日期、时区、数值和文字，缺少必需字段时拒绝转换。

## 原型限制

- 表结构仅用于验证；没有所有业务字段、生产约束、附件模型或正式升级版本管理。
- `insertOrReplace` 仅验证原型单表更新，不作为未来有外键/触发器的生产 upsert 实现定案。
- 队列仅验证事务与持久化；没有上传确认序号、冲突合并、账号切换或完整删除协议。
- 不证明真实 CloudKit 同步、GPS、传感器、生产签名、加密恢复或大规模性能。
- 发现 WCDB 延迟初始化绑定存在并行首用问题，使用集中建表锁规避；数据库操作仍在 actor 内。

完整结果见[验证报告](../../docs/persistence-validation.md)。
