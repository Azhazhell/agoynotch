//
//  DockBadgeReader.swift
//  AgoyNotch
//
//  Reads the Dock's badge text (the red unread count) for the target apps through the public
//  Accessibility API. Stateless and synchronous (AX IPC): call it ONLY on
//  MessageBadgeMonitor's background queue, never on the main thread. Only the badge text,
//  the item's URL and its title are read; message content is never touched.
//
//  Attribute names are string literals on purpose: `AXStatusLabel` has no header constant,
//  and the imported `kAX…` globals are `Unmanaged` vars (concurrency diagnostics).
//

import AppKit
import ApplicationServices

enum DockBadgeReadResult: Sendable {
    case ok([MessageBadge])
    case failed(String)
}

enum DockBadgeReader {

    static func read(dockPID: pid_t, targets: [DockBadgeTarget]) -> DockBadgeReadResult {
        let ax = AXUIElementCreateApplication(dockPID)
        // A hung Dock never blocks this queue for longer than this.
        AXUIElementSetMessagingTimeout(ax, 0.5)

        // Called directly (not via `attribute`) so the error code is kept for the log.
        var value: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(ax, "AXChildren" as CFString, &value)
        guard err == .success, let children = value as? [AXUIElement] else {
            return .failed("Dock children: AXError \(err.rawValue)")
        }

        let lists = children.filter { (attribute($0, "AXRole") as? String) == "AXList" }
        // Not `.ok([])`: the monitor must be able to tell "Dock changed shape" from "no badges".
        guard !lists.isEmpty else { return .failed("Dock has no AXList") }

        var found: [MessageApp: MessageBadge] = [:]
        for list in lists {
            guard let items = attribute(list, "AXChildren") as? [AXUIElement] else { continue }
            for item in items {
                // Most items have no badge: one IPC call for them.
                guard let label = BadgeLabel.normalize(attribute(item, "AXStatusLabel") as? String) else {
                    continue
                }
                let url = attribute(item, "AXURL") as? URL
                let bundleID = url.flatMap { Bundle(url: $0)?.bundleIdentifier }
                let title = attribute(item, "AXTitle") as? String

                let target: DockBadgeTarget?
                if let bundleID {
                    target = targets.first { $0.bundleID == bundleID }
                } else {
                    target = targets.first { $0.localizedName != nil && $0.localizedName == title }
                }
                guard let target, found[target.app] == nil else { continue }
                found[target.app] = MessageBadge(app: target.app, bundleID: target.bundleID, label: label)
            }
        }
        return .ok(MessageApp.allCases.compactMap { found[$0] })
    }

    /// The attribute's value, or nil unless the copy succeeded.
    private static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else {
            return nil
        }
        return value
    }
}
