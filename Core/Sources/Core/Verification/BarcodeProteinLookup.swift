// Core/Sources/Core/Verification/BarcodeProteinLookup.swift
//
// docs/spec.md §3 (Goal Catalog & Verification), Protein row: Tier B, verified by "NFC tap on
// shaker/tub (+ preset grams), meal photo → vision model estimate, barcode scan, quick-repeat of
// recent meals." This file is the "barcode scan" path's data layer — given a scanned barcode, it
// answers "how much protein is in a serving of this product?" It does not scan anything itself
// (no VisionKit/AVFoundation code here — a barcode-scanning UI is a different, not-yet-built
// caller's job) and does not write a `GoalEvent` itself (see "Where this plugs in" below).
//
// docs/spec.md §10 (Food, Protein & Ordering Integrations):
//   "Barcode → product: Open Food Facts (free, open). Fallback to a commercial nutrition API if
//   coverage is poor."
// This file builds only the Open Food Facts half of that sentence. The fallback commercial API is
// explicitly an open, unresolved vendor choice — docs/spec.md §28 Open Questions: "Which
// nutrition/restaurant API is worth paying for at launch, if any?" — so rather than guessing a
// vendor (Nutritionix, Edamam, USDA FoodData Central, etc.) this file only defines
// `BarcodeNutritionFallbackProvider`, a protocol seam a future session implements against whatever
// vendor gets picked, wired in via `BarcodeProteinLookup.init(fallbackProvider:)`. No conforming
// type ships yet; `BarcodeProteinLookup.shared` runs with `fallbackProvider: nil`, so today a
// barcode Open Food Facts has no (or no nutrition) data for just throws — no silent vendor guess.
//
// Where this plugs in (per this task's own read of the real, current files — not memory):
//   - `GoalType.protein` (Core/Sources/Core/Models/Goal.swift) is the goal this feeds.
//   - `GoalEventSource.barcode` (Core/Sources/Core/Models/GoalEvent.swift) is the exact, already-
//     real `goal_events.source` case a `GoalEvent` for a barcode-derived log should carry.
//   - `IntentSupport.GoalLogSource.barcode` (Core/Sources/Core/Intents/IntentSupport.swift) already
//     exists and already maps to `GoalEventSource.barcode` via `.eventSource` — so a future
//     barcode-scan screen's flow is already wired end-to-end *except* for this file: scan →
//     `BarcodeProteinLookup.shared.lookupProtein(barcode:)` (this file) → feed the resulting
//     `proteinGramsPerServing` into `LogProteinIntent(grams:source: .barcode)` (spec §14:
//     `LogProteinIntent | grams, source | Writes goal_event`). This file deliberately stops at
//     producing that `Double` (plus the rest of `BarcodeProduct`) — it does not construct or run
//     `LogProteinIntent` itself, and does not touch `SwiftData`/`ModelContext` at all, since intent
//     files and their `perform()` bodies are `Core/Sources/Core/Intents`'s own territory (see
//     `LogProteinIntent.swift`), not this task's file list.
//   - `MealItem` (Core/Sources/Core/Models/Meal.swift, read directly for this task — its own header
//     already documents that `Meal.items` covers "non-photo logging paths (NFC tap, quick-repeat,
//     barcode)") is bridged to via `BarcodeProduct.asMealItem`, a pure, optional convenience for a
//     future caller that wants to log a barcode scan as a one-item `Meal` instead of/alongside a
//     `LogProteinIntent` call. Building/inserting the actual `Meal` row is still that future
//     caller's job, not this file's — this only hands back the `MealItem` value.
//
// Real API shape — verified live, not assumed from training memory (CLAUDE.md working rule 5):
// this task queried `https://world.openfoodfacts.org/api/v2/product/<barcode>.json` directly
// against four real barcodes on 2026-09-22 to confirm the exact response shape before writing the
// decoder below, rather than presenting a guessed shape as certain:
//   - `3017620422003` (Nutella): HTTP 200, `{"code","status":1,"status_verbose":"product found",
//     "product":{...}}`; `product.nutriments.proteins_100g` present, `proteins_serving` ABSENT
//     (Nutella has no `serving_size`/`serving_quantity` at all in Open Food Facts) — confirms the
//     "per-100g only, no serving size" case this file has to degrade gracefully for.
//   - `5000159484695` (Twix): HTTP 200, `status:1`; `product.serving_quantity: 43.1`,
//     `product.serving_size: "43.1 gram"`, `product.nutriments.proteins_serving: 1.2` present
//     alongside `proteins_100g: 2.78` — confirms the "OFF already did the per-serving math" case.
//   - `0017082521015` (not in OFF's database): **HTTP 404**, but still a small, valid, decodable
//     JSON body: `{"code":"0017082521015","status":0,"status_verbose":"product not found"}` — no
//     `product` key at all. This is the reason this file does NOT treat a non-2xx HTTP status as an
//     automatic transport failure: a 404 with a decodable `status:0` body is the *normal*,
//     expected shape for "barcode not in Open Food Facts," which is an everyday outcome for a
//     protein-tracking app's users (niche/regional/store-brand products), not an error condition.
//   - `0000000000000` (malformed/too-short after Open Food Facts' own normalization): HTTP 200,
//     `{"code":"00000000","status":0,"status_verbose":"no code or invalid code"}` — same `status:0`
//     shape, different `status_verbose`, still no `product` key. This file doesn't branch on
//     `status_verbose`'s exact text (only ever used for logging) since both cases collapse to the
//     same outcome a caller needs: "no product," i.e. `BarcodeProteinLookupError.productNotFound`.
//   - Also observed: Open Food Facts normalizes a scanned code across symbologies server-side (the
//     12-digit UPC-A `017082521015` came back in the 404 body as the 13-digit, zero-padded EAN-13
//     `0017082521015`) — this is why `normalizedBarcode(from:)` below only rejects obviously
//     non-barcode input (empty, non-digit, wildly wrong length) rather than hard-coding "must be
//     exactly 13 digits" and rejecting a valid EAN-8/UPC-E/UPC-A scan; Open Food Facts' own service
//     already does the symbology normalization.
//
// Explicitly NOT verified live (flagged per CLAUDE.md working rule 5, not presented as certain):
//   - Whether every product in Open Food Facts always reports `nutriments.proteins_unit == "g"`.
//     True for both real products checked above; this file defensively refuses to use a
//     `proteins_100g`/`proteins_serving` figure at all if `proteins_unit` is present and isn't
//     "g", rather than guessing a conversion, but a non-"g" unit was never actually observed to
//     confirm that branch fires correctly against a real response.
//   - Open Food Facts' request-rate-limit policy and exact User-Agent enforcement (this file sends
//     a descriptive `User-Agent`, matching the general courtesy Open Food Facts' public API docs
//     are known to ask integrators for, but this task did not fetch/read their current terms page
//     to confirm the exact wording or a hard numeric rate limit) — not enforced client-side here.
//   - Whether a 404-with-decodable-body is universal for every "not found" case, or whether some
//     other failure shapes exist (e.g. a genuine 5xx during a Open Food Facts outage, or a
//     malformed/truncated body) — this file treats "decodes successfully" vs. "doesn't" as the
//     real fork (see `lookupOpenFoodFacts(barcode:)`), which should degrade correctly either way,
//     but wasn't exhaustively fuzzed against real outage conditions.
//   - The exact set of `AVMetadataObject.ObjectType`/VisionKit symbologies a future scanning UI
//     will feed this file — `normalizedBarcode(from:)`'s 6...14 digit bound is a reasonable guess
//     at "every common retail barcode symbology" (UPC-E compressed through GTIN-14), not verified
//     against a real scan.
//
// No Mac/Swift compiler available to build-check this file (CLAUDE.md environment status) — the
// networking (`URLSession.data(for:)`, `URLComponents`) and `Decodable` pieces are ordinary
// Foundation API, not a framework whose surface shifts across iOS versions, so this is lower-risk
// than e.g. this directory's `NFCReader.swift`/`GymAutoDetect.swift` HealthKit/CoreNFC calls — but
// still unbuilt, unrun code; see this task's `knownIssues`.

