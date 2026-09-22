/// Shared package for everything ZANO's app and extension targets have in common.
///
/// Subfolders (created as each session adds real files — see docs/spec.md §11 and
/// docs/PROGRESS.md for which session owns which folder):
///   Models        — SwiftData models (Session 1)
///   Store         — App Group–backed SwiftData container + shared UserDefaults (Session 1)
///   Intents       — App Intents catalog, docs/spec.md §14 (Session 4)
///   Verification  — goal verifiers: gym, focus, health, nfc (Session 3)
///   LockEngine    — shields, schedules, unlock rules, Time Bank (Session 2, §10)
///   Sync          — Supabase client + outbox pattern (Session 7)
///   UI            — design system, components, docs/spec.md §15 (Session 5)
///   Copy          — coach-voice copy, docs/spec.md §5.13 (Session 2+)
public enum ZanoCore {
    /// Bumped by hand when the shared package's shape changes meaningfully — not a build number.
    public static let version = "0.1.0"
}
