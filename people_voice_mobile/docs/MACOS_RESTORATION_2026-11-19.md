# macOS interface restoration

Reference: screenshot provided on November 19, 2026.

The macOS branch of Home now uses MacosHome. It restores the full-width brand
header, grouped scrolling sidebar, red selected destination, search entry,
image-backed lead story, author/date/subtitle, and three-column promoted stories.
The header exposes promotion, preferences, trends and the notification inbox.
Navigation preserves visited pages and the loaded news feed. Narrow windows use
a drawer. System-default appearance is dark on macOS; explicit appearance
preferences remain available.

Existing repository and page implementations provide search, categories,
community, podcasts, saved articles, publishing, account, preferences and more.
Notifications refresh on launch, foreground activation and once a minute.
No server data, publications or payments were changed.

Read-only live checks returned HTTP 200 for:

- `/api/v1/posts`
- `/api/v1/posts/featured`
- `/api/v1/categories`
- `/api/v1/promotions/pricing`
- `/api/v1/rankings?metric=comments&days=30`
- `https://podcasts.fayettevillethepeoplevoice.com/episodes`

The first article returned by the live feed matched the reference screenshot.
Stories and categories remain live data, rather than fixed screenshot content.
The pricing endpoint returned USD 500 cents / 7 days. Existing payment and
approval checks remain in their original implementations.

Validation:

- Debug macOS build succeeded; launched again through Xcode's Runner scheme.
- Seven widget tests passed across macos_home_test, feed_layout_test,
  category_cards_test and production_ui_test.
- Targeted analysis of macos_home.dart, main.dart and macos_home_test.dart passed.
- Screen capture was unavailable (`could not create image from display`), so an
  exact visual comparison of the running application remains unverified.
- Authenticated publishing, payments and administration were not exercised
  against production. Public endpoint availability does not validate those flows.
- The native build reported existing plugin warnings and missing 256/512 icon
  assets; these did not prevent compilation.

This UI work does not establish whether any unauthorized modification occurred.
