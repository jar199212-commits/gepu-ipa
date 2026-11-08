import SwiftUI

struct ImagePager: UIViewRepresentable {
    let ids: [String]
    @Binding var index: Int
    let loader: (String) async -> UIImage?
    var onTap: () -> Void = {}

    func makeUIView(context: Context) -> PagerView {
        let view = PagerView()
        view.onIndexChange = { newIndex in
            if index != newIndex {
                DispatchQueue.main.async {
                    if self.index != newIndex { self.index = newIndex }
                }
            }
        }
        view.onTap = onTap
        view.setItems(ids, index: index, loader: loader)
        return view
    }

    func updateUIView(_ uiView: PagerView, context: Context) {
        uiView.onTap = onTap
        uiView.loader = loader
        if uiView.currentIDs != ids {
            uiView.setItems(ids, index: index, loader: loader)
        } else if uiView.currentIndex != index {
            uiView.scroll(to: index)
        }
    }
}

// MARK: - 分页容器
final class PagerView: UIView {
    private lazy var collectionView: UICollectionView = {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.minimumLineSpacing = 0
        layout.minimumInteritemSpacing = 0
        layout.sectionInset = .zero
        let cv = UICollectionView(frame: .zero, collectionViewLayout: layout)
        cv.isPagingEnabled = true
        cv.backgroundColor = .black
        cv.showsHorizontalScrollIndicator = false
        cv.contentInsetAdjustmentBehavior = .never
        cv.dataSource = self
        cv.delegate = self
        cv.register(ImagePageCell.self, forCellWithReuseIdentifier: "page")
        return cv
    }()

    var currentIDs: [String] = []
    var currentIndex: Int = 0
    var loader: ((String) async -> UIImage?)?
    var onIndexChange: ((Int) -> Void)?
    var onTap: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        addSubview(collectionView)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        backgroundColor = .black
        addSubview(collectionView)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let old = collectionView.frame
        collectionView.frame = bounds
        if let layout = collectionView.collectionViewLayout as? UICollectionViewFlowLayout {
            if layout.itemSize != bounds.size {
                layout.itemSize = bounds.size
                layout.invalidateLayout()
            }
        }
        if old.width != bounds.width {
            scroll(to: currentIndex, animated: false)
        }
    }

    func setItems(_ ids: [String], index: Int, loader: ((String) async -> UIImage?)?) {
        currentIDs = ids
        self.loader = loader
        currentIndex = max(0, min(index, max(0, ids.count - 1)))
        collectionView.reloadData()
        layoutIfNeeded()
        scroll(to: currentIndex, animated: false)
    }

    func scroll(to index: Int, animated: Bool = false) {
        guard index >= 0, index < currentIDs.count, collectionView.bounds.width > 0 else { return }
        let target = CGPoint(x: collectionView.bounds.width * CGFloat(index), y: 0)
        if abs(collectionView.contentOffset.x - target.x) < 0.5 { return }
        collectionView.setContentOffset(target, animated: animated)
    }

    private func syncCurrentPage() {
        let width = collectionView.bounds.width
        guard width > 0 else { return }
        let page = Int(round(collectionView.contentOffset.x / width))
        guard page >= 0, page < currentIDs.count, page != currentIndex else { return }
        currentIndex = page
        onIndexChange?(page)
    }
}

extension PagerView: UICollectionViewDataSource, UICollectionViewDelegate, UICollectionViewDelegateFlowLayout {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        currentIDs.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "page", for: indexPath) as! ImagePageCell
        let id = currentIDs[indexPath.item]
        cell.configure(id: id, loader: loader, onTap: onTap)
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        collectionView.bounds.size
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) { syncCurrentPage() }
    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate { syncCurrentPage() }
    }
    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) { syncCurrentPage() }
}

// MARK: - 单页（可缩放）
final class ImagePageCell: UICollectionViewCell, UIScrollViewDelegate {
    private let scrollView = UIScrollView()
    private let imageView = UIImageView()
    private let spinner = UIActivityIndicatorView(style: .large)
    private let failLabel = UILabel()
    private var currentID = ""
    private var task: Task<Void, Never>?
    private var onTap: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        contentView.backgroundColor = .black

        scrollView.delegate = self
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = 4
        scrollView.bouncesZoom = true
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.contentInsetAdjustmentBehavior = .never
        contentView.addSubview(scrollView)

        imageView.contentMode = .scaleAspectFit
        imageView.isUserInteractionEnabled = true
        scrollView.addSubview(imageView)

        spinner.color = .white
        spinner.hidesWhenStopped = true
        contentView.addSubview(spinner)

        failLabel.text = "原图加载失败\n请检查 NAS 连接或在设置中开启网络"
        failLabel.numberOfLines = 0
        failLabel.textAlignment = .center
        failLabel.font = .systemFont(ofSize: 14)
        failLabel.textColor = UIColor.white.withAlphaComponent(0.7)
        failLabel.isHidden = true
        contentView.addSubview(failLabel)

        let single = UITapGestureRecognizer(target: self, action: #selector(handleSingleTap))
        let double = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        single.require(toFail: double)
        double.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(single)
        scrollView.addGestureRecognizer(double)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit { task?.cancel() }

    override func layoutSubviews() {
        super.layoutSubviews()
        scrollView.frame = contentView.bounds
        spinner.center = CGPoint(x: contentView.bounds.midX, y: contentView.bounds.midY)
        failLabel.frame = contentView.bounds.insetBy(dx: 24, dy: 0)
        if scrollView.zoomScale <= 1.01 {
            imageView.frame = scrollView.bounds
            scrollView.contentSize = scrollView.bounds.size
        }
    }

    func configure(id: String, loader: ((String) async -> UIImage?)?, onTap: (() -> Void)?) {
        self.onTap = onTap
        guard id != currentID else { return }
        currentID = id
        task?.cancel()
        imageView.image = nil
        failLabel.isHidden = true
        scrollView.setZoomScale(1, animated: false)
        spinner.startAnimating()

        guard let loader else {
            spinner.stopAnimating()
            failLabel.isHidden = false
            return
        }

        task = Task { [weak self] in
            let image = await loader(id)
            await MainActor.run {
                guard let self, self.currentID == id else { return }
                self.spinner.stopAnimating()
                if let image {
                    self.imageView.image = image
                    self.failLabel.isHidden = true
                    self.scrollView.setZoomScale(1, animated: false)
                    self.setNeedsLayout()
                } else {
                    self.failLabel.isHidden = false
                }
            }
        }
    }

    @objc private func handleSingleTap() {
        onTap?()
    }

    @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        if scrollView.zoomScale > 1.2 {
            scrollView.setZoomScale(1, animated: true)
        } else {
            let point = gesture.location(in: imageView)
            let size = CGSize(width: scrollView.bounds.width / 2.5, height: scrollView.bounds.height / 2.5)
            scrollView.zoom(to: CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2, width: size.width, height: size.height), animated: true)
        }
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        let offsetX = max((scrollView.bounds.width - scrollView.contentSize.width) * 0.5, 0)
        let offsetY = max((scrollView.bounds.height - scrollView.contentSize.height) * 0.5, 0)
        scrollView.contentInset = UIEdgeInsets(top: offsetY, left: offsetX, bottom: offsetY, right: offsetX)
    }
}
