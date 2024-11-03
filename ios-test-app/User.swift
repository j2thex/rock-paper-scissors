import Foundation

struct User: Codable {
    let id: String
    var name: String
    var wins: Int
    var losses: Int
    var draws: Int
    
    var winRate: Double {
        let total = Double(wins + losses)
        return total > 0 ? (Double(wins) / total) * 100 : 0
    }
} 