import Foundation
import os

// MARK: - Public result types

/// How ``BarcodeProduct/proteinGramsPerServing`` was derived, so a caller can decide how much to
/// trust it (e.g. show "per Open Food Facts" vs. "estimated" copy, or decide whether to prompt the
/// user to confirm/edit before logging).
public enum BarcodeProteinEstimateBasis: String, Sendable, Equatable, Codable {
    /// Open Food Facts reported `nutriments.proteins_serving` directly — the product's own listed
    /// serving size and protein-per-serving figure, not computed here.
    case reportedPerServing
    /// No `proteins_serving` field, but `proteins_100g` and a serving size in grams
    /// (`serving_quantity`) were both present, so `proteinGramsPerServing` is this file's own
    /// `proteins_100g / 100 * serving_quantity` computation.
    case computedFromPer100g
    /// Only `proteins_100g` was available — no serving size at all (the real Nutella response this
    /// file's header verified is exactly this case). ``BarcodeProduct/proteinGramsPerServing`` is
    /// `nil` when this is the basis; a caller must ask the user for a serving size/grams figure
    /// before there's anything meaningful to log.
    case per100gOnly
}

/// One Open Food Facts (or, once a vendor is chosen, fallback-API) lookup result for a scanned
/// barcode. `Sendable`/`Hashable` value type — never holds a live network handle or model context.
public struct BarcodeProduct: Sendable, Hashable {
    /// The barcode Open Food Facts actually matched against — prefers the server's own
    /// (possibly-normalized, e.g. zero-padded) `code` over the caller's raw input when present,
    /// since that's the canonical identifier this product was really found under.
    public let barcode: String
    /// `product.product_name`, e.g. "Nutella". `nil` if Open Food Facts has no name on file.
    public let name: String?
    /// First comma-separated entry of `product.brands` (Open Food Facts stores brands as a
    /// free-text, comma-separated list, e.g. `"Nutella, Ferrero"` — this takes just the first for
    /// a clean single display brand). `nil` if absent or empty.
    public let brand: String?
    /// Grams of protein in one serving of this product, ready to feed into
    /// `LogProteinIntent(grams:source:)` (spec §14) — see ``BarcodeProteinEstimateBasis`` for how
    /// this was derived, and `nil` for the ``BarcodeProteinEstimateBasis/per100gOnly`` case, where
    /// no serving size exists to compute one from.
    public let proteinGramsPerServing: Double?
    /// How ``proteinGramsPerServing`` was derived (or why it's `nil`).
    public let proteinBasis: BarcodeProteinEstimateBasis
    /// `product.nutriments.proteins_100g` as-is, for a caller that wants to show/compute against
    /// the per-100g figure directly (e.g. a manual serving-size entry UI for the
    /// ``BarcodeProteinEstimateBasis/per100gOnly`` case). `nil` only if Open Food Facts had no
    /// protein data for this product at all, which ``BarcodeProteinLookup`` never returns as a
    /// success (see `BarcodeProteinLookupError.noNutritionData`) — so this is non-`nil` on every
    /// `BarcodeProduct` this file actually hands back.
    public let proteinGramsPer100g: Double?
    /// `product.serving_quantity` in grams, when Open Food Facts has one on file.
    public let servingSizeGrams: Double?
    /// `product.serving_size`, Open Food Facts' own free-text serving description (e.g.
    /// `"43.1 gram"`) — for display only; ``servingSizeGrams`` is the parsed numeric figure this
    /// file actually computes with.
    public let servingSizeDescription: String?
    /// `product.image_front_url`, when present and a valid `URL`.
    public let imageURL: URL?

