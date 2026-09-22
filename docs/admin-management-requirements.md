# KeepUp 后台管理需求（交接 apps-admin）

日期：2026-09-22。本文是待实现需求，不代表功能已完成。

## 目标和范围

在现有 apps-admin 新增独立的 KeepUp 项目，统一维护会员商品、会员展示页面、广告与激励相关的 IAAP 配置，并支持通过 Cloudflare 向 KeepUp 客户端下发版本化配置。

本期包含项目注册、配置编辑与校验、环境隔离、配置下发和发布结果核验。不需要新增用户列表、运动数据、记步记录、排行榜或用户权益手工发放后台。用户运动数据目前仍由客户端管理。

分两步交付：

1. 后台项目和 IAAP 配置维护，可以独立完成验收。
2. Cloudflare 下发和客户端联调，必须单独报告完成状态；只保存 MongoDB 不等于 App 已生效。

## 一、项目入口与隔离

- 项目 key 固定为 `keepup`，显示名为 `KeepUp`。
- 菜单增加“KeepUp / 项目概览”和“KeepUp / IAAP 配置”。
- 页面路径：`/projects/keepup`、`/projects/keepup/iaap`。
- 复用现有项目概览、版本列表和 JSON 编辑器，无需复制一套戒烟业务页面。
- 纳入现有项目级正式写权限管理，默认只读；不能依赖开启全局正式写权限。
- 测试与正式配置、下发目标和发布凭据隔离；KeepUp 与其他项目的数据隔离。
- 初始化可重复执行，不覆盖已有配置，不修改戒烟项目的记录。若 KeepUp 没有独立数据库，可在后台数据库使用独立集合；最终集合与连接方式写入实现文档。

## 二、IAAP 配置维护

沿用现有版本维护体验：

- 按 App 版本列出配置，版本按数字比较倒序排列。
- 选择版本查看、编辑、保存完整 JSON；支持从已有版本复制新版本。
- 默认复制比新版本低且最接近的版本，也允许自行选择来源。
- JSON 树与源码编辑都应保留未知字段，不能因编辑器不认识字段而丢失内容。
- 保存前提示准确的字段错误；失败保留编辑内容，成功刷新最后更新时间。
- 切换项目或版本时，未保存内容需提醒；旧异步请求不能覆盖当前选择。
- 并发编辑须检测冲突，例如提交读取时的 revision，不静默覆盖其他人的更新。

管理接口沿用现有风格：

| 接口 | 请求 | 返回内容 |
| --- | --- | --- |
| `POST /api/admin/projects/keepup/iaap/list` | 空对象 | 版本、更新时间、revision |
| `POST /api/admin/projects/keepup/iaap/detail` | `version` | version、config、updatedAt、revision |
| `POST /api/admin/projects/keepup/iaap/save` | version、config、预期 revision（新增时为空） | 保存后的完整记录 |

响应封装、错误码、鉴权沿用 apps-admin。配置内容和管理元数据分开存储，版本唯一。保存操作记录项目、环境、版本、前后 revision 及结果，遵循已有审计机制。

## 三、配置协议

参考最新代码而非旧文档中的 `products` 示例：

- QuitSmoke：`/Users/xbingo/Developer/Projects/quit-smoking/QuitSmoke/QuitSmoke/Iaap/IaapConfigsM.swift`。
- KeepUp 现有会员配置：`KeepUp/Resources/membership.json`。
- KeepUp 当前解析与购买代码：`KeepUp/Features/Membership/MembershipStore.swift`。

业务配置顶层采用 `system`、`ads`、`skus`、`iaaps`。以下仅是可保存的安全空模板，不是可启用商业化的正式配置：

```json
{
  "system": {},
  "ads": {},
  "skus": [],
  "iaaps": []
}
```

### 商品与会员页面

- `skus` 是唯一商品目录，使用 QuitSmoke 的 `pid`、`type`、`titleType`、`desc` 字段。
- `type` 沿用 `lifetime`、`subscribe`、`consumable`；类型必须与 App Store 商品类型匹配。
- `titleType` 沿用 `timer`、`desc`、`appstoreDesc`。
- `iaaps` 使用页面 `type` 区分入口，通过 `iap.pids` 引用目录中的商品；商品不能在不同页面重复定义不同属性。
- 支持维护既有页面字段：`closeAlpha`、`priceAlpha`、`hideFuncBtn`、`showGiveUp`、`benefits`、`iap`、`reward`、`operateText`。
- KeepUp 的页面入口和权益枚举由客户端支持范围决定；不能直接照搬戒烟专属的 `quit_now`、`firekeeper` 等入口或权益。
- 商品价格、币种、订阅周期和优惠资格以 StoreKit 返回值为准，后台描述不能替代真实交易信息。
- 商品停售与历史购买权益识别要分开处理：隐藏销售入口不能撤销已购用户的权益。具体历史商品识别由客户端实现。

KeepUp 当前本地商品 ID 如下，均仅为待核实候选，不代表已在 App Store Connect 建立：

- `com.bestlife.keepup.premium.lifetime`
- `com.bestlife.keepup.premium.year`
- `com.bestlife.keepup.premium.quarter`
- `com.bestlife.keepup.premium.month`

不能复用 QuitSmoke 的商品 ID。实际商品组合、定价及权益清单未最终确认，后台能力可先完成，正式配置不能假定已经确认。

### 广告与激励

