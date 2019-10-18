//
//  FilesViewController.swift
//  Markdown
//
//  Created by zhubch on 2017/6/22.
//  Copyright © 2017年 zhubch. All rights reserved.
//

import UIKit
import EZSwiftExtensions
import RxSwift
import QuickLook
import Zip

class FilesViewController: UIViewController {
        
    @IBOutlet weak var tableView: UITableView!
    
    @IBOutlet weak var emptyView: UIView!
    
    @IBOutlet weak var oprationViewBottom: NSLayoutConstraint!

    let pulldDownLabel = UILabel()
        
    fileprivate var files = [File]()
    
    fileprivate var items = [
        File.cloud,
        File.inbox,
    ]
    
    var sections: [[File]] {
        if isHomePage {
            return [items,files]
        }
        return [files]
    }
    
    var root = File.empty
    
    let bag = DisposeBag()
            
    var textField: UITextField?
    
    var isHomePage = false
    
    var selectFolderMode = false
    
    var selectFiles = [File]()
    
    var selectedFolder: File?
    
    var filesToMove: [File]?

    var moveFrom: FilesViewController?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        if root == File.empty && selectFolderMode == false {
            root = File.local
            isHomePage = true
        }
        
        if isHomePage {
            title = /"Documents"
            loadFiles()
            observeFileChange()
        } else if selectFolderMode {
            title = /"MoveTo"
            File.local.expand = false
            File.cloud.expand = false
            _ = Configure.shared.theme.asObservable().subscribe(onNext: { (theme) in
                self.navBar?.barStyle = theme == .white ? .default : .black
            })
        } else {
            title = root.displayName ?? root.name
            tableView.tableHeaderView = UIView(x: 0, y: 0, w: 0, h: 0.01)
        }
        
        refresh()

        setupUI()
        
        setupBarButton()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        if !isMovingToParentViewController {
            refresh()
        }
        
        if root == File.cloud {
            root.reloadChildren()
            refresh()
        }
        
