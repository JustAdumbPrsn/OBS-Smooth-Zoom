# OBS-Smooth-Zoom
An OBS Lua script which adds smooth zoom functionality and smooth cursor with tons of customizing options.

This script is based on [OBS-Zoom-To-Mouse](https://github.com/BlankSourceCode/obs-zoom-to-mouse) by [BlankSourceCode](https://github.com/BlankSourceCode)
The idea was to add the similar polished zoom and cursors similar to paid apps like ScreenStudio and Rapidemo has.

Currently works with OBS 32.0.4

**Note:** Altough this script should work on MacOS & Linux, I have only tested it on Windows 11 

<video src="https://github.com/user-attachments/assets/b51a6f82-56fc-4de1-b88b-fd9ba1f07beb" autoplay loop muted playsinline controls width="100%">
</video>

## Install
1. Git clone the repo (or just save a copy of `OBS-Smooth-Zoom.lua`)
1. Launch OBS
1. In OBS, add a `Display Capture` source (if you don't have one already)
1. In OBS, open Tools -> Scripts
1. In the Scripts window, press the `+` button to add a new script
1. Find and add the `OBS-Smooth-Zoom.lua` script
1. In OBS, open File -> Settings -> Hotkeys 
   * Add a hotkey for `Toggle zoom to mouse` to zoom in and out
   * Add a hotkey for `Toggle follow mouse during zoom` to turn mouse tracking on and off (*Optional*)
   
   **Note:** If you change your desktop display properties in Windows (such as moving a monitor, changing your primary display, updating the orientation of a display), you will need to re-add your display capture source in OBS for it to update the values that the script uses for its auto calculations. You will then need to reload the script.

   **Note:** Only works on `Display Capture` sources (automatically). In theory it should be able to work on window captures too, if there was a way to get the mouse position relative to that specific window. You can now enable the `Show all sources` option to select a non-display capture source, but you MUST set manual source position values

   
1. **(Optional)** | To have custom cursor
     1. Download cursor.png and pointer.png, or if you have your own cursor and pointer png use those instead
     2. In OBS, add two `Image` sources
     3. name one `cursor` and name one `pointer` and use the respective image png files for those
     4. In OBS, open Tools -> Scripts, scroll down in the script settings to find `Smooth Cursor Effects` section and set Arrow Cursor Source as cursor and Hand Cursor Source as pointer (the image sources we          created)
     5. Set desired cursor scale and X,Y offset to align the custom images to your real mouse cursor.
     6. At the end i recommend to disable `Capture Cursor` property in your display source since now the custom cursor will be visible so you will not need the original Cursor

2. **(Optional)** | To have Motion & Zoom blur
     1. Install [Composite Blur](https://obsproject.com/forum/resources/composite-blur.1780/) plugin for OBS
     2. Go to Filters of your Display Capture
     3. press the `+` button to add two new `Composite Blur` filters, name one as `Zoom Blur` and other as `Motion Blur`
     4. For Zoom Blur, set Blur Algorithm as `Gaussian/Box` (Box as better performance) and set Blur type to `Zoom`, change Blur radius to 0.00px
     5. For Motion Blur, set Blur Alogithm as `Gaussian/Box` (Box as better performance) and set Blur type to `Directional`, change Blur radius to 0.00px
     6. Now, go to Tools -> Scripts -> OBS-Smooth-Zoom.lua, scroll to `Effects (Blur)` section and enable any of the two blur options you want (or both)