    public init(
        barcode: String,
        name: String?,
        brand: String?,
        proteinGramsPerServing: Double?,
        proteinBasis: BarcodeProteinEstimateBasis,
        proteinGramsPer100g: Double?,
        servingSizeGrams: Double?,
        servingSizeDescription: String?,
        imageURL: URL?
    ) {
        self.barcode = barcode
        self.name = name
        self.brand = brand
        self.proteinGramsPerServing = proteinGramsPerServing
        self.proteinBasis = proteinBasis
        self.proteinGramsPer100g = proteinGramsPer100g
        self.servingSizeGrams = servingSizeGrams
        self.servingSizeDescription = servingSizeDescription
        self.imageURL = imageURL
    }

    /// Convenience bridge to `Models/Meal.swift`'s `MealItem` (read directly for this task — see
    /// this file's header), for a caller that wants to log this scan as a one-item `Meal` instead
    /// of (or in addition to) a direct `LogProteinIntent` call. `nil` whenever
    /// ``proteinGramsPerServing`` is `nil` (the ``BarcodeProteinEstimateBasis/per100gOnly`` case) —
    /// there's no confident per-serving figure yet to hand `MealItem.proteinGramsEstimate`.
    ///
    /// `confidence` reflects ``proteinBasis``, not a vision-model guess (this data came from a
    /// barcode match, not image inference): `1.0` when Open Food Facts reported the per-serving
    /// figure directly, `0.9` when this file computed it from `proteins_100g` × a serving size —
    /// still exact arithmetic, marked slightly under `1.0` only because Open Food Facts' serving
    /// size itself is crowd-sourced and occasionally wrong, not because the math is approximate.
    public var asMealItem: MealItem? {
        guard let proteinGramsPerServing else { return nil }
        let confidence: Double
        switch proteinBasis {
        case .reportedPerServing: confidence = 1.0
        case .computedFromPer100g: confidence = 0.9
        case .per100gOnly: confidence = 0.0 // unreachable: this basis always pairs with a nil proteinGramsPerServing above.
        }
        return MealItem(
            name: name ?? "Scanned item",
            proteinGramsEstimate: proteinGramsPerServing,
            confidence: confidence
        )
    }
}

