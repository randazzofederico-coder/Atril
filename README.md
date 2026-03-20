# Atril Digital - Atril

Atril Digital is a robust Flutter application designed for musicians to manage, read, and annotate PDF sheet music. Optimized for stage performance with a focus on stability and ease of use.

## ✨ Key Features

- **Sheet Music Library**: Infinite nesting of folders, search, and full file management (rename, move, delete).
- **Advanced PDF Reader**: Fast rendering engine with vertical scroll, page scrubbing, and seamless navigation between setlist items.
- **Photo Scanner (Camera to PDF)**:
  - Capture or import multiple pages.
  - **3x3 Homography Perspective Correction**: Fix camera angles with professional-grade quadrilateral warping.
  - **Image Processing**: B/W thresholding, brightness, and contrast adjustments—all processed in background Isolates for zero UI lag.
- **Smart Annotations**: Non-destructive pen and highlighter layers, saved per document or per setlist.
- **Setlist Management**: Organize scores for performance and navigate them with a single tap.
- **Robust Backup**: Export and import your entire library and configuration in a single `.atril` file.

## 🚀 Tech Stack

- **Framework**: Flutter (Dart)
- **Database**: Drift (SQLite)
- **PDF Core**: Syncfusion & pdfrx
- **Image Processing**: Pure Dart `image` package with custom homography math.
- **Architecture**: Domain-Driven Design with a Facade pattern (`AppData`).

## 🛠️ Getting Started

1. Clone the repository.
2. Run `flutter pub get`.
3. Run `flutter run`.

---
*Developed for musicians who need reliability on stage.*
