# Lumi Teacher Dashboard Redesign Plan
**Theme:** "Simplicity is the ultimate sophistication."
**Goal:** Create an intentional, high-signal, and visually premium experience for teachers.

---

## 1. The "Elegant" Weekly Reading Graph
The goal is to move from a "data table" feel to a "visual narrative."

### Visual Refinements
*   **Rounded Stadium Bars:** Use `BarChartRodData` with `borderRadius` on all corners to create a "pill" shape rather than a block.
*   **Vertical Gradients:** Implement a linear gradient for bars (e.g., `teacherPrimary` at 100% opacity at the top to 10% at the base). This provides vertical rhythm and depth.
*   **Minimalist Axis:** 
    *   Remove all Y-axis lines and labels.
    *   Remove X-axis border lines.
    *   Keep only Day labels (M, T, W...) in a light, muted `textSecondary`.
*   **The "Ghost" Benchmark:** Add a subtle, dashed horizontal line representing the class average or a set goal. This gives the data instant context without adding clutter.

### Micro-Interactions
*   **Soft Tooltips:** On tap, show a floating bubble with a "Summary of the Day" (e.g., "18/24 read • 3 new books started").
*   **Haptic Pulse:** A light haptic tap when interacting with specific data points.

---

## 2. The Art of the "Empty State"
An empty state should feel like a "clean canvas," not a "missing feature."

### Design Choices
*   **Shimmering Skeletons:** Ensure the `LumiSkeleton` exactly matches the final card dimensions to reduce "layout shift" anxiety.
*   **"Ghost Data" Placeholders:** If no logs exist for the week, show the graph with light, outlined bars (20% opacity) and a subtle message: *"Waiting for the first log of the week..."*
*   **The "Seed" Action:** Instead of a generic "Refresh" button, provide a purposeful CTA like *"Assign a book to get started"* or *"Log a class reading session."*

---

## 3. High-Signal Dashboard Features
Only add features that earn their place by providing immediate value (Intentionality).

### The "Daily Insight" (Hero Section)
*   Replace the static "Good Morning" with a dynamic insight:
    *   *"80% of Year 1 Blue met their goal yesterday! 🌟"*
    *   *"3 students are on a 5-day streak."*
    *   *"Leo hasn't logged in 3 days. Send a nudge?"*

### The "Priority Nudges" List
*   A small, elegant section (max 3 items) that only appears when action is needed.
*   Focuses on **Inactivity** or **Milestones** (e.g., "Sarah just finished her 10th book!").

### Reading Momentum Indicator
*   A tiny, sophisticated "sparkline" or arrow next to the class name showing if the reading rate is trending up or down compared to the previous week.

---

## 4. Sophisticated Details (The "Small" Things)
*   **Soft Elevation:** Use elevation `0` or `1` with custom shadows (`Color.withValues(alpha: 0.04)`) and a 1px border (`AppColors.teacherBorder`).
*   **Negative Space:** Increase padding between cards to let the content "breathe."
*   **Micro-Animations:** Use `flutter_animate` to ensure cards don't just "pop" in but "float" into position with a subtle 200ms slide-and-fade.

---

## 5. Implementation Roadmap

### Phase 1: Visual Core
*   Refactor `_WeeklyEngagementChart` to use gradients and stadium rods.
*   Cleanup `_DashboardStatsGrid` to use more whitespace and softer icons.

### Phase 2: Intelligence
*   Implement the `DailyInsight` logic in the Hero section.
*   Add the `PriorityNudges` widget to replace the generic `InactivityAlertBanner`.

### Phase 3: Polish
*   Apply `flutter_animate` transitions to all dashboard cards.
*   Integrate Haptic feedback on all primary interactions.
