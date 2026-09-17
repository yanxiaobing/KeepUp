# 实时计步：Core Motion 与 HealthKit

日期：2026-09-16。

## 用户要求

PunchCard 使用 Core Motion 的原因是实时步数和授权方便。KeepUp 不要求复用这项实现：若 HealthKit 同样满足实时步数体验，可优先采用 HealthKit。

## 核查结论

| 能力 | Core Motion / CMPedometer | HealthKit |
| --- | --- | --- |
| 更新来源 | 设备计步器的持续更新 | 健康数据存储中的样本变化 |
| 前台刷新 | startUpdates 提供持续、best-effort 回调 | Observer Query 提醒数据已变化，再查询统计；依赖来源先把样本写入 HealthKit |
| 严格每秒更新 | 没有此保证 | 也没有此保证；监听变化不等于传感器实时流 |
| 后台 | 不应承诺持续唤醒；恢复前台后的回调可包含后台累计活动 | 后台投递有频率限制；SDK 对 stepCount 注明至少小时级间隔，不是实时通道 |
| 授权 | 运动与健身权限 | 按健康数据类型授权；不能确知用户是否拒绝读取步数 |

**当前建议：保持 CM 作为前台实时计步的优先方案，HealthKit 作为待真机验证的替代方案。** 这来自更新机制与体验要求，不是复用旧代码的考虑。

若后续只要求“打开页面显示健康 App 中的累计步数”，HealthKit 更值得优先考虑；若要求“拿着手机走路时页面持续跟着增长”，不能仅凭 HKObserverQuery 有回调就认定可完全替代 CM。

暂不默认引入 CM + HealthKit 双来源合并。若真机结果要求混用，需要单独确定展示基准和去重，不能将健康总步数直接加上 CM 今日总步数。

## 真机验证清单

1. 同一部 iPhone 并行记录 CM 回调、HealthKit 观察事件及重新查询结果的时间；测量持续走路时的前台更新延迟。
2. 对比停止、恢复、锁屏后返回、跨午夜后的累计值与刷新行为。
3. 比较首次授权流程；HealthKit 请求成功只表示授权流程完成，不能当成读取已获批准。
4. 无可读数据时显示中性状态，不错误宣称“用户已拒绝”或“今天 0 步”。
5. 如设备有其他健康数据来源，核对总量口径；不因此新增 Watch App。

尚未做真机传感器测试，因此不把以上候选定为最终替换决定。

## 依据

- [CMPedometer](https://developer.apple.com/documentation/coremotion/cmpedometer)
- [持续计步更新](https://developer.apple.com/documentation/coremotion/cmpedometer/startupdates(from:withhandler:))
- [HealthKit Observer Queries](https://developer.apple.com/documentation/healthkit/executing-observer-queries)
- [HealthKit 读取权限的隐私设计](https://support.apple.com/en-ca/guide/security/sec88be9900f/web)
- 本机 Xcode 27 iPhoneOS SDK：`HealthKit.framework/Headers/HKHealthStore.h` 的 `HKBackgroundDelivery` 注释，及 `CoreMotion.framework/Headers/CMPedometer.h` 的持续更新注释。

后台小时级投递限制不等于前台也必须等待一小时；前台的关键限制是不能保证健康样本写入与传感器更新同频。