        tableView.allowsMultipleSelectionDuringEditing = false
    }
    
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        if Configure.shared.darkOption.value != .system || isHomePage == false {
            return
        }
        if #available(iOS 13.0, *) {
            if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
                ColorCenter.shared.theme = UITraitCollection.current.userInterfaceStyle == .dark ? .black : .white
            }
        }
    }
    
    func observeFileChange() {
        NotificationCenter.default.addObserver(self, selector: #selector(localChanged(_:)), name: Notification.Name("LocalChanged"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(inboxChanged(_:)), name: Notification.Name("InboxChanged"), object: nil)
    }
    
    func loadFiles() {
        File.loadLocal { local in
            self.root = local
            self.refresh()
        }
        File.loadCloud { cloud in
            self.items[0] = cloud
            self.tableView.reloadRows(at: [IndexPath(row: 0, section: 0)], with: .none)
        }
        File.loadInbox { inbox in
            self.items[1] = inbox
            self.tableView.reloadRows(at: [IndexPath(row: 1, section: 0)], with: .none)
        }
    }
    
    @objc func localChanged(_ noti: Notification) {
        navigationController?.popToRootViewController(animated: true)
        File.loadLocal { local in
            self.root = local
            self.refresh()
        }
    }
    
    @objc func inboxChanged(_ noti: Notification) {
        navigationController?.popToRootViewController(animated: true)
        guard let url = noti.object as? URL else { return }
        didPickFile(url)
    }
    
    @objc func multipleSelect() {
        selectFiles = []
        tableView.setEditing(tableView.isEditing == false, animated: true)
        setupBarButton()
        if root == File.inbox {
            return
        }
        var inset = CGFloat(0)
        if #available(iOS 11.0, *) {
            inset = view.safeAreaInsets.bottom
        }
        oprationViewBottom.constant = tableView.isEditing ? 0 : -44 - inset
        UIView.animate(withDuration: 0.5) {
            self.view.layoutIfNeeded()
        }
    }
    
    @objc func selectAllFiles() {
        for i in 0..<files.count {
            selectFiles.append(files[i])
            let indexPath = IndexPath(row: i, section: isHomePage ? 1 : 0)
            tableView.selectRow(at: indexPath, animated: true, scrollPosition: .none)
        }
    }
    
    func refresh() {
        if (selectFolderMode) {
            files = [File.cloud,File.local]
        } else {
            files = root.children.sorted {
                switch Configure.shared.sortOption {
                case .type:
                    return $0.type == .text && $1.type == .folder
                case .name:
                    return $0.name > $1.name
                case .modifyDate:
                    return $0.modifyDate > $1.modifyDate
                }
            }
        }
        if isViewLoaded {
            tableView.reloadData()
            if isPhone || selectFolderMode || tableView.isEditing || File.current == nil {
                return
            }
            if let index = files.firstIndex(where: { $0 == File.current! }) {
                let indexPath = IndexPath(row: index, section: isHomePage ? 1 : 0)
                tableView.selectRow(at: indexPath, animated: false, scrollPosition: .middle)
            }
        }
    }
    
    @IBAction func longPressedTableView(_ ges: UILongPressGestureRecognizer!) {
        if ges.state != .began {
            return
        }
        if tableView.isEditing || selectFolderMode {
            return
        }
        if root.isExternalFile {
            return
        }
        let pos = ges.location(in: ges.view)
        if let _ = tableView.indexPathForRow(at: pos) {
            multipleSelect()
        }
    }
    
    @IBAction func moveFiles() {
        if self.selectFiles.count == 0 {
            return
        }
        self.selectFiles = self.selectFiles.filter { !$0.opened }
        if self.selectFiles.count == 0 {
            SVProgressHUD.showError(withStatus: /"FileIsEditing")
            return
        }
        self.performSegue(withIdentifier: "move", sender: self.selectFiles)
        multipleSelect()
    }
    
    @IBAction func deleteFiles() {
        if self.selectFiles.count == 0 {
            return
        }
        self.selectFiles = self.selectFiles.filter { !$0.opened }
        if self.selectFiles.count == 0 {
            SVProgressHUD.showError(withStatus: /"FileIsEditing")
            return
        }
        self.showAlert(title:nil , message: /"DeleteMessage", actionTitles: [/"Cancel",/"Delete"], textFieldconfigurationHandler: nil, actionHandler: { (index) in
            if index == 0 {
                return
            }
            self.selectFiles.forEach { file in
                file.trash()
            }
            self.refresh()
            self.multipleSelect()
        })
    }
    
    @objc func cancel() {
        dismiss(animated: true, completion: nil)
    }
    
    @objc func sureMove() {
        guard let newParent = selectedFolder else { return }
        filesToMove?.forEach {
            $0.move(to: newParent)
        }
        moveFrom?.refresh()
        dismiss(animated: true) { }
    }
    
    @objc func showSettings() {
        performSegue(withIdentifier: "settings", sender: nil)
    }
    
    @objc func createFile(_ sender: Any) {
        showAlert(title: nil, message: /"CreateTips", actionTitles: [/"CreateNote",/"CreateFolder",/"Cancel"], textFieldconfigurationHandler: { textField in
            textField.clearButtonMode = .whileEditing
            textField.placeholder = /"FileNamePlaceHolder"
            self.textField = textField
        }) { index in
            let name = self.textField?.text ?? ""
            if name.count == 0 || index == 2 {
                return
            }
            guard let file = self.root.createFile(name: name, type: index == 0 ? .text : .folder) else {
                return
            }
            self.openFile(file)
        }
    }
    
    func openFile(_ file: File) {
        if file.type == .folder || file.type == .location {
            performSegue(withIdentifier: "file", sender: file)
            return
        }
        if file.type == .other {
            preview(file)
            return
        }
        if file.type == .archive {
            unzip(file)
            return
        }
        if file.opened {
            return
        }
        SVProgressHUD.show()
        file.open { text in
            SVProgressHUD.dismiss()
            if text == nil {
                SVProgressHUD.showError(withStatus: /"CanNotAccesseThisFile")
                return
            }
            guard let parent = file.parent else {
                self.performSegue(withIdentifier: "edit", sender: file)
                return
            }
            self.goToRoot(parent)
            self.performSegue(withIdentifier: "edit", sender: file)
        }
    }
    
    func preview(_ file: File) {
        guard let url = file.url as NSURL?, QLPreviewController.canPreview(url) else {
            SVProgressHUD.showError(withStatus: /"CanNotPreviewThisFile")
            return
        }
        let vc = QLPreviewController()
        vc.dataSource = self
        vc.delegate = self
        vc.currentPreviewItemIndex = files.firstIndex{ $0 == file } ?? 0
        presentVC(vc)
    }
    
    func unzip(_ file: File) {
        guard let url = file.url, let destURL = root.url else { return }
        SVProgressHUD.show()
        DispatchQueue.global().async {
            do {
                try Zip.unzipFile(url, destination: destURL, overwrite: false, password: nil, progress: { progress in

                })
                DispatchQueue.main.async {
                    self.root.reloadChildren()
                    self.refresh()
                    SVProgressHUD.dismiss()
                }
            } catch {
                DispatchQueue.main.async {
                    SVProgressHUD.dismiss()
                    SVProgressHUD.showError(withStatus: "UnzipFailed")
                }
            }
        }

    }
    
    func goToRoot(_ root: File) {
        if root.type == .text || root.type == .other {
            return
        }
        if root == self.root {
            refresh()
            return
        }
        if let vc = self.navigationController?.viewControllers.first(where: { vc -> Bool in
            if let filesVC = vc as? FilesViewController {
                return filesVC.root == root
            }
            return false
        }) {
            self.navigationController?.popToViewController(vc, animated: true)
            return
        }
        performSegue(withIdentifier: "file", sender: root)
    }
    
    func didSelectFile(_ indexPath: IndexPath) {
        let file = sections[indexPath.section][indexPath.row]
        if file == File.location {
            addLocation()
            tableView.deselectRow(at: indexPath, animated: true)
            return
        }
        if file == File.inbox && file.children.count == 0 {
            pickFromFiles()
            return
        }
        if file.disable {
            SVProgressHUD.showError(withStatus: /"CanNotAccesseThisFile")
            return
        }
        
        openFile(file)
    }
    
    func didSelectDestFolder(_ indexPath: IndexPath) {
        navigationItem.rightBarButtonItem?.isEnabled = true
        selectedFolder = sections[indexPath.section][indexPath.row]
        let cell = tableView.cellForRow(at: indexPath)
        if selectedFolder!.folders.count > 0 {
            var indexPaths = [IndexPath]()
            for i in 1...selectedFolder!.folders.count {
                indexPaths.append(IndexPath(row: indexPath.row + i, section: indexPath.section))
            }
            if selectedFolder!.expand {
                files.removeAll { item -> Bool in
                    return selectedFolder!.folders.contains{ $0 == item }
                }
                tableView.deleteRows(at: indexPaths, with: .top)
            } else {
                files.insert(contentsOf: selectedFolder!.folders, at: indexPath.row + 1)
                tableView.insertRows(at: indexPaths, with: .bottom)
            }
            selectedFolder!.expand = !selectedFolder!.expand
            (cell?.accessoryView as? UIImageView)?.image = (selectedFolder!.expand ?  #imageLiteral(resourceName: "icon_expand") : #imageLiteral(resourceName: "icon_forward")).recolor(color: ColorCenter.shared.secondary.value)
        }
    }
    
    func setupBarButton() {
        if selectFolderMode {
            navigationItem.prompt = /"SelectFolderToMove"
            navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(cancel))
            navigationItem.rightBarButtonItem = UIBarButtonItem(title: /"Move", style: .done, target: self, action: #selector(sureMove))
            navigationItem.rightBarButtonItem?.isEnabled = false
        } else if root == File.inbox {
            navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(pickFromFiles))
            if tableView.isEditing {
                navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(multipleSelect))
            }
        } else if root.isExternalFile == false {
            if tableView.isEditing {
                navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(multipleSelect))
                navigationItem.leftBarButtonItem = UIBarButtonItem(title: /"SelectAll", style: .plain, target: self, action: #selector(selectAllFiles))
            } else {
                navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(createFile(_:)))
                if isHomePage {
                    navigationItem.leftBarButtonItem = UIBarButtonItem(image: #imageLiteral(resourceName: "nav_settings"), style: .plain, target: self, action: #selector(showSettings))
                } else {
                    navigationItem.leftBarButtonItem = nil
                }
            }
        }
    }
    
    func doIfPro(_ task: (() -> Void)) {
        let date = Date(fromString: "2019-10-16", format: "yyyy-MM-dd")!
        let now = Date()
        if now <= date {
            task()
            return
        }
        if Configure.shared.isPro {
            task()
            return
        }
        showAlert(title: /"PremiumOnly", message: /"PremiumTips", actionTitles: [/"SubscribeNow",/"Cancel"], textFieldconfigurationHandler: nil) { [unowned self](index) in
            if index == 0 {
                let sb = UIStoryboard(name: "Settings", bundle: Bundle.main)
                let vc = sb.instantiateVC(PurchaseViewController.self)!
                let nav = UINavigationController(rootViewController: vc)
                nav.modalPresentationStyle = .formSheet
                self.presentVC(nav)
            }
        }
    }
    
    func setupUI() {
        DispatchQueue.main.async {
            var inset = CGFloat(0)
            if #available(iOS 11.0, *) {
                self.navigationItem.largeTitleDisplayMode = .never
                inset = UIApplication.shared.keyWindow?.safeAreaInsets.bottom ?? 0
            }
            self.oprationViewBottom.constant = -44 - inset
        }
                                
        navBar?.setTintColor(.navTint)
        navBar?.setBackgroundColor(.navBar)
        navBar?.setTitleColor(.navTitle)
        view.setBackgroundColor(.background)
        view.setTintColor(.navTint)
        tableView.setBackgroundColor(.tableBackground)
        tableView.setSeparatorColor(.primary)
        emptyView.setBackgroundColor(.background)
        
        pulldDownLabel.text = Configure.shared.sortOption.next.displayName
        pulldDownLabel.setTextColor(.secondary)
        pulldDownLabel.font = UIFont.font(ofSize: 14)
        tableView.addPullDownView(pulldDownLabel, bag: bag) { [unowned self] in
            Configure.shared.sortOption = Configure.shared.sortOption.next
            self.pulldDownLabel.text = Configure.shared.sortOption.next.displayName
            self.refresh()
        }
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        
        if segue.identifier == "move" {
            if let nav = segue.destination as? UINavigationController,
                let vc = nav.topViewController as? FilesViewController,
                let files = sender as? [File] {
                vc.selectFolderMode = true
                vc.filesToMove = files
                vc.moveFrom = self
            }
            return
        }
        
        if let vc = segue.destination as? FilesViewController,
            let file = sender as? File {
            vc.root = file
            return
        }
        
        if let nav = segue.destination as? UINavigationController,
            let vc = nav.topViewController as? EditViewController,
            let file = sender as? File {
            vc.file = file
            return
        }
    }
}