/// Errors ``BarcodeProteinLookup`` throws. `Sendable`/`Equatable`, no associated `Error` values
/// (matches `NFCReaderFailure`'s convention in this same directory) — `.transportFailure` carries
/// a plain `String` description instead of the underlying `Error` so this stays `Equatable`.
public enum BarcodeProteinLookupError: Error, Sendable, Equatable {
    /// `barcode` was empty, contained non-digit characters, or was an implausible length before
    /// any network call was attempted. See `normalizedBarcode(from:)`'s doc comment.
    case invalidBarcode
    /// Open Food Facts has no product on file for this barcode (`status: 0` in a decodable
    /// response body — see this file's header for the real, live-verified shape, including that
    /// this can arrive over a 404 HTTP status with a perfectly valid JSON body). If a
    /// `fallbackProvider` is configured, ``BarcodeProteinLookup/lookupProtein(barcode:)`` tries it
    /// before this is thrown to the caller.
    case productNotFound
    /// Open Food Facts found the product but it has no usable protein figure (no
    /// `nutriments.proteins_100g` at all, or a `proteins_unit` other than `"g"` this file doesn't
    /// know how to interpret — see this file's header's "explicitly NOT verified live" note). Same
    /// fallback-provider behavior as `.productNotFound`.
    case noNutritionData
    /// A response body arrived but didn't decode as the expected JSON shape at all (as opposed to
    /// decoding fine with `status: 0` — that's `.productNotFound`, not this).
    case decodingFailure
    /// The network request itself failed (no connectivity, timeout, DNS failure, TLS failure, a
    /// non-2xx/404 HTTP status with no usable body, etc). The associated string is
    /// `(error as NSError).localizedDescription` or a short synthesized description, kept as a
    /// plain `String` so this type stays `Sendable`/`Equatable` without depending on `Error`'s own
    /// (non-`Equatable`) shape.
    case transportFailure(String)
}

