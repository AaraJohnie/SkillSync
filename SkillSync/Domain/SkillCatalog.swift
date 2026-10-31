import Foundation

enum SkillCatalog {
    static let all: [CatalogSkill] = [
        .init(name: "Swift", category: .mobile),
        .init(name: "SwiftUI", category: .mobile),
        .init(name: "UIKit", category: .mobile),
        .init(name: "ARKit", category: .mobile),
        .init(name: "Firebase", category: .backend),
        .init(name: "Node.js", category: .backend),
        .init(name: "Python", category: .data),
        .init(name: "APIs", category: .backend),
        .init(name: "Figma", category: .design),
        .init(name: "UI/UX", category: .design),
        .init(name: "Product Design", category: .product),
        .init(name: "Illustration", category: .creative),
        .init(name: "Motion", category: .creative),
        .init(name: "Copywriting", category: .creative),
        .init(name: "Video", category: .creative),
        .init(name: "Machine Learning", category: .data),
        .init(name: "Product Strategy", category: .product)
    ]

    static func category(for name: String) -> SkillCategory {
        all.first { $0.name == name }?.category ?? .product
    }

    static func grouped() -> [(SkillCategory, [CatalogSkill])] {
        SkillCategory.allCases.compactMap { category in
            let skills = all.filter { $0.category == category }
            return skills.isEmpty ? nil : (category, skills)
        }
    }
}

enum GapAnalyzer {
    static func missing(required: [String], owned: [UserSkill]) -> [String] {
        let have = Set(owned.map(\.name))
        return required.filter { !have.contains($0) }
    }

    static func covering(required: [String], owned: [UserSkill]) -> [UserSkill] {
        let need = Set(required)
        return owned.filter { need.contains($0.name) }
    }
}

enum StudentVerification {
    static func isVerified(email: String) -> Bool {
        let lowered = email.lowercased()
        let known = ["edu", "ac.uk", "edu.au", "ac.in"]
        if known.contains(where: { lowered.hasSuffix(".\($0)") }) { return true }
        let campus = ["university", "college", "campus", "student"]
        return campus.contains { lowered.contains($0) }
    }
}
