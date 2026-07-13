import SwiftUI

enum AccessibleHitTarget {
    static let minimumDimension: CGFloat = 44
}

extension View {
    @ViewBuilder
    func minimumAccessibleHitTarget() -> some View {
        #if os(iOS)
        self
            .frame(
                minWidth: AccessibleHitTarget.minimumDimension,
                minHeight: AccessibleHitTarget.minimumDimension
            )
            .contentShape(Rectangle())
        #else
        self
        #endif
    }
}
