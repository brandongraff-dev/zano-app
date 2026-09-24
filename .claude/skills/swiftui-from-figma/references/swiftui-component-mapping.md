# SwiftUI component mapping

Use this reference when converting Figma designs into SwiftUI.

## Common mappings

- Screen frame -> top-level `View`
- Vertical auto layout -> `VStack`
- Horizontal auto layout -> `HStack`
- Absolute overlay -> `ZStack` / `.overlay`
- Scroll frame -> `ScrollView`
- List of same rows -> `ForEach`
- Figma component -> SwiftUI subview
- Figma variants -> enum + switch, or parameters
- Color variable -> design system color / `Color` extension
- Text style -> design system font / helper modifier

## Layout guidelines

- Use `Spacer()` carefully; prefer clear stacks and padding
- Group magic numbers in a local `Constants` enum when no design system exists
- Use `.frame(maxWidth: .infinity, alignment: ...)` for flexible cards/buttons
- Avoid fixed heights unless the design truly requires them
- Handle safe areas intentionally

## Preview states

Every important screen should have previews for:

- content
- loading
- empty
- error

Use realistic sample data and avoid network calls in previews.
