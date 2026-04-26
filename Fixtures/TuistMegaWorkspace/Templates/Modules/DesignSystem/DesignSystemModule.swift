import Kingfisher
import SnapKit
import UIKit

public enum DesignSystem {
    public static let fixtureSummary = "DesignSystem packages: Kingfisher + SnapKit"
}

public final class DesignSystemContainerView: UIView {
    public override init(frame: CGRect) {
        super.init(frame: frame)

        let imageView = UIImageView()
        imageView.kf.indicatorType = .activity
        addSubview(imageView)
        imageView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
            make.height.greaterThanOrEqualTo(44)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
