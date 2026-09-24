// BrandCopy.swift
// Core / Copy
//
// The brand name and taglines (docs/spec.md header: "Taglines carry the meaning: 'Tap in.' /
// 'Earn it.'"; docs/brand/brand-kit.md). Used as the logo's accessibility label and wherever the
// brand speaks for itself.

extension Copy {
    public enum brand {
        public static let name = "ZANO"
        public static let taglineEarn = "Earn it."
        public static let taglineTap = "Tap in."
        /// Settings footer under the wordmark: `"Version 1.0 (42)"`.
        public static func versionLine(version: String, build: String) -> String {
            "Version \(version) (\(build))"
        }
    }
}