extension FilesViewController: UITableViewDelegate, UITableViewDataSource {
    func numberOfSections(in tableView: UITableView) -> Int {
        tableView.isHidden = files.count == 0 && isHomePage == false
        return sections.count
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return sections[section].count
    }
    
    func tableView(_ tableView: UITableView, indentationLevelForRowAt indexPath: IndexPath) -> Int {
        if !selectFolderMode {
            return 0
        }
        let file = sections[indexPath.section][indexPath.row]
        return file.deep
    }
        
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "item", for: indexPath)
        let file = sections[indexPath.section][indexPath.row]
        cell.textLabel?.text = file.displayName ?? file.name
        if file.type == .folder || file.type == .location {
            let count = file.children.count
            cell.detailTextLabel?.text = count == 0 ? /"Empty" : "\(file.children.count) " + /"Children"
            if file == File.cloud {
                cell.imageView?.image = #imageLiteral(resourceName: "icon_cloud").recolor(color: ColorCenter.shared.tint.value)
            } else if file == File.inbox {
                cell.imageView?.image = #imageLiteral(resourceName: "icon_box").recolor(color: ColorCenter.shared.tint.value)
                if count == 0 {
                    cell.textLabel?.text = /"ExternalEmpty"
                    cell.detailTextLabel?.text = ""
                }
            } else if file == File.location {
                cell.imageView?.image = #imageLiteral(resourceName: "icon_location").recolor(color: ColorCenter.shared.tint.value)
                cell.detailTextLabel?.text = ""
            } else if file == File.local {
                cell.imageView?.image = #imageLiteral(resourceName: "icon_local").recolor(color: ColorCenter.shared.tint.value)
            } else {
                cell.imageView?.image = #imageLiteral(resourceName: "icon_folder").recolor(color: ColorCenter.shared.tint.value)
            }
        } else {
            cell.detailTextLabel?.text = file.modifyDate.readableDate()
            let icon = file.type == .archive ? #imageLiteral(resourceName: "icon_archive") : (file.type == .image ? #imageLiteral(resourceName: "icon_image"): #imageLiteral(resourceName: "icon_text"))
            cell.imageView?.image = icon.recolor(color: ColorCenter.shared.tint.value)
        }
                
        if selectFolderMode {
            cell.indentationWidth = 20
            cell.detailTextLabel?.text = nil
        }
        return cell
    }
        
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if isHomePage && indexPath.section == 0 {
            tableView.deselectRow(at: indexPath, animated: true)
            if tableView.isEditing {

            } else {
                doIfPro {
                    self.didSelectFile(indexPath)
                }
            }
        } else if tableView.isEditing {
            let file = files[indexPath.row]
            if file.isExternalFile {
                tableView.deselectRow(at: indexPath, animated: true)
            } else {
                selectFiles.append(file)
            }
        } else if selectFolderMode {
            didSelectDestFolder(indexPath)
        } else {
            didSelectFile(indexPath)
        }
    }
    
    func tableView(_ tableView: UITableView, didDeselectRowAt indexPath: IndexPath) {
        if tableView.isEditing {
            let file = files[indexPath.row]
            selectFiles.removeAll { file == $0 }
        }
    }
    
    func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        if selectFolderMode {
            return false
        }
        if isHomePage && indexPath.section == 0 {
            let file = self.sections[indexPath.section][indexPath.row]
            return file.isExternalFile
        }
        return self.root.isExternalFile == false
    }
    
    func tableView(_ tableView: UITableView, editingStyleForRowAt indexPath: IndexPath) -> UITableViewCellEditingStyle {
        
        let file = self.sections[indexPath.section][indexPath.row]
        if file.isExternalFile {
            return .delete
        }
        return UITableViewCellEditingStyle(rawValue: UITableViewCellEditingStyle.delete.rawValue | UITableViewCellEditingStyle.insert.rawValue)!
    }
    
    func tableView(_ tableView: UITableView, editActionsForRowAt indexPath: IndexPath) -> [UITableViewRowAction]? {
        let file = self.sections[indexPath.section][indexPath.row]
        
        if file.isExternalFile {
            let deleteAction = UITableViewRowAction(style: .destructive, title: /"Delete") { [unowned self](_, indexPath) in
                if file.opened {
                    SVProgressHUD.showError(withStatus: /"FileIsEditing")
                    return
                }
                file.trash()
                if self.isHomePage {
                    self.items.remove(at: indexPath.row)
                } else {
                    self.files.remove(at: indexPath.row)
                }
                tableView.deleteRows(at: [indexPath], with: .middle)
            }
            return [deleteAction]
        }
        
        let deleteAction = UITableViewRowAction(style: .destructive, title: /"Delete") { [unowned self](_, indexPath) in
            if file.opened {
                SVProgressHUD.showError(withStatus: /"FileIsEditing")
                return
            }
            self.showAlert(title: nil, message: /"DeleteMessage", actionTitles: [/"Cancel",/"Delete"], textFieldconfigurationHandler: nil, actionHandler: { (index) in
                if index == 0 {
                    return
                }
                file.trash()
                self.files.remove(at: indexPath.row)
                tableView.deleteRows(at: [indexPath], with: .middle)
            })
        }
        
        let renameAction = UITableViewRowAction(style: .default, title: /"RenameTips") { [unowned self](_, indexPath) in
            if file.disable {
                SVProgressHUD.showError(withStatus: /"CanNotAccesseThisFile")
                return
            }
            if file.opened {
                SVProgressHUD.showError(withStatus: /"FileIsEditing")
                return
            }
            self.showAlert(title: nil, message: /"RenameTips", actionTitles: [/"Cancel",/"OK"], textFieldconfigurationHandler: { (textField) in
                textField.text = file.displayName ?? file.name
                textField.clearButtonMode = .whileEditing
                textField.placeholder = /"FileNamePlaceHolder"
                self.textField = textField
            }, actionHandler: { (index) in
                let name = (self.textField?.text ?? "").trimmed()
                if index == 0 || name.count == 0 {
                    return
                }
                let pattern = "^[^\\.\\*\\:/]+$"
                let predicate = NSPredicate(format: "SELF MATCHES %@", pattern)
                
                if predicate.evaluate(with: name) {
                    file.rename(to: name)
                } else {
                    SVProgressHUD.showError(withStatus: /"FileNameError")
                }
                tableView.reloadRows(at: [indexPath], with: .automatic)
            })
        }
        
        let moveAction = UITableViewRowAction(style: .default, title: /"Move") { [unowned self](_, indexPath) in
            if file.opened {
                SVProgressHUD.showError(withStatus: /"FileIsEditing")
                return
            }
            self.performSegue(withIdentifier: "move", sender: [file])
        }
        
        renameAction.backgroundColor = .lightGray
        moveAction.backgroundColor = .orange
        return [deleteAction,renameAction,moveAction]
    }
}

