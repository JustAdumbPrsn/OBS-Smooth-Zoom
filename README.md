# OBS Smooth Zoom
[![Star this Project](https://img.shields.io/badge/Star_this_Repo-f1c40f?style=for-the-badge&logo=github&logoColor=white&labelColor=222)](https://github.com/JustAdumbPrsn/OBS-Smooth-Zoom)
![OBS Version](https://img.shields.io/badge/OBS-32.0.4+-blueviolet?style=for-the-badge)
![Platform](https://img.shields.io/badge/Platform-Windows%20|%20macOS%20|%20Linux-lightgrey?style=for-the-badge)

An advanced Lua script for OBS Studio that provides high-quality cursor zoom in real time. This script replicates the polished zoom effects found in paid software like ScreenStudio and Rapidemo.

This script is based on [OBS-Zoom-To-Mouse](https://github.com/BlankSourceCode/obs-zoom-to-mouse) by BlankSourceCode.

## Demo

https://github.com/user-attachments/assets/b51a6f82-56fc-4de1-b88b-fd9ba1f07beb

---

## Features
* **Smooth Animations:** Smooth transitions for zooming in and out.
* **Dynamic Tracking:** Weighted camera following during active zoom.
* **Custom Cursors:** Support for high-resolution custom cursor and pointer images with Dynamic effects like rotate and tilt
* **Effect Integration:** Native support for Motion and Zoom blur via external plugins.

---

## Installation

1. **Download the script**
   ```bash
   git clone https://github.com/JustAdumbPrsn/OBS-Smooth-Zoom.git
   ```
   or just download `OBS-Smooth-Zoom.lua` directly from the repository.

2. **Load the script into OBS**
   - Navigate to `Tools` → `Scripts`
   - Click the `+` button and select `OBS-Smooth-Zoom.lua`

3. **Configure a display capture source**
   - Add a `Display Capture` source to your active scene
   - Select the appropriate display from the source properties

4. **Assign hotkeys**
   - Go to `File` → `Settings` → `Hotkeys`
   - Bind keys for:
     - `Toggle zoom to mouse`
     - `Toggle follow mouse during zoom` (optional)

> [!IMPORTANT]
> If you modify Windows display properties (e.g., changing monitor orientation or primary display), you must re-add your `Display Capture` source and reload the script to recalculate coordinates.

> While this script is optimized for Display Capture, you can use Window Capture by enabling `Show all sources` and manually defining source position values.

---

## Optional Configuration

### Custom Cursor Effects

The script supports custom cursor graphics with dynamic animations:

1. **Prepare cursor assets**
   - Download reference assets: `cursor.png` and `pointer.png` from the repository
   - Or provide your own high-resolution cursor images

2. **Add image sources to OBS**
   - Create two **Image** sources named `cursor` and `pointer`
   - Load your cursor graphics into these sources

3. **Configure in script settings**
   - Navigate to the **Smooth Cursor Effects** section
   - Assign `cursor` to **Arrow Cursor**
   - Assign `pointer` to **Hand Cursor**
   - Adjust scale and offset parameters to align with your system cursor

4. **Disable native cursor rendering**
   - In your Display Capture source properties, disable `Capture Cursor` to prevent duplicate cursors

### Motion and Zoom Blur Effects

For cinematic blur effects, install the [Composite Blur](https://obsproject.com/forum/resources/composite-blur.1780/) plugin:

1. **Install Composite Blur plugin**
   - Download and install from the OBS plugin repository

2. **Add filters to display capture**
   - Right-click your Display Capture source → `Filters`
   - Add two `Composite Blur` filters
   - Name them exactly: `Zoom Blur` and `Motion Blur`

3. **Configure blur filters**
   - Algorithm: `Gaussian` (quality) or `Box` (performance)
   - Blur Radius: `0.00px` (controlled programmatically by script)

4. **Enable in script settings**
   - Check the corresponding options under **Effects (Blur)**

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
---

## Troubleshooting

### Zoom coordinates are incorrect
- Re-add your Display Capture source after changing monitor configuration
- Reload the script via `Tools` → `Scripts` → Reload

### Custom cursor not appearing
- Verify image source names exactly match: `cursor` and `pointer`
- Check that source visibility is enabled
- Adjust X/Y offsets in script settings

### Blur effects not working
- Confirm Composite Blur plugin is installed
- Verify filter names exactly match: `Zoom Blur` and `Motion Blur`
- Check that filters are applied to the correct source

### Performance issues
- Switch blur algorithm from Gaussian to Box
- Reduce blur radius limits in script settings
- Lower display capture resolution or framerate

---

## Contributing

Contributions are welcome! Please follow these guidelines:

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/improvement`)
3. Commit your changes with descriptive messages
4. Test on your target platform(s)
5. Submit a pull request with a clear description of changes

---

## License

This project is licensed under the MIT License. See [LICENSE](LICENSE) for details.

---

## Acknowledgments

- Original concept and base implementation: [BlankSourceCode/obs-zoom-to-mouse](https://github.com/BlankSourceCode/obs-zoom-to-mouse)
- Blur integration: [Composite Blur](https://obsproject.com/forum/resources/composite-blur.1780/) by Exeldro

---

## Support

- **Issues**: [GitHub Issues](https://github.com/JustAdumbPrsn/OBS-Smooth-Zoom/issues)
- **Discussions**: [GitHub Discussions](https://github.com/JustAdumbPrsn/OBS-Smooth-Zoom/discussions)
- **OBS Forums**: [OBS Project Forums](https://obsproject.com/forum/)

For bug reports, please include:
- OBS version
- Operating system and version
- Script settings configuration
- Steps to reproduce the issue
