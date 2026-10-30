import SwiftUI

struct StoreBadge: View {
    let storeName: String

    var color: Color {
        switch storeName.lowercased() {
        case let s where s.contains("cisalfa"):
            return .red
        case let s where s.contains("maxi"):
            return .orange
        case let s where s.contains("mister"):
            return .blue
        case let s where s.contains("nencini"):
            return .green
        default:
            return .purple
        }
    }

    var body: some View {
        Text(storeName)
            .font(.system(size: 11, weight: .bold))
            .foregroundColor(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.85))
            .cornerRadius(6)
    }
}

struct DiscountBadge: View {
    let discountText: String

    var body: some View {
        Text(discountText)
            .font(.system(size: 11, weight: .bold))
            .foregroundColor(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color.red)
            .cornerRadius(6)
    }
}

struct BestPriceBadge: View {
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 10))
            Text("MIGLIOR PREZZO")
                .font(.system(size: 10, weight: .heavy))
        }
        .foregroundColor(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.green)
        .cornerRadius(6)
    }
}

struct SizeChip: View {
    let size: String
    let isSelected: Bool

    var body: some View {
        Text(size)
            .font(.system(size: 13, weight: isSelected ? .bold : .medium))
            .foregroundColor(isSelected ? .white : .primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isSelected ? Color.blue : Color(.systemGray6))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 1.5)
            )
    }
}