// MARK: - Fallback vendor extension point (docs/spec.md §10 / §28 — unresolved, do not guess)

/// Seam for a future commercial nutrition-API fallback (docs/spec.md §10: "Fallback to a
/// commercial nutrition API if coverage is poor"). Which vendor — Nutritionix, Edamam, USDA
/// FoodData Central, or something else — is an explicit open question (docs/spec.md §28: "Which
/// nutrition/restaurant API is worth paying for at launch, if any?"), so this file only declares
/// the seam; no conforming type ships here, and `BarcodeProteinLookup.shared` runs with
/// `fallbackProvider: nil` until a future session wires a real one in via
/// `BarcodeProteinLookup.init(fallbackProvider:)`.
public protocol BarcodeNutritionFallbackProvider: Sendable {
    /// Looks up the same (already-normalized, digits-only) `barcode` Open Food Facts didn't have,
    /// or didn't have usable protein data for. Should `throw` — ideally a
    /// `BarcodeProteinLookupError` case, though any `Error` propagates unchanged — rather than
    /// returning a fabricated/zero-protein `BarcodeProduct`.
    func lookupProduct(barcode: String) async throws -> BarcodeProduct
}

// MARK: - BarcodeProteinLookup

/// Looks up a scanned barcode against Open Food Facts' free, public product API (docs/spec.md
/// §10) and extracts a per-serving protein figure. See this file's header for the real API shape
/// this was verified against, what's still unverified, and where the result is meant to plug in
/// (`LogProteinIntent`, `MealItem`).
///
/// A plain `Sendable` value type (not an `actor`) — every stored property (`URLSession`,
/// `BarcodeNutritionFallbackProvider?`, `Logger`) is itself `Sendable`, and there's no mutable
/// state to protect: each `lookupProtein(barcode:)` call is a self-contained request/response with
/// nothing shared across calls, so there's no race to guard against the way `SyncEngine`/
/// `LockEngineManager`'s persistent actor state needs. `.shared` is the real-usage singleton;
/// `init(session:fallbackProvider:)` stays `public` (not defaulted-and-hidden) so a future
/// `CoreTests` target can inject a stubbed `URLSession`/`URLProtocol` or a fake fallback provider,
/// matching this directory's existing testability convention (`QuickRepeatSuggester`,
/// `GymAutoDetect`).
public struct BarcodeProteinLookup: Sendable {
    public static let shared = BarcodeProteinLookup()

    /// Open Food Facts' barcode product-lookup endpoint (docs/spec.md §10) — v2, exactly as this
    /// task specified and as this file's header verified live.
    static let apiHost = "world.openfoodfacts.org"
    static let apiPath = "/api/v2/product/"

    /// Narrows the response to only the fields this file reads (see `requestURL(for:)`) — a
    /// well-populated product's *full* Open Food Facts payload (ingredient lists, allergen tags,
    /// per-language name variants, nutrient-estimate breakdowns, etc.) can run tens of KB; this
    /// file's header's live Nutella/Twix checks both confirmed `fields` narrows `product` down to
    /// just these keys without changing `code`/`status`/`status_verbose`'s own top-level shape.
    static let requestedFields = "code,status,status_verbose,product_name,brands,nutriments,serving_size,serving_quantity,image_front_url"

    /// Sent as `User-Agent` — Open Food Facts' public API guidance is known (from training
    /// knowledge, not a page this task fetched — see header) to ask integrators for a descriptive
    /// User-Agent identifying the calling app rather than a generic/default one. Not dynamically
    /// built from `Bundle.main` (this file has no access to the app target's actual bundle/version
    /// from within the `Core` package in a way that's meaningful in a unit-test host too), so this
    /// is a static placeholder a future session should firm up with a real contact once one exists.
    static let userAgent = "ZANO-iOS/1.0 (https://zano.app) - Barcode Protein Lookup"

