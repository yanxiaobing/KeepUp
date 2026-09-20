# 跑步地图坐标

GPS 原始数据、数据库和距离计算统一使用 WGS-84。`RunningMapCoordinates.displayCoordinate(forWGS84:)` 仅供地图展示入口调用一次：大陆点转 GCJ-02，其他地区原样返回。不可将其结果回写轨迹或再次转换。

沿用本机 PunchCard `PCRunningCoordinateAdapter` 的展示策略。CLLocation 的 WGS-84 类型定义并不能证明大陆地图底图会自动转换自定义覆盖物。本次移植没有真实设备底图对齐证据；不同地区、网络及地图提供方，尤其边境、海岸、岛屿和跨境桥梁附近，仍需真机核对。区域数据为概化陆地范围，不是米级边界，也不是地图提供方检测器。

## 固定数据和来源

- 区域：Natural Earth v5.1.2，固定版本 `f1890d9f152c896d250a77557a5751a93d494776` 的 `ne_10m_admin_0_countries.geojson`，提取 `ADM0_A3=CHN`。保留原版全部 70 个 polygon/ring、14,118 顶点及七位小数，不做几何简化。港澳台由来源数据单独表达，不纳入本转换范围。数据为 public domain。
- 原始文件 SHA256：`239eec57ac17f100a11e2536cffc56752c318b50ae765b0918ff7aab4ce8f255`。
- 本次直接从本机 PunchCard 的 `CoordinateData/PCMainlandPolygon.inc` 提取顶点及环索引生成 `running-map-region.json`；运行时按整数纬度索引原始边，保留各 polygon 环异或和 polygon 间并集。
- 转换数学：googollee/eviltransform，固定版本 `03ba58d92dfda57f8a1635f3805483c8fc10bd77` 的 `c/transform.c`，BSD-2-Clause。修改为 Swift，仅保留 WGS-84 向 GCJ-02 的展示转换，以完整 polygon 替代矩形推断。
- 完整版权和二进制分发声明随 `running-map-region.json` 的 `notice` 字段打包。

## 自动验证

三个固定外部前向对照值（不是算法自行生成的往返值）；周边国家、港澳台、海南、无效坐标；整数纬度分桶两侧的网格与完整环遍历逐点对照。数值测试不能替代真机地图对齐验收。
