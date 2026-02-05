# OBS Smooth Zoom
[![Star this Project](https://img.shields.io/badge/Star_this_Repo-f1c40f?style=for-the-badge&logo=github&logoColor=white&labelColor=222)](https://github.com/JustAdumbPrsn/OBS-Smooth-Zoom)
![OBS Version](https://img.shields.io/badge/OBS-32.0.4+-blueviolet?style=for-the-badge)
![Platform](https://img.shields.io/badge/Platform-Windows%20|%20macOS%20|%20Linux-lightgrey?style=for-the-badge)

An advanced Lua script for OBS Studio that provides high-quality cursor zoom in real time. This script replicates the polished zoom effects found in paid software like ScreenStudio and Rapidemo.

This script is based on [OBS-Zoom-To-Mouse](https://github.com/BlankSourceCode/obs-zoom-to-mouse) by BlankSourceCode.

Example Video:

<video src="https://github.com/user-attachments/assets/b51a6f82-56fc-4de1-b88b-fd9ba1f07beb" autoplay loop muted playsinline controls width="100%">
</video>

---

## Key Features

* **Smooth Animations:** Smooth transitions for zooming in and out.
* **Dynamic Tracking:** Weighted camera following during active zoom.
* **Custom Cursors:** Support for high-resolution custom cursor and pointer images with Dynamic effects like rotate and tilt
* **Effect Integration:** Native support for Motion and Zoom blur via external plugins.

---

## Installation

1.  **Download:** Clone this repository or save a copy of `OBS-Smooth-Zoom.lua`.
2.  **Add Script:**
    * Launch OBS and navigate to `Tools` > `Scripts`.
    * Click the `+` icon and select `OBS-Smooth-Zoom.lua`.
3.  **Setup Source:**
    * Add a `Display Capture` source to your scene.
4.  **Configure Hotkeys:**
    * Go to `File` > `Settings` > `Hotkeys`.
    * Assign keys for `Toggle zoom to mouse` and `Toggle follow mouse during zoom` (Optional).

> [!IMPORTANT]
> If you modify Windows display properties (e.g., changing monitor orientation or primary display), you must re-add your `Display Capture` source and reload the script to recalculate coordinates.

> While this script is optimized for Display Capture, you can use Window Capture by enabling `Show all sources` and manually defining source position values.

---

## Advanced Configuration

### Custom Cursor Effects
To use smooth custom cursors, you can add your own cursor:
1.  Download the cursor.png & pointer.png from the github repository (If you want exact ones I am using)
2.  Add two **Image** sources to OBS named `cursor` and `pointer`.
3.  In the script settings, navigate to the **Smooth Cursor Effects** section.
4.  Assign the `cursor` source to **Arrow Cursor** and the `pointer` source to **Hand Cursor**.
5.  Adjust the Scale and X/Y offsets and  to align the images with your hardware cursor.
6.  **Note:** It is recommended to disable `Capture Cursor` in your original Display Capture source to avoid duplicate cursors.

### Motion and Zoom Blur
This script supports cinematic blur effects through the [Composite Blur](https://obsproject.com/forum/resources/composite-blur.1780/) plugin.
1.  Install the Composite Blur plugin.
2.  Add two `Composite Blur` filters to your **Display Capture** source.
3.  Name them `Zoom Blur` and `Motion Blur`.
4.  Set both algorithms to **Gaussian/Box** (Box for performance) and Blur Radius to `0.00px` as script will automatically handle blur.
5.  In the script settings, enable the corresponding options under the **Effects (Blur)** section.

---

## Compatibility

The following specifications are recommended for optimal performance and stability.

| Component | Specification |
| :--- | :--- |
| **Primary OS** | Windows 11 (Verified) |
| **Secondary OS** | macOS, Linux (Experimental/Community Tested) |
| **OBS Version** | 32.0.4+ |
| **Source Type** | Optimized for `Display Capture` |

---

## Platform Support

While the core interpolation logic is cross-platform, advanced hooks for input detection vary by operating system.

| Feature | Windows | Linux | macOS |
| :--- | :---: | :---: | :---: |
| **Smooth Zooming** | ![Supported](https://img.shields.io/badge/-Supported-brightgreen?style=flat-square) | ![Supported](https://img.shields.io/badge/-Supported-brightgreen?style=flat-square) | ![Partial](https://img.shields.io/badge/-Supported*-brightgreen?style=flat-square) |
| **Mouse Tracking** | ![Supported](https://img.shields.io/badge/-Supported-brightgreen?style=flat-square) | ![Supported](https://img.shields.io/badge/-Supported-brightgreen?style=flat-square) | ![Supported](https://img.shields.io/badge/-Supported-brightgreen?style=flat-square) |
| **Click Animations** | ![Supported](https://img.shields.io/badge/-Supported-brightgreen?style=flat-square) | ![Not Supported](https://img.shields.io/badge/-Not_Supported-lightgrey?style=flat-square) | ![Not Supported](https://img.shields.io/badge/-Not_Supported-lightgrey?style=flat-square) |
| **Hand/Pointer Detection** | ![Supported](https://img.shields.io/badge/-Supported-brightgreen?style=flat-square) | ![Not Supported](https://img.shields.io/badge/-Not_Supported-lightgrey?style=flat-square) | ![Not Supported](https://img.shields.io/badge/-Not_Supported-lightgrey?style=flat-square) |

### Technical Limitations

* **macOS Architecture:** Smooth zooming functionality on macOS relies on `libobjc`. Users on modern macOS versions may need to verify system permissions for OBS to access the display buffer effectively.
* **Window Capture:** While `Display Capture` is the primary target, other sources can be utilized by enabling **Show all sources** and providing manual coordinate values within the script settings.
* **Linux Environment:** Support is currently focused on X11; Wayland users may experience varying results depending on the compositor’s security policy.
---

### Platform-Specific Notes

* **macOS Support:** Smooth zooming on macOS depends on `libobjc` and specific system permissions. Depending on your version of macOS (notably Sonoma and later), additional security overrides may be required for the script to access the display buffer correctly.
* **Linux Support:** Compatibility is confirmed for X11 environments. Wayland support may vary based on the specific compositor's screen-sharing protocols.