    static let requestTimeoutSeconds: TimeInterval = 10

    /// Shortest real retail barcode symbology this file expects (UPC-E, compressed). See
    /// `normalizedBarcode(from:)`.
    static let minimumBarcodeLength = 6
    /// Longest real retail barcode symbology this file expects (GTIN-14). See
    /// `normalizedBarcode(from:)`.
    static let maximumBarcodeLength = 14

    private let session: URLSession
    private let fallbackProvider: BarcodeNutritionFallbackProvider?
    private let logger = Logger(subsystem: "com.zano.app.Core", category: "BarcodeProteinLookup")

    public init(session: URLSession = .shared, fallbackProvider: BarcodeNutritionFallbackProvider? = nil) {
        self.session = session
        self.fallbackProvider = fallbackProvider
    }

    // MARK: - Public contract

    /// Looks up `rawBarcode` (whatever a scanner or manual-entry field hands over — untrimmed,
    /// unvalidated) against Open Food Facts, falling back to `fallbackProvider` (if configured)
    /// only when Open Food Facts specifically has no product, or no usable protein data, on file
    /// (docs/spec.md §10: "if coverage is poor" — a data-coverage gap, not a transient network
    /// failure; a `.transportFailure` is never silently retried against the fallback here).
    ///
    /// Throws `BarcodeProteinLookupError` (or whatever `fallbackProvider.lookupProduct(barcode:)`
    /// itself throws, once one exists) — never returns a fabricated/placeholder product.
    public func lookupProtein(barcode rawBarcode: String) async throws -> BarcodeProduct {
        let barcode = try Self.normalizedBarcode(from: rawBarcode)
        do {
            return try await lookupOpenFoodFacts(barcode: barcode)
        } catch let error as BarcodeProteinLookupError {
            switch error {
            case .productNotFound, .noNutritionData:
                if let fallbackProvider {
                    logger.notice("Open Food Facts had no usable data for this barcode; trying configured fallback provider.")
                    return try await fallbackProvider.lookupProduct(barcode: barcode)
                }
                throw error
            case .invalidBarcode, .decodingFailure, .transportFailure:
                throw error
            }
        }
    }

    // MARK: - Open Food Facts request

    private func lookupOpenFoodFacts(barcode: String) async throws -> BarcodeProduct {
        let url = try Self.requestURL(for: barcode)
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = Self.requestTimeoutSeconds
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse
        do {
            let result = try await session.data(for: request)
            data = result.0
            response = result.1
        } catch {
            let description = (error as NSError).localizedDescription
            logger.error("Open Food Facts request failed: \(description, privacy: .public)")
            throw BarcodeProteinLookupError.transportFailure(description)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw BarcodeProteinLookupError.transportFailure("Non-HTTP response from Open Food Facts.")
        }
        // A 404 with a decodable `{"status":0,...}` body is Open Food Facts' normal "not found"
        // shape (verified live — see this file's header), not a transport failure, so only a
        // genuine server error (5xx) is treated as one here; everything else falls through to the
        // decode step below and is resolved from the body's own `status` field.
        guard httpResponse.statusCode < 500 else {
            throw BarcodeProteinLookupError.transportFailure("Open Food Facts returned HTTP \(httpResponse.statusCode).")
        }

        let decoded: OpenFoodFactsResponse
        do {
            decoded = try JSONDecoder().decode(OpenFoodFactsResponse.self, from: data)
        } catch {
            logger.error("Open Food Facts response failed to decode: \(String(describing: error), privacy: .public)")
            throw BarcodeProteinLookupError.decodingFailure
        }

        guard decoded.status == 1, let product = decoded.product else {
            logger.notice("Open Food Facts: no product for this barcode (status_verbose: \(decoded.statusVerbose ?? "n/a", privacy: .public)).")
            throw BarcodeProteinLookupError.productNotFound
        }

        guard let extraction = Self.extractProtein(from: product) else {
            logger.notice("Open Food Facts: product found but no usable protein figure.")
            throw BarcodeProteinLookupError.noNutritionData
        }

        return BarcodeProduct(
            barcode: decoded.code ?? barcode,
            name: product.productName,
            brand: Self.firstBrand(from: product.brands),
            proteinGramsPerServing: extraction.gramsPerServing,
            proteinBasis: extraction.basis,
            proteinGramsPer100g: product.nutriments?.proteinsPer100g,
            servingSizeGrams: product.servingQuantity,
            servingSizeDescription: product.servingSize,
            imageURL: product.imageFrontURL.flatMap { URL(string: $0) }
        )
    }

