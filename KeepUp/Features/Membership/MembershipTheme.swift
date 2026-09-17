import SwiftUI
struct MembershipTheme: Identifiable {
    let id: Int; let name: String; let english: String; let image: String; let hex: UInt32
    static let all: [Self] = [
        .init(id: 1, name: "北京", english: "Beijing", image: "calendar_city_beijing", hex: 0xaae6f0),
        .init(id: 2, name: "青岛", english: "Qingdao", image: "calendar_city_qingdao", hex: 0xcdeeff),
        .init(id: 3, name: "上海", english: "Shanghai", image: "calendar_city_shanghai", hex: 0x8fa7d6),
        .init(id: 4, name: "武汉", english: "Wuhan", image: "calendar_city_wuhan", hex: 0xf7d8cb),
        .init(id: 5, name: "台北", english: "Taipei", image: "calendar_city_taibei", hex: 0xe0f0e7),
        .init(id: 6, name: "广州", english: "Guangzhou", image: "calendar_city_guangzhou", hex: 0x2ad3d5),
        .init(id: 7, name: "重庆", english: "Chongqing", image: "calendar_city_chongqing", hex: 0xe29256),
        .init(id: 8, name: "泸沽湖", english: "LuguLake", image: "calendar_city_lijiang", hex: 0x3c9688),
        .init(id: 9, name: "拉萨", english: "Lhasa", image: "calendar_city_lasa", hex: 0xdff1fb),
        .init(id: 10, name: "乌鲁木齐", english: "Urumqi", image: "calendar_city_wulumuqi", hex: 0xf1c962),
        .init(id: 11, name: "西宁", english: "Sining", image: "calendar_city_xining", hex: 0xf1e9ba),
        .init(id: 12, name: "呼和浩特", english: "Hohhot", image: "calendar_city_huhehaote", hex: 0xb7dc82),
        .init(id: 13, name: "沈阳", english: "Shenyang", image: "calendar_city_shenyang", hex: 0x8dddfb),
    ]
}
