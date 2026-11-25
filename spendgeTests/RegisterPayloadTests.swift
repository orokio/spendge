import XCTest
@testable import spendge

/// 用服务端真实响应结构做契约测试，防止字段改名或类型不一致。
final class RegisterPayloadTests: XCTestCase {
    func testDecodesCategoriesPayload() throws {
        let json = """
        {
          "deviceToken": "opaque",
          "expiresAt": "2027-02-24T00:00:00Z",
          "categoriesVersion": 1,
          "categories": [
            {
              "code": "takeout",
              "name": "点外卖",
              "iconName": "takeoutbag.and.cup.and.straw.fill",
              "colorHex": "#FB923C",
              "kindRawValue": "expense",
              "domainRawValue": "food",
              "scope": "外卖点餐、美团、饿了么",
              "sortOrder": 1,
              "isArchived": false
            }
          ]
        }
        """.data(using: .utf8)!

        let payload = try JSONDecoder().decode(DeviceRegistrar.RegisterResponse.self, from: json)
        XCTAssertEqual(payload.categoriesVersion, 1)
        let item = try XCTUnwrap(payload.categories?.first)
        XCTAssertEqual(item.code, "takeout")
        XCTAssertEqual(item.categoryInfo.name, "点外卖")
        XCTAssertEqual(item.categoryInfo.kind, .expense)
        XCTAssertEqual(item.categoryInfo.domain, .food)
    }

    func testDecodesRenewalWithoutCategories() throws {
        let json = """
        { "expiresAt": "2027-02-24T00:00:00Z" }
        """.data(using: .utf8)!
        let payload = try JSONDecoder().decode(DeviceRegistrar.RegisterResponse.self, from: json)
        XCTAssertNil(payload.categories)
        XCTAssertNil(payload.categoriesVersion)
    }

    func testRemoteCategoryFallsBackForMissingOptionalFields() throws {
        let json = """
        { "code": "custom", "name": "自定义" }
        """.data(using: .utf8)!
        let item = try JSONDecoder().decode(DeviceRegistrar.RemoteCategory.self, from: json)
        XCTAssertEqual(item.categoryInfo.iconName, "tag.fill")
        XCTAssertEqual(item.categoryInfo.colorHex, "#9CA3AF")
        XCTAssertEqual(item.categoryInfo.sortOrder, 99)
        XCTAssertFalse(item.categoryInfo.isArchived)
    }
}
