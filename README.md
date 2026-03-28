# 🚇 Ruse Metro Tycoon

An interactive Flutter map simulation and tycoon game based on a fictional Metro system in Ruse, Bulgaria. Built using `flutter_map` and OpenStreetMap, this app simulates real-time train movements, calculates route physics, and includes fun tycoon mechanics!

## 📱 Play the Game (Android Download)
Want to try out the simulation? You can download and install the Android app directly to your phone:

**👉 [Download the latest Android APK here](./apk/app-release.apk)**

*(Note: You may need to allow "Install from Unknown Sources" on your Android device to install).*

## 🚀 Features
* **🗺️ Interactive Map:** Full OpenStreetMap integration with custom markers, heatmaps for station popularity, and a toggleable line legend.
* **🚂 Live Train Physics:** Trains physically move along the map in real-time. The `RoutePhysics` engine calculates segment travel times, arrival estimates, and station stops.
* **💰 Tycoon Mechanics:** Passive income generation based on active lines. Buy "Ruse Metro Passes" with your earnings and track your total distance traveled!
* **📍 Smart Route Planner:** Select a start and end destination to calculate travel times, ticket prices, and direct vs. transfer routes.
* **🚨 Chaos Mode (Admin):** Trigger random train breakdowns! A broken train stops generating money until you tap it multiple times with the "repair wrench" to fix it.

## 💻 Tech Stack
* **Framework:** Flutter / Dart
* **Map Engine:** `flutter_map`
* **Tile Provider:** OpenStreetMap
* **Math/Geospatial:** `latlong2` for coordinate physics and distance calculations.

## 🛠️ How to Build from Source
If you want to run this project locally on your computer:
1. Clone the repository.
2. Run `flutter pub get` to install dependencies.
3. Run `flutter run` to launch on your connected device or emulator.