extension FilesViewController: UIDocumentPickerDelegate {
    
    @objc func pickFromFiles() {
        let picker = UIDocumentPickerViewController(documentTypes: ["public.text"], in: .open)
        picker.delegate = self
        picker.modalPresentationStyle = .formSheet
        presentVC(picker)
    }
    
    @objc func addLocation() {
        let picker = UIDocumentPickerViewController(documentTypes: ["public.folder"], in: .open)
        picker.delegate = self
        if #available(iOS 11.0, *) {
            picker.allowsMultipleSelection = true
        }
        picker.modalPresentationStyle = .formSheet
        presentVC(picker)
    }
    
    func finishPick(_ url: URL) {
        let accessed = url.startAccessingSecurityScopedResource()
        if !accessed {
            SVProgressHUD.showError(withStatus: /"CanNotAccesseThisFile")
            return
        }
        guard let values = try? url.resourceValues(forKeys: [URLResourceKey.isDirectoryKey]) else {
            url.stopAccessingSecurityScopedResource()
            SVProgressHUD.showError(withStatus: /"CanNotAccesseThisFile")
            return
        }
        if values.isDirectory ?? false {
            didPickFolder(url)
        } else {
            didPickFile(url)
        }
    }
    
    func didPickFile(_ url: URL) {
        showActionSheet(actionTitles: [/"ImportFile",/"OpenOriginFile"]) { index in
            let name = url.deletingPathExtension().lastPathComponent
            if index == 0 {
                guard let data = try? Data(contentsOf: url) else { return }
                url.stopAccessingSecurityScopedResource()
                if let newFile = File.local.createFile(name: name, contents: data, type: .text) {
                    self.openFile(newFile)
                }
            } else {
                guard let data = try? url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil) else { return }
                url.stopAccessingSecurityScopedResource()
                if let newFile = File.inbox.createFile(name: name, contents: data, type: .text) {
                    self.openFile(newFile)
                }
            }
        }
    }
    
    func didPickFolder(_ url: URL) {
        let name = url.deletingPathExtension().lastPathComponent
        guard let data = try? url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil) else { return }
        url.stopAccessingSecurityScopedResource()
        if let newFile = File.location.createFile(name: name, contents: data, type: .location) {
            items.insert(newFile, at: 2)
            tableView.insertRows(at: [IndexPath(row: 2, section: 0)], with: .middle)
        }
    }
    
    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        
    }
    
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentAt url: URL) {
        finishPick(url)
    }
    
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        if urls.count > 0 {
            finishPick(urls.first!)
        }
    }
}

extension FilesViewController: QLPreviewControllerDelegate, QLPreviewControllerDataSource {
    func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
        return self.files.count
    }
    
    func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
        let file = files[index]
        if let url = file.url as NSURL? { return url}
        return NSURL()
    }
    
}

