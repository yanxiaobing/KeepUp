# 资料填写与会员墙还原

## 入口

- 新安装：资料填写 → 确认无误 → 会员引导 → 放弃优惠继续 → 日历。
- 已有资料：我的 → 头像，或设置 → 设置资料，进入个人信息列表逐项编辑。
- 会员墙：我的 → 高级版。

## 原版对照

资料：`PunchCard/Module/UserInfo`；会员：`PunchCard/Module/Iaap`。
固定尺寸沿用原版 375 点基准，乘以当前屏宽 / 375。资料页使用实际 safe area；会员导航按原版 statusBarFrame 定位，避免两者在灵动岛设备上的高度差。

本轮新增资源记录于 `punchcard-resource-manifest.json`。全部 291 个 imageset / 678 个资源文件的 SHA-256 与原版一致。裁剪组件通过官方 SPM 包 TOCropViewController 3.2.0 接入，固定版本并使用包自带的本地化资源；保留原版正方形裁剪配置。

裁剪采用官方在 iOS 26 上的玻璃工具栏与图标按钮；资料页和会员墙继续按 PunchCard 还原。项目中不保留裁剪库源码副本或 Objective-C 桥接头。

## 本地存储与边界

资料在 WCDB profile 表保存；schema 3 继续保留原打卡数据和本地资料。头像压缩为 512×512 JPEG，昵称限制七个 UTF-16 单元并保留完整字形、兼容中文输入法组字。

会员价格使用 StoreKit 产品信息。JSON 中的 KeepUp 产品 ID 是预留值，需要在自己的 App Store Connect 配置；当前未完成真实内购和恢复的沙盒交易验收。UI 测试不请求 App Store，测试缺失商品提示与关闭，不模拟付费成功。CloudKit 仍未接入。

## 参考运行

`.build/ReferenceUIHarness` 是原版源码副本，仅增加资料页面的直接启动入口，方便同机型对照；未修改 PunchCard 工作区。参考机与 KeepUp 均为 iPhone 17 Pro / iOS 26.5。

截图位于 `.build/ui-review`：`Reference-` 是原版，`KeepUp-Profile-` / `KeepUp-Membership-` 是本轮 KeepUp。动态时间、商品价格、已选择的资料值不作静态像素相等要求。

## 验证范围

- WCDB 与业务：12 个测试函数通过（其中数值校验包含 5 组参数），含资料重启读回、非法修改保护，以及 schema 1 升级后保留打卡记录。
- 既有日历、补打卡、语言切换、重启与删除、大字号等 4 条 UI 回归通过。上述结果位于 `.build/ProfileMembershipFifth.xcresult` 的业务测试和 `KeepUpUITests` 测试组；该早期结果包整体并非全部通过。
- 中英文资料填写、标尺、确认、会员引导、普通会员墙关闭、取消编辑，以及相册选图与裁剪 4 条流程在 `.build/ProfileMembershipAcceptance.xcresult` 全部通过。
- 官方 SPM 3.2.0 的最新回归：以上 4 条流程全部通过，结果为 `.build/ProfileMembershipSPM320.xcresult`；裁剪采用 iOS 26 玻璃工具栏，图标按钮补齐中英文辅助功能标签。最新截图已导出至 `.build/ui-review/KeepUp-*.png`。
- 215 个本地化条目校验通过；678 个资源文件与原版 SHA-256 一致。
- 同尺寸资料第二页截图抽查：两处插画区域平均 RGB 通道差约为 0.24 / 255、0.20 / 255。此结果仅对应抽查区域，不代表整页逐像素完全相等。
- 真机相机、原始 iOS 26.0 系统，以及真实商品购买/恢复尚未验收。
