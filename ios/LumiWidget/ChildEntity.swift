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
struct ChildEntity: AppEntity, Identifiable, Hashable {
    /// Sentinel ID meaning "use whatever child is currently active in the app."
    /// Must be a NON-EMPTY string — iOS silently drops entities with empty IDs
    /// from persisted widget configuration, which makes any picker selection
    /// revert to `defaultResult()` on the next timeline reload.
    /// `WidgetDataStore.buildEntry` treats this exact string as the signal to
    /// fall back to the App Group `selectedChildId`.
    static let activeChildId = "__lumi_active_child__"

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

    static let defaultQuery = ChildEntityQuery()

    /// The default sentinel — "follow the in-app active child."
    /// Stored (not computed) because `SelectChildIntent.@Parameter(default:)`
    /// requires a compile-time constant.
    static let activeChildSentinel = ChildEntity(
        id: activeChildId,
        firstName: "Active child in app"
    )
}

/// Closed-set query: the picker's options are exactly the sentinel plus the
/// parent's linked children — nothing else exists, nothing to search for.
///
/// `EnumerableEntityQuery` is the documented Apple pattern for closed sets and
/// it's what enables `WidgetConfigurationIntent` to actually persist picker
/// selections across timeline reloads. With basic `EntityQuery` iOS treats
/// `suggestedEntities()` as a hint set and (in practice) discards selections
/// on reload — `entities(for:)` is never called and the parameter snaps back
/// to `defaultResult()`. EnumerableEntityQuery gives iOS the full valid set,
/// so it can commit the chosen id to disk and rehydrate it cleanly.
struct ChildEntityQuery: EnumerableEntityQuery {
    /// The complete set of valid entities — sentinel + every linked child.
    /// iOS uses this to (a) populate the picker, (b) validate a saved entity
    /// id, and (c) persist the user's selection.
    func allEntities() async throws -> [ChildEntity] {
        var all: [ChildEntity] = [ChildEntity.activeChildSentinel]
        all.append(contentsOf: WidgetDataStore.allChildren().map {
            ChildEntity(id: $0.id, firstName: $0.name)
        })
        let summary = all.map { "\($0.id):\($0.firstName)" }.joined(separator: ", ")
        widgetDebugLog.notice("allEntities returning — \(summary, privacy: .public)")
        return all
    }

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

    // NOTE: deliberately no `defaultResult()`.
    //
    // Returning a non-nil default appears to make Apple's WidgetConfigurationIntent
    // framework treat the parameter as "always has the default value" and never
    // persist or rehydrate the user's picker selection (entities(for:) is never
    // called, defaultResult fires on every reload). Apple's own sample widgets
    // with EntityQuery omit defaultResult and rely on the @Parameter being
    // optional. The "follow active child" behaviour for a newly-added widget
    // (configuration.child == nil) is preserved by the provider's `?? ""`
    // fallback, which WidgetDataStore.buildEntry interprets as "use the App
    // Group selectedChildId" (= the in-app active child).
}