    private static func requestURL(for barcode: String) throws -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = apiHost
        components.path = "\(apiPath)\(barcode).json"
        components.queryItems = [URLQueryItem(name: "fields", value: requestedFields)]
        guard let url = components.url else {
            // Only reachable if `barcode` somehow contains characters `normalizedBarcode(from:)`
            // should already have rejected — kept as a typed throw rather than a force-unwrap so a
            // gap in that validation degrades to a normal error instead of a crash.
            throw BarcodeProteinLookupError.invalidBarcode
        }
        return url
    }

    // MARK: - Pure helpers (internal, not `private`, so a future `CoreTests` can exercise these
    // directly without a network call — same convention `QuickRepeatSuggester`'s pure clustering
    // functions use in this same directory).

    /// Rejects obviously-not-a-barcode input before spending a network round trip on it, without
    /// hard-coding an exact digit count: Open Food Facts normalizes across symbologies server-side
    /// (this file's header: a scanned 12-digit UPC-A came back zero-padded to a 13-digit EAN-13),
    /// so this only bounds length loosely (UPC-E's 6 through GTIN-14's 14) and requires ASCII
    /// digits only.
    static func normalizedBarcode(from raw: String) throws -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed.count >= minimumBarcodeLength,
              trimmed.count <= maximumBarcodeLength,
              trimmed.allSatisfy({ $0.isASCII && $0.isNumber })
        else {
            throw BarcodeProteinLookupError.invalidBarcode
        }
        return trimmed
    }

    /// Open Food Facts stores `brands` as a free-text, comma-separated list (e.g.
    /// `"Nutella, Ferrero"`, verified live — see header). Returns just the first, trimmed entry as
    /// a clean single display brand; `nil` if `brands` is absent or blank.
    static func firstBrand(from brands: String?) -> String? {
        guard let brands else { return nil }
        guard let first = brands.split(separator: ",").first else { return nil }
        let trimmed = first.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Extracts a protein-per-serving figure (and how it was derived) from a decoded product, or
    /// `nil` if there's no usable protein data at all. See ``BarcodeProteinEstimateBasis`` for what
    /// each outcome means; this is the one place that decides among the three real shapes this
    /// file's header verified live (reported-per-serving, computable-from-per-100g, per-100g-only).
    static func extractProtein(from product: OpenFoodFactsProduct) -> (gramsPerServing: Double?, basis: BarcodeProteinEstimateBasis)? {
        guard let nutriments = product.nutriments else { return nil }

        // Every real response this file's header checked reported protein in grams
        // (`proteins_unit: "g"`). A present-but-different unit is a shape this file doesn't know
        // how to interpret — refusing rather than guessing a conversion (see header's "explicitly
        // NOT verified live" note).
        if let unit = nutriments.proteinsUnit, unit.lowercased() != "g" {
            return nil
        }

        if let perServing = nutriments.proteinsServing {
            return (perServing, .reportedPerServing)
        }

        if let per100g = nutriments.proteinsPer100g {
            if let servingGrams = product.servingQuantity, servingGrams > 0 {
                return (per100g / 100 * servingGrams, .computedFromPer100g)
            }
            // No serving size at all (the real Nutella case this file's header verified) — still
            // real, usable data (per-100g), just not enough to compute a per-serving figure.
            return (nil, .per100gOnly)
        }

        return nil
    }
}