- `ads` 参考 QuitSmoke 的广告位结构，支持大陆/海外广告位配置与自动加载等已有字段；仅启用 KeepUp 已接入的位置。
- 广告平台 App ID 与广告单元 ID 分开记录和校验，不能互相替代。
- KeepUp 使用独立的广告应用和广告位，不能直接复制戒烟项目的正式 ID。
- 支持关闭广告位；没有有效 ID 时客户端跳过加载。空模板不得触发广告。
- 页面 `reward` 可沿用现有 `rewardId`、`insertId`、`count`、`hideGiveUpWhenNoAd` 结构。`count` 的单位和作用需与 KeepUp 客户端约定后才能发布非空奖励配置，不能凭字段名推定发放次数。
- 奖励内容、有效期、使用次数等若需新增字段，应先形成客户端可解码的协议，再开放正式发布。
- 后台配置只描述规则，不能证明广告观看成功或直接授予会员。奖励以 SDK 成功回调或接入后的服务端验证为准，发放须防重复；播放失败、取消不得误发奖励。
- 无广告或加载失败必须能退出，不能把用户困在商业化页面。

### 校验要求

保存时校验 JSON 顶层为对象、四个主字段类型、版本格式、商品 ID 唯一、页面类型唯一、`iap.pids` 引用存在、透明度在 0～1 范围、时间间隔为正数以及奖励数值符合约定。错误信息带字段路径。

编辑草稿允许尚未填写真实商品和广告位的空模板；正式下发前还需检查已启用功能引用完整、客户端支持对应协议。不要将未知扩展字段静默删除，也不要把 QuitSmoke 专属枚举自动当成 KeepUp 已支持。

## 四、Cloudflare 下发

目标链路：`apps-admin 编辑保存 → 发布指定 revision → Cloudflare HTTPS → KeepUp 拉取校验 → 缓存并应用`。

- 后台数据库是编辑源，Cloudflare 是分发端。可用 Worker + KV 或版本化静态 JSON，依据已有基础设施选定方案并记录。
- 本期 KeepUp 不要求建立完整业务服务器，也不复用戒烟服务端的加密协议和密钥。公开配置不存放任何服务端密钥、广告平台管理凭据或交易票据。
- 保存不自动影响线上；提供 KeepUp 的显式发布操作，展示待发布版本、revision、目标环境及与线上配置的差异。不要改变其他项目现有的直接保存流程。
- 发布成功须读取分发地址核验 revision 和内容摘要；超时或结果不明确显示待核验，不能误报成功或盲目重复发布。
- 发布失败保留上一份可用线上配置；支持重新发布历史成功 revision 进行回滚，保留发布记录。
- 生产发布受 KeepUp 项目写权限和环境检查保护。Cloudflare 凭据仅保存在服务端配置中，不发给管理前端或 App。

建议固定读取协议如下，实际域名和路径由实现方提供给 KeepUp：

```text
GET https://<配置域名>/keepup/<test或production>/iaap/<App版本>.json
```

```json
{
  "schemaVersion": 1,
  "appVersion": "1.0.0",
  "revision": "<不可变版本标识>",
  "config": {
    "system": {},
    "ads": {},
    "skus": [],
    "iaaps": []
  }
}
```

`1.0.0` 仅为协议示例。读取精确 App 版本，不自动回退到任意最新版本；不存在返回明确 404。配置响应使用 JSON Content-Type、ETag 和明确的缓存策略，支持条件请求。实现方须说明 CDN/存储传播延迟及生效时间，不能承诺保存即全网生效。

客户端由 KeepUp 项目实现：远程配置校验成功后完整替换；网络失败、超时、404、JSON 损坏或 schema 不支持时依次使用当前 App 版本的最近有效缓存、包内默认配置。不同环境和 App 版本不得共用错误缓存，不能因配置加载失败阻塞启动、已有权益或恢复购买。

## 五、协作边界和待确认项

apps-admin 负责后台管理、存储、校验、发布与分发端验证，并交付接口协议、初始配置、环境地址和联调说明。

KeepUp 负责配置模型与远程加载、缓存兜底、StoreKit 商品加载及交易监听、购买和恢复、权益联动、广告 SDK 及激励发放。后台完成不能替代真实交易或广告验收。

以下业务决定尚未确认，不阻塞后台基础功能：

1. 广告采用大陆穿山甲＋海外 AdMob，还是仅 AdMob。
2. 最终商品组合、价格、订阅周期和会员权益；是否参考 QuitSmoke 方案。
3. 激励解锁的具体功能、次数和有效期。
4. Cloudflare 最终账号、分发域名和部署资源；此前会话登录已过期，实施时重新核验登录状态。

Chrome 已登录部分商业化平台不代表 KeepUp 应用、商品和广告位已经创建或通过审核。缺少凭据时可以先交付完整后台能力及测试适配，不应填入其他 App 的正式配置冒充完成。

## 六、验收清单

### 后台独立交付

- KeepUp 出现在侧栏和项目列表，两个页面可打开。
- 可新增、复制、编辑、保存和重新读取版本，刷新页面或服务重启后数据仍在。
- JSON 树/源码切换保留字段，非法引用等错误可定位，并发保存冲突有明确提示。
- 测试与正式、KeepUp 与其他项目互不影响；正式默认只读，开启 KeepUp 权限不扩大其他项目权限。
- 初始化重复执行不覆盖已有数据；保留项目已有未提交修改。
- 针对新增行为完成接口测试和前后端构建，并报告实际结果。

### 下发与联调交付

- 测试环境完成保存、发布、分发读取及 revision/摘要一致性验证。
- 验证发布失败保留旧配置、历史回滚、未知 App 版本、缓存更新和重复发布处理。
- KeepUp 客户端分别验证远程成功、离线缓存、首次离线包内兜底、配置损坏和不兼容 schema。
- 真正商业化启用前，另行完成沙盒购买/恢复/到期或撤销权益，以及广告成功/失败/取消/重复回调的联调。
- 交付时分别列出“后台已完成”“Cloudflare 已完成”“客户端待联调”和实际阻塞项，不笼统宣称全部完成。
