// StoreRecoveryCopy.swift
// Core / Copy
//
// `Copy.storeRecovery` — the screen the app shows instead of running when its on-device data store
// can't be opened (`ModelContainer.appGroupOpenFailure`, audit W1). Calm and plain: nothing is
// lost yet, here is the way out of any lock, here is who to tell.

extension Copy {
    public enum storeRecovery {
        public static let title = "ZANO couldn't open your data"
        public static let body = "Your goals and streak are still on this phone, but ZANO couldn't read them just now. Close ZANO and open it again. If this keeps happening, restart your phone, then email us."
        /// The always-available escape: lifts any shield ZANO put up.
        public static let unlockButtonLabel = "Unlock my apps"
        public static let unlockedConfirmation = "Your apps are unlocked."
        public static let contactLabel = "Email support"
    }
}
