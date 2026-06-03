import AppIntents
import SwiftUI

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

    /// The "follow the in-app active child" entity surfaced at the top of the
    /// picker via `ChildEntityQuery.allEntities()`.
    static let activeChildSentinel = ChildEntity(
        id: activeChildId,
        firstName: "Active child in app"
    )
}

/// Closed-set query: the picker's options are exactly the sentinel plus the
/// parent's linked children. `EnumerableEntityQuery` is Apple's documented
/// pattern for closed sets and exposes the full valid set to the framework
/// via `allEntities()`, which is what `WidgetConfigurationIntent` needs to
/// persist and rehydrate picker selections cleanly.
///
/// Deliberately no `defaultResult()` — returning a non-nil default makes the
/// framework treat the parameter as "always has the default value" and skip
/// persisting user selections. Apple's own AppEntity widget samples (e.g.
/// TLocation/weather) omit defaultResult and rely on the @Parameter being
/// optional. The "follow active child in app" behaviour for a newly-added
/// widget (configuration.child == nil) is preserved by the provider's
/// `?? ""` fallback, which `WidgetDataStore.buildEntry` interprets as "use
/// the App Group selectedChildId".
struct ChildEntityQuery: EnumerableEntityQuery {
    func allEntities() async throws -> [ChildEntity] {
        var all: [ChildEntity] = [ChildEntity.activeChildSentinel]
        all.append(contentsOf: WidgetDataStore.allChildren().map {
            ChildEntity(id: $0.id, firstName: $0.name)
        })
        return all
    }

    func entities(for identifiers: [ChildEntity.ID]) async throws -> [ChildEntity] {
        let children = WidgetDataStore.allChildren()
        return identifiers.map { id in
            if id == ChildEntity.activeChildId {
                return ChildEntity.activeChildSentinel
            }
            if let match = children.first(where: { $0.id == id }) {
                return ChildEntity(id: match.id, firstName: match.name)
            }
            // Fallback for a stale/unknown ID (e.g. child was unlinked): keep
            // the entry visible in the picker with a placeholder name so the
            // user can re-select. `WidgetDataStore.buildEntry` falls back to
            // the active child at render time.
            return ChildEntity(id: id, firstName: "Unknown")
        }
    }
}
