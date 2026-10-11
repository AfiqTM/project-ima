# i-Ma'luum for iOS (SwiftUI)

AMOLED-black SwiftUI client for i-Ma'luum with accent colour `#9D846B`.

## Build without a Mac (GitHub Actions)

1. Create a new **private** GitHub repo and upload everything in this folder (keep the `.github` folder).
2. Open the **Actions** tab -> *Build IPA* -> **Run workflow** (it also runs on every push to `main`).
3. When the run finishes, download the **IIUMApp-ipa** artifact and unzip it to get `IIUMApp.ipa`.
4. The IPA is unsigned. Install it with **Sideloadly** or **AltStore** using your free Apple ID (re-sign every 7 days).

Bundle ID is `com.example.imaluum` (change it in `project.yml` if signing complains).

## How it works

- You sign in once inside an embedded web view (the real i-Ma'luum / CAS page). The app never sees your password.
- A hidden web view loads the pages and reads their tables, which are shown as native screens.
- The timetable page is parsed explicitly (`TimetableParser`). Other tabs find their pages from the site's own
  sidebar links and render whatever tables/links they contain, so they may need styling tweaks per page.
- Last loaded data is cached for offline viewing. "Explore with demo data" works without logging in.
