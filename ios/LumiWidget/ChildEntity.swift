import AppIntents
import SwiftUI
import os

/// A child the parent has linked to their account. Powers the widget
/// configuration picker (long-press widget → Edit Widget → "Choose child").
///
/// The list of children is sourced from the App Group payload written by
/// `WidgetDataService` (Flutter side) — see `WidgetDataStore.allChildren()`.
///
/// A sentinel entity with id `ChildEntity.activeChildId` represents "follow
/// the active child in the app." It is the default and what the widget shows
/// before the parent customises anything.
struct ChildEntity: AppEntity, Identifiable {
    /// Sentinel ID meaning "use whatever child is currently active in the app."
    /// Matches the empty-string convention used by `WidgetDataStore.buildEntry`,
    /// which falls back to `selectedChildId` when given an empty string.
    static let activeChildId = ""

    let id: String
    let firstName: String

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Child")
    }

    var displayRepresentation: DisplayRepresentation {
        if id == Self.activeChildId {
            return DisplayRepresentation(
                title: "Active child in app",
                subtitle: "Follows the child selected in Lumi"
            )
        }
        return DisplayRepresentation(title: LocalizedStringResource(stringLiteral: firstName))
    }

    static var defaultQuery = ChildEntityQuery()

    /// The default sentinel — "follow the in-app active child."
    static var activeChildSentinel: ChildEntity {
        ChildEntity(id: activeChildId, firstName: "Active child in app")
    }
}

struct ChildEntityQuery: EntityQuery {
    func entities(for identifiers: [ChildEntity.ID]) async throws -> [ChildEntity] {
        let children = WidgetDataStore.allChildren()
        widgetDebugLog.notice("entities(for:) called — requested ids=\(identifiers, privacy: .public), allChildren count=\(children.count, privacy: .public)")
        let result = identifiers.map { id -> ChildEntity in
            if id == ChildEntity.activeChildId {
                return ChildEntity.activeChildSentinel
            }
            if let match = children.first(where: { $0.id == id }) {
                return ChildEntity(id: match.id, firstName: match.name)
            }
            // Fallback for a stale/unknown ID (e.g. child was unlinked): keep
            // the entry visible in the picker with a placeholder name so the
            // user can re-select. `WidgetDataStore.buildEntry` will fall back
            // to the active child at render time.
            return ChildEntity(id: id, firstName: "Unknown")
        }
        let summary = result.map { "\($0.id):\($0.firstName)" }.joined(separator: ", ")
        widgetDebugLog.notice("entities(for:) returning — \(summary, privacy: .public)")
        return result
    }

    /// What appears in the picker when the parent opens Edit Widget.
    /// Starts with the "Active child in app" sentinel, then lists every
    /// linked child.
    func suggestedEntities() async throws -> [ChildEntity] {
        var suggestions: [ChildEntity] = [ChildEntity.activeChildSentinel]
        suggestions.append(contentsOf: WidgetDataStore.allChildren().map {
            ChildEntity(id: $0.id, firstName: $0.name)
        })
        let summary = suggestions.map { "\($0.id):\($0.firstName)" }.joined(separator: ", ")
        widgetDebugLog.notice("suggestedEntities returning — \(summary, privacy: .public)")
        return suggestions
    }

    /// Pre-selected default when the parent first adds the widget.
    func defaultResult() async -> ChildEntity? {
        widgetDebugLog.notice("defaultResult() called — returning activeChildSentinel")
        return ChildEntity.activeChildSentinel
    }
}