// MARK: - Open Food Facts JSON decoding

/// Top-level `https://world.openfoodfacts.org/api/v2/product/<barcode>.json` response shape,
/// verified live against four real barcodes (see this file's header). `status` is `1` for a found
/// product, `0` otherwise (both observed directly as JSON numbers, not strings, across every real
/// call this file's header made) — `product` is present only when `status == 1`.
struct OpenFoodFactsResponse: Decodable {
    let code: String?
    let status: Int
    let statusVerbose: String?
    let product: OpenFoodFactsProduct?

    private enum CodingKeys: String, CodingKey {
        case code, status, product
        case statusVerbose = "status_verbose"
    }
}

/// The `product` object, narrowed to exactly the fields `requestedFields` asks Open Food Facts
/// for. Custom `init(from:)` (rather than a synthesized one) so a handful of numeric-looking
/// fields that this file has seen Open Food Facts' crowd-sourced data occasionally serialize
/// inconsistently degrade to `nil` instead of failing the whole decode — see `flexibleDouble(_:_:)`.
struct OpenFoodFactsProduct: Decodable {
    let productName: String?
    let brands: String?
    let servingSize: String?
    let servingQuantity: Double?
    let imageFrontURL: String?
    let nutriments: OpenFoodFactsNutriments?

    private enum CodingKeys: String, CodingKey {
        case productName = "product_name"
        case brands
        case servingSize = "serving_size"
        case servingQuantity = "serving_quantity"
        case imageFrontURL = "image_front_url"
        case nutriments
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        productName = try? container.decodeIfPresent(String.self, forKey: .productName)
        brands = try? container.decodeIfPresent(String.self, forKey: .brands)
        servingSize = try? container.decodeIfPresent(String.self, forKey: .servingSize)
        servingQuantity = flexibleDouble(container, .servingQuantity)
        imageFrontURL = try? container.decodeIfPresent(String.self, forKey: .imageFrontURL)
        nutriments = try? container.decodeIfPresent(OpenFoodFactsNutriments.self, forKey: .nutriments)
    }
}

/// `product.nutriments`, narrowed to the protein-related keys this file reads. Verified live
/// (header): `proteins_100g`/`proteins_serving` are plain JSON numbers on every real product this
/// task checked, but Open Food Facts' underlying database is community-edited and not
/// schema-enforced, so `flexibleDouble(_:_:)` defensively also accepts a numeric-looking string for
/// either field rather than risking a hard decode failure on some other product this task didn't
/// happen to check.
struct OpenFoodFactsNutriments: Decodable {
    let proteinsPer100g: Double?
    let proteinsServing: Double?
    let proteinsUnit: String?

    private enum CodingKeys: String, CodingKey {
        case proteinsPer100g = "proteins_100g"
        case proteinsServing = "proteins_serving"
        case proteinsUnit = "proteins_unit"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        proteinsPer100g = flexibleDouble(container, .proteinsPer100g)
        proteinsServing = flexibleDouble(container, .proteinsServing)
        proteinsUnit = try? container.decodeIfPresent(String.self, forKey: .proteinsUnit)
    }
}

/// Shared by `OpenFoodFactsProduct`/`OpenFoodFactsNutriments`'s custom decoders: tries `Double`
/// first (the shape this file actually observed live), then a numeric-looking `String` (defensive
/// fallback for Open Food Facts' crowd-sourced data — see those types' doc comments). Never throws;
/// an unparseable or missing value just decodes to `nil`, which `extractProtein(from:)` already
/// treats as "no data" rather than a decode error.
private func flexibleDouble<Key: CodingKey>(
    _ container: KeyedDecodingContainer<Key>,
    _ key: Key
) -> Double? {
    if let value = try? container.decode(Double.self, forKey: key) {
        return value
    }
    if let string = try? container.decode(String.self, forKey: key) {
        return Double(string)
    }
    return nil
}
