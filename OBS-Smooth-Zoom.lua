--
-- OBS Zoom to Mouse
-- An OBS Lua script which adds smooth zoom functionality and smooth cursor with tons of customizing options. 
-- Copyright (c) JustAdumbPrsn
-- Based on work Copyright (c) BlankSourceCode. All rights reserved.
--

local obs = obslua
local ffi = require("ffi")
local VERSION = "1.0"
local TRANSFORM_FILTER_NAME = "obs-zoom-to-mouse-transform"
local ZOOM_BLUR_FILTER_NAME = "Zoom Blur"
local MOTION_BLUR_FILTER_NAME = "Motion Blur"
local BLUR_FILTER_ID = "composite_blur"

local socket_available, socket = pcall(require, "ljsocket")
local socket_server = nil
local socket_mouse = nil

-- Windows API for advanced mouse/cursor detection
local click_detection_available = false
local cursor_shape_detection_available = false
local hCursorHand = nil

if ffi and ffi.os == "Windows" then
    pcall(function()
        ffi.cdef[[
            short GetAsyncKeyState(int vKey);
            
            typedef struct {
                unsigned long cbSize;
                unsigned long flags;
                void* hCursor;
                struct { long x; long y; } ptScreenPos;
            } CURSORINFO_SCRIPT;
            int GetCursorInfo(CURSORINFO_SCRIPT *pci);
            void* LoadCursorA(void* hInstance, const char* lpCursorName);
        ]]
        click_detection_available = true
        
        -- Get handle for "Hand" cursor (Pointer)
        -- IDC_HAND is 32649
        hCursorHand = ffi.C.LoadCursorA(nil, ffi.cast("const char*", 32649))
        cursor_shape_detection_available = (hCursorHand ~= nil)
    end)
end

local source_name = ""
local source = nil
local sceneitem = nil
local sceneitem_info_orig = nil
local sceneitem_crop_orig = nil
local sceneitem_info = nil
local crop_filter = nil
local crop_filter_info = { x=0, y=0, w=0, h=0 }
local zoom_blur_filter = nil
local motion_blur_filter = nil
local zoom_blur_settings = nil
local motion_blur_settings = nil
local crop_filter_info_orig = { x = 0, y = 0, w = 0, h = 0 }
local monitor_info = nil
local zoom_info = {
    source_size = { width = 0, height = 0 },
    source_crop = { x = 0, y = 0, w = 0, h = 0 },
    source_crop_filter = { x = 0, y = 0, w = 0, h = 0 },
    zoom_to = 2
}
local zoom_time = 0
local zoom_target = nil
local locked_center = nil
local locked_last_pos = nil
local hotkey_zoom_id = nil
local hotkey_follow_id = nil
local is_timer_running = false

local win_point = nil
local x11_display = nil
local x11_root = nil
local x11_mouse = nil
local osx_lib = nil
local osx_nsevent = nil
local osx_mouse_location = nil

local use_auto_follow_mouse = true
local use_follow_outside_bounds = false
local is_following_mouse = false
local follow_speed = 0.1
local follow_smooth_time = 0.1 -- For SmoothDamp
local follow_dead_zone = 0 -- Pixels
local tracked_mouse_pos = { x = 0, y = 0 } -- For dead zone tracking
local smoothed_mouse_pos = { x = 0, y = 0 } -- For weighted smoothing
local zoom_value = 2
local zoom_speed = 0.06 -- Deprecated in favor of duration, but kept for compatibility or fallback
local zoom_duration = 0.5 -- Seconds
local zoom_overshoot = 0.0 -- 0 to 1
local zoom_preset = "Smooth" -- Smooth, Bounce, Snappy, Custom

local use_zoom_blur = false
local zoom_blur_intensity = 5
local zoom_blur_inactive_radius = 2.0

local use_motion_blur = false
local motion_blur_intensity = 1.0

local allow_all_sources = false
local use_monitor_override = false
local monitor_override_x = 0
local monitor_override_y = 0
local monitor_override_w = 0

-- Preset Management
local global_presets = {
    Smooth = { dur = 0.8, ovr = 0.0, smt = 0.25 },
    Bounce = { dur = 0.6, ovr = 0.35, smt = 0.15 },
    Snappy = { dur = 0.3, ovr = 0.0, smt = 0.05 }
}
local global_settings = nil

local function refresh_presets_table(settings)
    if not settings then return end
    -- Reset to defaults first
    global_presets = {
        Smooth = { dur = 0.8, ovr = 0.0, smt = 0.25 },
        Bounce = { dur = 0.6, ovr = 0.35, smt = 0.15 },
        Snappy = { dur = 0.3, ovr = 0.0, smt = 0.05 }
    }
    
    local array = obs.obs_data_get_array(settings, "custom_presets")
    if array then
        local count = obs.obs_data_array_count(array)
        for i = 0, count - 1 do
            local item = obs.obs_data_array_item(array, i)
            local name = obs.obs_data_get_string(item, "name")
            if name ~= "" then
                global_presets[name] = {
                    dur = obs.obs_data_get_double(item, "dur"),
                    ovr = obs.obs_data_get_double(item, "ovr"),
                    smt = obs.obs_data_get_double(item, "smt")
                }
            end
            obs.obs_data_release(item)
        end
        obs.obs_data_array_release(array)
    end
end
local monitor_override_h = 0
local monitor_override_sx = 0
local monitor_override_sy = 0
local monitor_override_dw = 0
local monitor_override_dh = 0
local use_socket = false
local socket_port = 0
local socket_poll = 1000
local debug_logs = false
local is_obs_loaded = false
local is_script_loaded = false

-- Smooth Cursor Settings
local cursor_source_name = ""
local cursor_pointer_source_name = ""
local cursor_source = nil
local cursor_pointer_source = nil
local cursor_sceneitem = nil
local cursor_pointer_sceneitem = nil
local cursor_scale = 1.0
local cursor_click_scale = 0.78
local cursor_current_scale = 1.0 -- Animated scale
local velocity_cursor_scale = { val = 0 }
local cursor_pos = { x = 0, y = 0 } -- Cursor's smoothed position (separate from camera)
local velocity_cursor_x = { val = 0 }
local velocity_cursor_y = { val = 0 }
local cursor_smooth_time = 0.1 -- Weighted follow
local cursor_offset_x = -6 -- Offset
local cursor_offset_y = -2 -- Offset
local cursor_was_pointer = false -- Track state for swap anim
local cursor_swap_pulse = 1.0 -- Dynamic pulse factor for swapping
local velocity_cursor_swap = { val = 0 }

-- Dynamic Cursor Physics
local cursor_rotation_mode = "None"
local cursor_angle_offset = 0.0
local cursor_tilt_strength = 0.0
local cursor_current_rot = 0.0
local velocity_cursor_rot = { val = 0 }
local cursor_last_move_dir = { x = 0, y = 0 }

-- State variables for SmoothDamp
local velocity_x = { val = 0 }
local velocity_y = { val = 0 }
local velocity_mx = { val = 0 } -- Mouse velocity X
local velocity_my = { val = 0 } -- Mouse velocity Y
local velocity_w = { val = 0 }
local velocity_h = { val = 0 }
local last_blur_radius = 0
local last_camera_x = 0
local last_camera_y = 0
local current_blur_type = -1 -- -1: None, 2: Zoom, 3: Motion

local ZoomState = {
    None = 0,
    ZoomingIn = 1,
    ZoomingOut = 2,
    ZoomedIn = 3,
}
local zoom_state = ZoomState.None

local version = obs.obs_get_version_string()
local m1, m2 = version:match("(%d+%.%d+)%.(%d+)")
local major = tonumber(m1) or 0
local minor = tonumber(m2) or 0

-- Define the mouse cursor functions for each platform
if ffi.os == "Windows" then
    ffi.cdef[[
        typedef int BOOL;
        typedef struct{
            long x;
            long y;
        } POINT, *LPPOINT;
        BOOL GetCursorPos(LPPOINT);
    ]]
    win_point = ffi.new("POINT[1]")
elseif ffi.os == "Linux" then
    ffi.cdef[[
        typedef unsigned long XID;
        typedef XID Window;
        typedef void Display;
        Display* XOpenDisplay(char*);
        XID XDefaultRootWindow(Display *display);
        int XQueryPointer(Display*, Window, Window*, Window*, int*, int*, int*, int*, unsigned int*);
        int XCloseDisplay(Display*);
    ]]

    x11_lib = ffi.load("X11.so.6")
    x11_display = x11_lib.XOpenDisplay(nil)
    if x11_display ~= nil then
        x11_root = x11_lib.XDefaultRootWindow(x11_display)
        x11_mouse = {
            root_win = ffi.new("Window[1]"),
            child_win = ffi.new("Window[1]"),
            root_x = ffi.new("int[1]"),
            root_y = ffi.new("int[1]"),
            win_x = ffi.new("int[1]"),
            win_y = ffi.new("int[1]"),
            mask = ffi.new("unsigned int[1]")
        }
    end
elseif ffi.os == "OSX" then
    ffi.cdef[[
        typedef struct {
            double x;
            double y;
        } CGPoint;
        typedef void* SEL;
        typedef void* id;
        typedef void* Method;

        SEL sel_registerName(const char *str);
        id objc_getClass(const char*);
        Method class_getClassMethod(id cls, SEL name);
        void* method_getImplementation(Method);
        int access(const char *path, int amode);
    ]]

    osx_lib = ffi.load("libobjc")
    if osx_lib ~= nil then
        osx_nsevent = {
            class = osx_lib.objc_getClass("NSEvent"),
            sel = osx_lib.sel_registerName("mouseLocation")
        }
        local method = osx_lib.class_getClassMethod(osx_nsevent.class, osx_nsevent.sel)
        if method ~= nil then
            local imp = osx_lib.method_getImplementation(method)
            osx_mouse_location = ffi.cast("CGPoint(*)(void*, void*)", imp)
        end
    end
end

---
-- Get the current mouse position
---@return table Mouse position
function get_mouse_pos()
    local mouse = { x = 0, y = 0 }

    if socket_mouse ~= nil then
        mouse.x = socket_mouse.x
        mouse.y = socket_mouse.y
    else
        if ffi.os == "Windows" then
            if win_point and ffi.C.GetCursorPos(win_point) ~= 0 then
                mouse.x = win_point[0].x
                mouse.y = win_point[0].y
            end
        elseif ffi.os == "Linux" then
            if x11_lib ~= nil and x11_display ~= nil and x11_root ~= nil and x11_mouse ~= nil then
                if x11_lib.XQueryPointer(x11_display, x11_root, x11_mouse.root_win, x11_mouse.child_win, x11_mouse.root_x, x11_mouse.root_y, x11_mouse.win_x, x11_mouse.win_y, x11_mouse.mask) ~= 0 then
                    mouse.x = tonumber(x11_mouse.win_x[0])
                    mouse.y = tonumber(x11_mouse.win_y[0])
                end
            end
        elseif ffi.os == "OSX" then
            if osx_lib ~= nil and osx_nsevent ~= nil and osx_mouse_location ~= nil then
                local point = osx_mouse_location(osx_nsevent.class, osx_nsevent.sel)
                mouse.x = point.x
                if monitor_info ~= nil then
                    if monitor_info.display_height > 0 then
                        mouse.y = monitor_info.display_height - point.y
                    else
                        mouse.y = monitor_info.height - point.y
                    end
                end
            end
        end
    end

    return mouse
end

---
-- Get the information about display capture sources for the current platform
---@return any
function get_dc_info()
    if ffi.os == "Windows" then
        return {
            source_id = "monitor_capture",
            prop_id = "monitor_id",
            prop_type = "string"
        }
    elseif ffi.os == "Linux" then
        return {
            source_id = "xshm_input",
            prop_id = "screen",
            prop_type = "int"
        }
    elseif ffi.os == "OSX" then
        if major > 29.0 then
            return {
                source_id = "screen_capture",
                prop_id = "display_uuid",
                prop_type = "string"
            }
        else
            return {
                source_id = "display_capture",
                prop_id = "display",
                prop_type = "int"
            }
        end
    end

    return nil
end

---
-- Logs a message to the OBS script console
---@param msg string The message to log
function log(msg)
    if debug_logs then
        obs.script_log(obs.OBS_LOG_INFO, msg)
    end
end

---
-- Format the given lua table into a string
---@param tbl any
---@param indent any
---@return string result The formatted string
function format_table(tbl, indent)
    if not indent then
        indent = 0
    end

    local str = "{\n"
    for key, value in pairs(tbl) do
        local tabs = string.rep("  ", indent + 1)
        if type(value) == "table" then
            str = str .. tabs .. key .. " = " .. format_table(value, indent + 1) .. ",\n"
        else
            str = str .. tabs .. key .. " = " .. tostring(value) .. ",\n"
        end
    end
    str = str .. string.rep("  ", indent) .. "}"

    return str
end

--
-- Easing Functions
--
local Easing = {
    Cubic = {
        EaseOut = function(t)
            t = t - 1
            return t * t * t + 1
        end
    },
    Expo = {
        EaseOut = function(t)
            return (t == 1) and 1 or (-math.pow(2, -10 * t) + 1)
        end
    },
    Back = {
        EaseOut = function(t, overshoot)
            if not overshoot then overshoot = 1.70158 end
            t = t - 1
            return t * t * ((overshoot + 1) * t + overshoot) + 1
        end
    }
}

--
-- SmoothDamp
-- A continuously differentiable smoothing algorithm (critically damped spring)
--
-- current: number - The current position
-- target: number - The target position
-- currentVelocity: table - { val = number } (passed by reference to maintain state)
-- smoothTime: number - Approximately the time it will take to reach the target
-- maxSpeed: number - The maximum speed
-- deltaTime: number - The time since the last call to this function
-- return: number - The new value
function SmoothDamp(current, target, currentVelocity, smoothTime, maxSpeed, deltaTime)
    smoothTime = math.max(0.0001, smoothTime)
    local omega = 2 / smoothTime

    local x = omega * deltaTime
    local exp = 1 / (1 + x + 0.48 * x * x + 0.235 * x * x * x)
    local change = current - target
    local originalTo = target

    -- Clamp maximum speed
    local maxChange = maxSpeed * smoothTime
    change = clamp(-maxChange, maxChange, change)
    target = current - change

    local temp = (currentVelocity.val + omega * change) * deltaTime
    currentVelocity.val = (currentVelocity.val - omega * temp) * exp
    local output = target + (change + temp) * exp

    -- Prevent overshooting
    if (originalTo - current > 0) == (output > originalTo) then
        output = originalTo
        currentVelocity.val = (output - originalTo) / deltaTime
    end

    return output
end

---
-- Clamps a given value between min and max
---@param min number The min value
---@param max number The max value
---@param value number The number to clamp
---@return number result the clamped number
function clamp(min, max, value)
    return math.max(min, math.min(max, value))
end

---
-- Linear interpolate between v0 and v1
---@param v0 number The start position
---@param v1 number The end position
---@param t number Time
---@return number value The interpolated value
function lerp(v0, v1, t)
    return v0 * (1 - t) + v1 * t;
end

-- Helper to get reliable delta time
local last_tick_time = 0
function get_dt()
    local now = os.clock()
    local dt = now - last_tick_time
    last_tick_time = now
    
    -- Clamp dt to avoid huge jumps if the script lagged
    if dt > 0.1 then dt = 0.016 end 
    if dt < 0.001 then dt = 0.001 end -- preventing div by zero/infinity
    return dt
end

---
-- Get the size and position of the monitor so that we know the top-left mouse point
---@param source any The OBS source
---@return table|nil monitor_info The monitor size/top-left point
function get_monitor_info(source)
    local info = nil

    -- Only do the expensive look up if we are using automatic calculations on a display source
    if is_display_capture(source) and not use_monitor_override then
        local dc_info = get_dc_info()
        if dc_info ~= nil then
            local props = obs.obs_source_properties(source)
            if props ~= nil then
                local monitor_id_prop = obs.obs_properties_get(props, dc_info.prop_id)
                if monitor_id_prop then
                    local found = nil
                    local settings = obs.obs_source_get_settings(source)
                    if settings ~= nil then
                        local to_match
                        if dc_info.prop_type == "string" then
                            to_match = obs.obs_data_get_string(settings, dc_info.prop_id)
                        elseif dc_info.prop_type == "int" then
                            to_match = obs.obs_data_get_int(settings, dc_info.prop_id)
                        end

                        local item_count = obs.obs_property_list_item_count(monitor_id_prop);
                        for i = 0, item_count do
                            local name = obs.obs_property_list_item_name(monitor_id_prop, i)
                            local value
                            if dc_info.prop_type == "string" then
                                value = obs.obs_property_list_item_string(monitor_id_prop, i)
                            elseif dc_info.prop_type == "int" then
                                value = obs.obs_property_list_item_int(monitor_id_prop, i)
                            end

                            if value == to_match then
                                found = name
                                break
                            end
                        end
                        obs.obs_data_release(settings)
                    end

                    -- This works for my machine as the monitor names are given as "U2790B: 3840x2160 @ -1920,0 (Primary Monitor)"
                    -- I don't know if this holds true for other machines and/or OBS versions
                    -- TODO: Update this with some custom FFI calls to find the monitor top-left x and y coordinates if it doesn't work for anyone else
                    -- TODO: Refactor this into something that would work with Windows/Linux/Mac assuming we can't do it like this
                    if found then
                        log("Parsing display name: " .. found)
                        local x, y = found:match("(-?%d+),(-?%d+)")
                        local width, height = found:match("(%d+)x(%d+)")

                        info = { x = 0, y = 0, width = 0, height = 0 }
                        info.x = tonumber(x, 10)
                        info.y = tonumber(y, 10)
                        info.width = tonumber(width, 10)
                        info.height = tonumber(height, 10)
                        info.scale_x = 1
                        info.scale_y = 1
                        info.display_width = info.width
                        info.display_height = info.height

                        log("Parsed the following display information\n" .. format_table(info))

                        if info.width == 0 and info.height == 0 then
                            info = nil
                        end
                    end
                end

                obs.obs_properties_destroy(props)
            end
        end
    end

    if use_monitor_override then
        info = {
            x = monitor_override_x,
            y = monitor_override_y,
            width = monitor_override_w,
            height = monitor_override_h,
            scale_x = monitor_override_sx,
            scale_y = monitor_override_sy,
            display_width = monitor_override_dw,
            display_height = monitor_override_dh
        }
    end

    if not info then
        log("WARNING: Could not auto calculate zoom source position and size.\n" ..
            "         Try using the 'Set manual source position' option and adding override values")
    end

    return info
end

---
-- Check to see if the specified source is a display capture source
-- If the source_to_check is nil then the answer will be false
---@param source_to_check any The source to check
---@return boolean result True if source is a display capture, false if it nil or some other source type
function is_display_capture(source_to_check)
    if source_to_check ~= nil then
        local dc_info = get_dc_info()
        if dc_info ~= nil then
            -- Do a quick check to ensure this is a display capture
            if allow_all_sources then
                local source_type = obs.obs_source_get_id(source_to_check)
                if source_type == dc_info.source_id then
                    return true
                end
            else
                return true
            end
        end
    end

    return false
end

---
-- Releases the current sceneitem and resets data back to default
function release_sceneitem()
    if is_timer_running then
        obs.timer_remove(on_timer)
        is_timer_running = false
    end

    zoom_state = ZoomState.None

    if sceneitem ~= nil then
        if crop_filter ~= nil and source ~= nil then
            log("Zoom crop filter removed")
            obs.obs_source_filter_remove(source, crop_filter)
            obs.obs_source_release(crop_filter)
            crop_filter = nil
        end

        if sceneitem_info_orig ~= nil then
            log("Transform info reset back to original")
            obs.obs_sceneitem_set_info2(sceneitem, sceneitem_info_orig)
            sceneitem_info_orig = nil
        end

        if sceneitem_crop_orig ~= nil then
            log("Transform crop reset back to original")
            obs.obs_sceneitem_set_crop(sceneitem, sceneitem_crop_orig)
            sceneitem_crop_orig = nil
        end

        obs.obs_sceneitem_release(sceneitem)
        sceneitem = nil
    end

    if zoom_blur_filter ~= nil then
        obs.obs_source_release(zoom_blur_filter)
        zoom_blur_filter = nil
    end
    if zoom_blur_settings ~= nil then
        obs.obs_data_release(zoom_blur_settings)
        zoom_blur_settings = nil
    end

    if motion_blur_filter ~= nil then
        obs.obs_source_release(motion_blur_filter)
        motion_blur_filter = nil
    end
    if motion_blur_settings ~= nil then
        obs.obs_data_release(motion_blur_settings)
        motion_blur_settings = nil
    end

    if source ~= nil then
        obs.obs_source_release(source)
        source = nil
    end
end

----------------------------------------------------------
-- Blur Filter Management (Dual Filters)
----------------------------------------------------------
function refresh_blur_filters()
    if source == nil then return end
    
    -- 1. Refresh Zoom Blur Filter
    zoom_blur_filter = obs.obs_source_get_filter_by_name(source, ZOOM_BLUR_FILTER_NAME)
    if zoom_blur_filter ~= nil then
        zoom_blur_settings = obs.obs_source_get_settings(zoom_blur_filter)
        -- Reset radius if disabled
        if not use_zoom_blur then
             obs.obs_data_set_double(zoom_blur_settings, "radius", 0)
             obs.obs_source_update(zoom_blur_filter, zoom_blur_settings)
        end
    end

    -- 2. Refresh Motion Blur Filter
    motion_blur_filter = obs.obs_source_get_filter_by_name(source, MOTION_BLUR_FILTER_NAME)
    if motion_blur_filter ~= nil then
        motion_blur_settings = obs.obs_source_get_settings(motion_blur_filter)
         -- Reset radius if disabled
        if not use_motion_blur then
             obs.obs_data_set_double(motion_blur_settings, "radius", 0)
             obs.obs_source_update(motion_blur_filter, motion_blur_settings)
        end
    end
end

---
-- Updates the current sceneitem with a refreshed set of data from the source
-- Optionally will release the existing sceneitem and get a new one from the current scene
---@param find_newest boolean True to release the current sceneitem and get a new one
function refresh_sceneitem(find_newest)
    -- TODO: Figure out why we need to get the size from the named source during update instead of via the sceneitem source
    local source_raw = { width = 0, height = 0 }

    if find_newest then
        -- Release the current sceneitem now that we are replacing it
        release_sceneitem()

        -- Quit early if we are using no zoom source
        -- This allows users to reset the crop data back to the original,
        -- update it, and then force the conversion to happen by re-selecting it.
        if source_name == "obs-zoom-to-mouse-none" then
            return
        end

        -- Get a matching source we can use for zooming in the current scene
        log("Finding sceneitem for Zoom Source '" .. source_name .. "'")
        if source_name ~= nil then
            source = obs.obs_get_source_by_name(source_name)
            if source ~= nil then
                -- Get the source size, for some reason this works during load but the sceneitem source doesn't
                source_raw.width = obs.obs_source_get_width(source)
                source_raw.height = obs.obs_source_get_height(source)

                -- Get the current scene
                local scene_source = obs.obs_frontend_get_current_scene()
                if scene_source ~= nil then
                    local function find_scene_item_by_name(root_scene)
                        local queue = {}
                        table.insert(queue, root_scene)

                        while #queue > 0 do
                            local s = table.remove(queue, 1)
                            log("Looking in scene '" .. obs.obs_source_get_name(obs.obs_scene_get_source(s)) .. "'")

                            -- Check if the current scene has the target scene item
                            local found = obs.obs_scene_find_source(s, source_name)
                            if found ~= nil then
                                log("Found sceneitem '" .. source_name .. "'")
                                obs.obs_sceneitem_addref(found)
                                return found
                            end

                            -- If the current scene has nested scenes, enqueue them for later examination
                            local all_items = obs.obs_scene_enum_items(s)
                            if all_items then
                                for _, item in pairs(all_items) do
                                    local nested = obs.obs_sceneitem_get_source(item)
                                    if nested ~= nil then
                                        if obs.obs_source_is_scene(nested) then
                                            local nested_scene = obs.obs_scene_from_source(nested)
                                            table.insert(queue, nested_scene)
                                        elseif obs.obs_source_is_group(nested) then
                                            local nested_scene = obs.obs_group_from_source(nested)
                                            table.insert(queue, nested_scene)
                                        end
                                    end
                                end
                                obs.sceneitem_list_release(all_items)
                            end
                        end

                        return nil
                    end

                    -- Find the sceneitem for the source_name by looking through all the items
                    -- We start at the current scene and use a BFS to look into any nested scenes
                    local current = obs.obs_scene_from_source(scene_source)
                    sceneitem = find_scene_item_by_name(current)

                    obs.obs_source_release(scene_source)
                end

                if not sceneitem then
                    log("WARNING: Source not part of the current scene hierarchy.\n" ..
                        "         Try selecting a different zoom source or switching scenes.")
                    obs.obs_sceneitem_release(sceneitem)
                    obs.obs_source_release(source)

                    sceneitem = nil
                    source = nil
                    return
                end
            end
        end
    end

    if not monitor_info then
        monitor_info = get_monitor_info(source)
    end

    local is_non_display_capture = not is_display_capture(source)
    if is_non_display_capture then
        if not use_monitor_override then
            log("ERROR: Selected Zoom Source is not a display capture source.\n" ..
                "       You MUST enable 'Set manual source position' and set the correct override values for size and position.")
        end
    end

    if sceneitem ~= nil then
        -- Capture the original settings so we can restore them later
        sceneitem_info_orig = obs.obs_transform_info()
        obs.obs_sceneitem_get_info2(sceneitem, sceneitem_info_orig)

        sceneitem_crop_orig = obs.obs_sceneitem_crop()
        obs.obs_sceneitem_get_crop(sceneitem, sceneitem_crop_orig)

        sceneitem_info = obs.obs_transform_info()
        obs.obs_sceneitem_get_info2(sceneitem, sceneitem_info)

        -- sceneitem_crop = obs.obs_sceneitem_crop() -- Removed
        -- obs.obs_sceneitem_get_crop(sceneitem, sceneitem_crop) -- Removed

        if is_non_display_capture then
            -- Non-Display Capture sources don't correctly report crop values
            sceneitem_crop_orig.left = 0
            sceneitem_crop_orig.top = 0
            sceneitem_crop_orig.right = 0
            sceneitem_crop_orig.bottom = 0
        end

        -- Get the current source size (this will be the value after any applied crop filters)
        if not source then
            log("ERROR: Could not get source for sceneitem (" .. source_name .. ")")
        end

        -- TODO: Figure out why we need this fallback code
        local source_width = obs.obs_source_get_base_width(source)
        local source_height = obs.obs_source_get_base_height(source)

        if source_width == 0 then
            source_width = source_raw.width
        end
        if source_height == 0 then
            source_height = source_raw.height
        end

        if source_width == 0 or source_height == 0 then
            if monitor_info ~= nil and monitor_info.width > 0 and monitor_info.height > 0 then
                log("WARNING: Something went wrong determining source size.\n" ..
                    "         Using source size from info: " .. monitor_info.width .. ", " .. monitor_info.height)
                source_width = monitor_info.width
                source_height = monitor_info.height
            else
                log("ERROR: Something went wrong determining source size.\n" ..
                "       Try using the 'Set manual source position' option and adding override values")
            end
        else
            log("Using source size: " .. source_width .. ", " .. source_height)
        end

        -- Convert the current transform into one we can correctly modify for zooming
        -- Ideally the user just has a valid one set and we don't have to change anything because this might not work 100% of the time
        if sceneitem_info.bounds_type == obs.OBS_BOUNDS_NONE then
            sceneitem_info.bounds_type = obs.OBS_BOUNDS_SCALE_INNER
            sceneitem_info.bounds_alignment = 5 -- (5 == OBS_ALIGN_TOP | OBS_ALIGN_LEFT) (0 == OBS_ALIGN_CENTER)
            sceneitem_info.bounds.x = source_width * sceneitem_info.scale.x
            sceneitem_info.bounds.y = source_height * sceneitem_info.scale.y

            obs.obs_sceneitem_set_info2(sceneitem, sceneitem_info)

            log("WARNING: Found existing non-boundingbox transform. This may cause issues with zooming.\n" ..
                "         Settings have been auto converted to a bounding box scaling transfrom instead.\n" ..
                "         If you have issues with your layout consider making the transform use a bounding box manually.")
        end

        -- Get information about any existing crop filters (that aren't ours)
        zoom_info.source_crop_filter = { x = 0, y = 0, w = 0, h = 0 }
        local found_crop_filter = false
        local filters = obs.obs_source_enum_filters(source)
        if filters ~= nil then
            for k, v in pairs(filters) do
                local id = obs.obs_source_get_id(v)
                if id == "crop_filter" then
                    local name = obs.obs_source_get_name(v)
                    if name ~= TRANSFORM_FILTER_NAME and name ~= "temp_" .. TRANSFORM_FILTER_NAME then
                        found_crop_filter = true
                        local settings = obs.obs_source_get_settings(v)
                        if settings ~= nil then
                            if not obs.obs_data_get_bool(settings, "relative") then
                                zoom_info.source_crop_filter.x =
                                    zoom_info.source_crop_filter.x + obs.obs_data_get_int(settings, "left")
                                zoom_info.source_crop_filter.y =
                                    zoom_info.source_crop_filter.y + obs.obs_data_get_int(settings, "top")
                                zoom_info.source_crop_filter.w =
                                    zoom_info.source_crop_filter.w + obs.obs_data_get_int(settings, "cx")
                                zoom_info.source_crop_filter.h =
                                    zoom_info.source_crop_filter.h + obs.obs_data_get_int(settings, "cy")
                                log("Found existing non-relative crop/pad filter (" ..
                                    name ..
                                    "). Applying settings " .. format_table(zoom_info.source_crop_filter))
                            else
                                log("WARNING: Found existing relative crop/pad filter (" .. name .. ").\n" ..
                                    "         This will cause issues with zooming. Convert to relative settings instead.")
                            end
                            obs.obs_data_release(settings)
                        end
                    end
                end
            end

            obs.source_list_release(filters)
        end

        -- If the user has a transform crop set, we need to convert it into a crop filter so that it works correctly with zooming
        -- Ideally the user does this manually and uses a crop filter instead of the transfrom crop because this might not work 100% of the time
        if not found_crop_filter and (sceneitem_crop_orig.left ~= 0 or sceneitem_crop_orig.top ~= 0 or sceneitem_crop_orig.right ~= 0 or sceneitem_crop_orig.bottom ~= 0) then
            log("Creating new crop filter")

            -- Update the source size
            source_width = source_width - (sceneitem_crop_orig.left + sceneitem_crop_orig.right)
            source_height = source_height - (sceneitem_crop_orig.top + sceneitem_crop_orig.bottom)

            -- Update the source crop filter now that we will be using one
            zoom_info.source_crop_filter.x = sceneitem_crop_orig.left
            zoom_info.source_crop_filter.y = sceneitem_crop_orig.top
            zoom_info.source_crop_filter.w = source_width
            zoom_info.source_crop_filter.h = source_height

            -- Add a new crop filter that emulates the existing transform crop
            local settings = obs.obs_data_create()
            obs.obs_data_set_bool(settings, "relative", false)
            obs.obs_data_set_int(settings, "left", zoom_info.source_crop_filter.x)
            obs.obs_data_set_int(settings, "top", zoom_info.source_crop_filter.y)
            obs.obs_data_set_int(settings, "cx", zoom_info.source_crop_filter.w)
            obs.obs_data_set_int(settings, "cy", zoom_info.source_crop_filter.h)
            local crop_filter_temp = obs.obs_source_create_private("crop_filter", "temp_" .. TRANSFORM_FILTER_NAME, settings)
            obs.obs_source_filter_add(source, crop_filter_temp)
            obs.obs_data_release(settings)
            obs.obs_source_release(crop_filter_temp) -- Release temp filter after adding

            -- Clear out the transform crop
            local sceneitem_crop = obs.obs_sceneitem_crop()
            sceneitem_crop.left = 0
            sceneitem_crop.top = 0
            sceneitem_crop.right = 0
            sceneitem_crop.bottom = 0
            obs.obs_sceneitem_set_crop(sceneitem, sceneitem_crop)

            log("WARNING: Found existing transform crop. This may cause issues with zooming.\n" ..
                "         Settings have been auto converted to a relative crop/pad filter instead.\n" ..
                "         If you have issues with your layout consider making the filter manually.")
        elseif found_crop_filter then
            source_width = zoom_info.source_crop_filter.w
            source_height = zoom_info.source_crop_filter.h
        end

        -- Get the rest of the information needed to correctly zoom
        zoom_info.source_size = { width = source_width, height = source_height }
        zoom_info.source_crop = {
            l = sceneitem_crop_orig.left,
            t = sceneitem_crop_orig.top,
            r = sceneitem_crop_orig.right,
            b = sceneitem_crop_orig.bottom
        }
        --log("Transform updated. Using following values -\n" .. format_table(zoom_info))

        -- Set the initial the crop filter data to match the source
        crop_filter_info_orig = { x = 0, y = 0, w = zoom_info.source_size.width, h = zoom_info.source_size.height }
        crop_filter_info = {
            x = crop_filter_info_orig.x,
            y = crop_filter_info_orig.y,
            w = crop_filter_info_orig.w,
            h = crop_filter_info_orig.h
        }

        last_camera_x = crop_filter_info.x
        last_camera_y = crop_filter_info.y

        -- Get or create our crop filter that we change during zoom
        crop_filter = obs.obs_source_get_filter_by_name(source, TRANSFORM_FILTER_NAME)
        if crop_filter == nil then
            local crop_filter_settings = obs.obs_data_create()
            obs.obs_data_set_bool(crop_filter_settings, "relative", false)
            crop_filter = obs.obs_source_create_private("crop_filter", TRANSFORM_FILTER_NAME, crop_filter_settings)
            obs.obs_source_filter_add(source, crop_filter)
            obs.obs_data_release(crop_filter_settings) -- Release settings after use
        end

        obs.obs_source_filter_set_order(source, crop_filter, obs.OBS_ORDER_MOVE_BOTTOM)
        set_crop_settings(crop_filter_info_orig)
        
        refresh_blur_filters()
    end
end

---
-- Get the target position that we will attempt to zoom towards
---@param zoom any
---@param mouse table|nil Optional mouse position, if nil will call get_mouse_pos()
---@return table
function get_target_position(zoom, mouse)
    if mouse == nil then
        mouse = get_mouse_pos()
    end

    -- If we have monitor information then we can offset the mouse by the top-left of the monitor position
    -- This is because the display-capture source assumes top-left is 0,0 but the mouse uses the total desktop area,
    -- so a second monitor might start at x:1920, y:0 for example, so when we click at 1920,0 we want it to look like we clicked 0,0 on the source.
    if monitor_info then
        mouse.x = mouse.x - monitor_info.x
        mouse.y = mouse.y - monitor_info.y
    end

    -- Now offset the mouse by the crop top-left because if we cropped 100px off of the display clicking at 100,0 should really be the top-left 0,0
    mouse.x = mouse.x - zoom.source_crop_filter.x
    mouse.y = mouse.y - zoom.source_crop_filter.y

    -- If the source uses a different scale to the display, apply that now.
    -- This can happen with cloned sources, where it is cloning a scene that has a full screen display.
    -- The display will be the full desktop pixel size, but the cloned scene will be scaled down to the canvas,
    -- so we need to scale down the mouse movement to match
    if monitor_info and monitor_info.scale_x and monitor_info.scale_y then
        mouse.x = mouse.x * monitor_info.scale_x
        mouse.y = mouse.y * monitor_info.scale_y
    end

    -- Get the new size after we zoom
    -- Remember that because we are using a crop/pad filter making the size smaller (dividing by zoom) means that we see less of the image
    -- in the same amount of space making it look bigger (aka zoomed in)
    local new_size = {
        width = zoom.source_size.width / zoom.zoom_to,
        height = zoom.source_size.height / zoom.zoom_to
    }

    -- New offset for the crop/pad filter is whereever we clicked minus half the size, so that the clicked point because the new center
    local pos = {
        x = mouse.x - new_size.width * 0.5,
        y = mouse.y - new_size.height * 0.5
    }

    -- Create the full crop results
    local crop = {
        x = pos.x,
        y = pos.y,
        w = new_size.width,
        h = new_size.height,
    }

    -- Keep the zoom in bounds of the source so that we never show something outside that user is trying to hide with existing crop settings
    crop.x = math.floor(clamp(0, (zoom.source_size.width - new_size.width), crop.x))
    crop.y = math.floor(clamp(0, (zoom.source_size.height - new_size.height), crop.y))

    return { crop = crop, raw_center = mouse, clamped_center = { x = math.floor(crop.x + crop.w * 0.5), y = math.floor(crop.y + crop.h * 0.5) } }
end

function on_toggle_follow(pressed)
    if pressed then
        is_following_mouse = not is_following_mouse
        log("Tracking mouse is " .. (is_following_mouse and "on" or "off"))

        if is_following_mouse and zoom_state == ZoomState.ZoomedIn then
            -- Since we are zooming we need to start the timer for the animation and tracking
            if is_timer_running == false then
                is_timer_running = true
                local timer_interval = math.floor(obs.obs_get_frame_interval_ns() / 1000000)
                obs.timer_add(on_timer, timer_interval)
            end
        end
    end
end

local zoom_start_crop = { x = 0, y = 0, w = 0, h = 0 }

function on_toggle_zoom(pressed)
    if pressed then
        -- Check if we are in a safe state to zoom
        -- Allow interrupting animation by checking "or zoom_state == Zooming..." if we wanted, 
        -- but keeping it simple for now to strict states
        if zoom_state == ZoomState.ZoomedIn or zoom_state == ZoomState.None then
            
            -- Capture the starting position for interpolation
            zoom_start_crop.x = crop_filter_info.x
            zoom_start_crop.y = crop_filter_info.y
            zoom_start_crop.w = crop_filter_info.w
            zoom_start_crop.h = crop_filter_info.h

            if zoom_state == ZoomState.ZoomedIn then
                log("Zooming out")
                -- To zoom out, we set the target back to whatever it was originally
                zoom_state = ZoomState.ZoomingOut
                zoom_time = 0
                locked_center = nil
                locked_last_pos = nil
                zoom_target = { crop = crop_filter_info_orig, c = sceneitem_crop_orig }
                if is_following_mouse then
                    is_following_mouse = false
                    log("Tracking mouse is off (due to zoom out)")
                end
            else
                log("Zooming in")
                -- To zoom in, we get a new target based on where the mouse was when zoom was clicked
                zoom_state = ZoomState.ZoomingIn
                zoom_info.zoom_to = zoom_value
                zoom_time = 0
                locked_center = nil
                locked_last_pos = nil
                
                -- Initialize tracked mouse position for dead zone
                local initial_mouse = get_mouse_pos()
                tracked_mouse_pos.x = initial_mouse.x
                tracked_mouse_pos.y = initial_mouse.y
                smoothed_mouse_pos.x = initial_mouse.x
                smoothed_mouse_pos.y = initial_mouse.y
                
                zoom_target = get_target_position(zoom_info, smoothed_mouse_pos)
            end

            -- Since we are zooming we need to start the timer for the animation and tracking
            if is_timer_running == false then
                is_timer_running = true
                -- We use a very small timer interval to run as fast as possible (OBS will limit to frame rate)
                -- 1ms is fine, getting actual dt is handled in on_timer
                obs.timer_add(on_timer, 1)
                
                -- Reset velocities for smooth transition
                velocity_x.val = 0
                velocity_y.val = 0
                
                -- Reset velocities for smooth transition
                velocity_mx.val = 0
                velocity_my.val = 0
                
                -- Reset delta time helper
                get_dt()
            end
        end
    end
end

function on_timer()
    local dt = get_dt()

    -- 1. Smooth Cursor Tracking (Always runs if a cursor is configured)
    if (cursor_source_name ~= "" and cursor_sceneitem ~= nil) or 
       (cursor_pointer_source_name ~= "" and cursor_pointer_sceneitem ~= nil) then
        
        -- Detect current cursor shape (Standard vs Pointer)
        local is_pointer = false
        if cursor_shape_detection_available then
            local ci = ffi.new("CURSORINFO_SCRIPT")
            ci.cbSize = ffi.sizeof("CURSORINFO_SCRIPT")
            if ffi.C.GetCursorInfo(ci) ~= 0 then
                is_pointer = (ci.hCursor == hCursorHand)
            end
        end
        
        -- Visibility management: Swap based on pointer state with fallback
        local use_pointer = is_pointer and (cursor_pointer_source_name ~= "")
        local show_pointer = use_pointer
        local show_standard = (not show_pointer) and (cursor_source_name ~= "")
        
        if cursor_sceneitem then obs.obs_sceneitem_set_visible(cursor_sceneitem, show_standard) end
        if cursor_pointer_sceneitem then obs.obs_sceneitem_set_visible(cursor_pointer_sceneitem, show_pointer) end
        
        -- Get raw mouse position for cursor tracking
        local raw_mouse = get_mouse_pos()
        
        -- Apply smoothing (Weighted)
        cursor_pos.x = SmoothDamp(cursor_pos.x, raw_mouse.x, velocity_cursor_x, cursor_smooth_time, 100000, dt)
        cursor_pos.y = SmoothDamp(cursor_pos.y, raw_mouse.y, velocity_cursor_y, cursor_smooth_time, 100000, dt)
        
        -- Dynamic Effects Physics
        local speed = 0
        local dynamic_scale = 1.0
        local dynamic_rot = 0
        
        local vx = velocity_cursor_x.val
        local vy = velocity_cursor_y.val
        speed = math.sqrt(vx*vx + vy*vy)
        
        -- 1. Rotation Modes
        if cursor_rotation_mode == "Directional" then
            if speed > 20 then
                local raw_angle = math.atan2(vy, vx) * (180 / math.pi)
                
                -- Force snap to horizontal if Y movement is negligible (Fixes 345 drift)
                if math.abs(vy) < 10 then
                    raw_angle = (vx > 0 and 0 or (vx < 0 and 180 or raw_angle))
                end
                
                local target_angle = raw_angle + cursor_angle_offset
                local diff = (target_angle - cursor_current_rot + 180) % 360 - 180
                cursor_current_rot = SmoothDamp(cursor_current_rot, cursor_current_rot + diff, velocity_cursor_rot, 0.05, 100000, dt)
            end
            dynamic_rot = cursor_current_rot
        elseif cursor_rotation_mode == "Lean" then
            -- Tilt based on horizontal velocity (Lean)
            local lean_intensity = 0.05 -- Lean amount
            local target_lean = (vx * lean_intensity) + cursor_angle_offset
            
            -- Cap lean to 40 degrees relative to offset
            local lean_diff = target_lean - cursor_angle_offset
            if lean_diff > 40 then target_lean = cursor_angle_offset + 40 end
            if lean_diff < -40 then target_lean = cursor_angle_offset - 40 end
            
            local diff = (target_lean - cursor_current_rot + 180) % 360 - 180
            cursor_current_rot = SmoothDamp(cursor_current_rot, cursor_current_rot + diff, velocity_cursor_rot, 0.08, 100000, dt)
            dynamic_rot = cursor_current_rot
        else
            -- Mode "None": Smoothly return to default offset
            local diff = (cursor_angle_offset - cursor_current_rot + 180) % 360 - 180
            cursor_current_rot = SmoothDamp(cursor_current_rot, cursor_current_rot + diff, velocity_cursor_rot, 0.15, 100000, dt)
            dynamic_rot = cursor_current_rot
        end
        
        -- 2. Uniform Dynamic Scaling (Move Boost)
        if cursor_tilt_strength > 0 then
            local boost = math.min(speed / 1500, 0.5) * cursor_tilt_strength
            dynamic_scale = 1.0 + boost
        end
        
        -- Snap to exact position when very close
        if math.abs(cursor_pos.x - raw_mouse.x) < 0.5 and math.abs(velocity_cursor_x.val) < 1 then
            cursor_pos.x = raw_mouse.x
            velocity_cursor_x.val = 0
        end
        if math.abs(cursor_pos.y - raw_mouse.y) < 0.5 and math.abs(velocity_cursor_y.val) < 1 then
            cursor_pos.y = raw_mouse.y
            velocity_cursor_y.val = 0
        end
        
        -- Detect mouse click for scale animation
        local is_clicking = false
        if click_detection_available then
            local VK_LBUTTON = 0x01
            local state = ffi.C.GetAsyncKeyState(VK_LBUTTON)
            is_clicking = (bit.band(state, 0x8000) ~= 0)
        end
        
        -- Animate cursor scale
        local target_scale = is_clicking and (cursor_scale * cursor_click_scale) or cursor_scale
        local anim_time = is_clicking and 0.05 or 0.2 
        cursor_current_scale = SmoothDamp(cursor_current_scale, target_scale, velocity_cursor_scale, anim_time, 100000, dt)
        
        -- Transition Animation (Dip/Pop)
        if is_pointer ~= cursor_was_pointer then
            cursor_swap_pulse = 0.75
            velocity_cursor_swap.val = 1
            cursor_was_pointer = is_pointer
        end
        cursor_swap_pulse = SmoothDamp(cursor_swap_pulse, 1.0, velocity_cursor_swap, 0.12, 100000, dt)
        
        -- Calculate position relative to zoom
        local current_zoom = 1.0
        if zoom_state ~= ZoomState.None and crop_filter_info ~= nil and crop_filter_info.w > 0 then
            current_zoom = zoom_info.source_size.width / crop_filter_info.w
        end
        
        local crop_x = (zoom_state ~= ZoomState.None and crop_filter_info) and crop_filter_info.x or 0
        local crop_y = (zoom_state ~= ZoomState.None and crop_filter_info) and crop_filter_info.y or 0
        
        local final_x = (cursor_pos.x - crop_x) * current_zoom + (cursor_offset_x * current_zoom)
        local final_y = (cursor_pos.y - crop_y) * current_zoom + (cursor_offset_y * current_zoom)
        
        local f_pos = obs.vec2()
        f_pos.x = final_x
        f_pos.y = final_y
        
        local f_scale = obs.vec2()
        f_scale.x = cursor_current_scale * current_zoom * cursor_swap_pulse * dynamic_scale
        f_scale.y = cursor_current_scale * current_zoom * cursor_swap_pulse * dynamic_scale
        
        if cursor_sceneitem then
            obs.obs_sceneitem_set_pos(cursor_sceneitem, f_pos)
            obs.obs_sceneitem_set_scale(cursor_sceneitem, f_scale)
            obs.obs_sceneitem_set_rot(cursor_sceneitem, dynamic_rot)
        end
        if cursor_pointer_sceneitem then
            obs.obs_sceneitem_set_pos(cursor_pointer_sceneitem, f_pos)
            obs.obs_sceneitem_set_scale(cursor_pointer_sceneitem, f_scale)
            obs.obs_sceneitem_set_rot(cursor_pointer_sceneitem, dynamic_rot)
        end
    end

    -- 2. Zoom & Camera Logic (Requires valid source and target)
    if crop_filter_info ~= nil and zoom_target ~= nil then
        
        -- Update Zoom Progress
        if zoom_state == ZoomState.ZoomingOut or zoom_state == ZoomState.ZoomingIn then
            zoom_time = zoom_time + (dt / zoom_duration)
        end

        -- Calculate Eased T for Zoom (Size)
        -- We clamp t at 1 for the logic, but allow overshoot functions to go beyond
        local t = math.min(1, zoom_time)
        local t_eased = t

        -- Use zoom_overshoot value directly to decide easing curve
        -- If overshoot > 0, use Back.EaseOut for bounce effect
        -- Otherwise, use Cubic.EaseOut (smooth) or Expo.EaseOut (snappy based on duration)
        if zoom_overshoot > 0 and zoom_state == ZoomState.ZoomingIn then
            t_eased = Easing.Back.EaseOut(t, zoom_overshoot * 3.0)
        elseif zoom_duration <= 0.4 then
            -- Short duration = snappy feel
            t_eased = Easing.Expo.EaseOut(t)
        else
            -- Default smooth ease
            t_eased = Easing.Cubic.EaseOut(t)
        end

        local is_zooming = (zoom_state == ZoomState.ZoomingOut or zoom_state == ZoomState.ZoomingIn)

        -- 1. Update Size (Width/Height) using Easing
        if is_zooming then
            crop_filter_info.w = lerp(zoom_start_crop.w, zoom_target.crop.w, t_eased)
            crop_filter_info.h = lerp(zoom_start_crop.h, zoom_target.crop.h, t_eased)
        end
        -- If not zooming, W/H stays constant (ZoomedIn state), so we don't touch it.

        -- 2. Update Position (X/Y)
        -- If following mouse, we use SmoothDamp (Physics)
        -- If NOT following mouse (or Zooming Out), we use Easing (Interpolation) to lock to target
        
        -- Update the target if following (always update dirty target)
        local should_follow = is_following_mouse or (use_auto_follow_mouse and zoom_state == ZoomState.ZoomingIn)
        
        if should_follow and zoom_state ~= ZoomState.ZoomingOut then
             -- Get raw mouse position for dead zone check
             local mouse = get_mouse_pos()
             
             -- Dead Zone Check: Continuous "Pushing Box" logic
             if follow_dead_zone > 0 then
                 local dx = mouse.x - tracked_mouse_pos.x
                 local dy = mouse.y - tracked_mouse_pos.y
                 local dist = math.sqrt(dx*dx + dy*dy)
                 
                 -- If outside dead zone, drag the tracked position towards mouse
                 -- causing it to be exactly 'dead_zone' pixels away
                 if dist > follow_dead_zone then
                    local scale = (dist - follow_dead_zone) / dist
                    tracked_mouse_pos.x = tracked_mouse_pos.x + dx * scale
                    tracked_mouse_pos.y = tracked_mouse_pos.y + dy * scale
                 end
             else
                 -- No dead zone, snap directly
                 tracked_mouse_pos.x = mouse.x
                 tracked_mouse_pos.y = mouse.y
             end
             
             -- Always update target based on tracked pos (it will be stable if mouse is in dead zone)
             zoom_target = get_target_position(zoom_info, tracked_mouse_pos)
             
             -- Apply bounds check if required
             if not use_follow_outside_bounds then
                 -- Check if mouse is within source bounds
                 if zoom_target.raw_center.x >= zoom_target.crop.x and
                    zoom_target.raw_center.x <= zoom_target.crop.x + zoom_target.crop.w and
                    zoom_target.raw_center.y >= zoom_target.crop.y and
                    zoom_target.raw_center.y <= zoom_target.crop.y + zoom_target.crop.h then
                     -- Keep target
                 else
                     -- Only update if valid? Or should we clamp?
                     -- For now keeping original logic roughly: update if valid
                 end
             end
             
             -- Choice: No smoothing or Weighted Input Smoothing?
             -- We smooth the mouse movement itself ("Input Smoothing").
             -- This ensures the camera rigidly follows the smoothed path, 
             -- providing the feel of "weight" without any corner-tripping bugs.
             smoothed_mouse_pos.x = SmoothDamp(smoothed_mouse_pos.x, tracked_mouse_pos.x, velocity_mx, follow_smooth_time, 100000, dt)
             smoothed_mouse_pos.y = SmoothDamp(smoothed_mouse_pos.y, tracked_mouse_pos.y, velocity_my, follow_smooth_time, 100000, dt)
             
             -- Always update target based on smoothed mouse
             zoom_target = get_target_position(zoom_info, smoothed_mouse_pos)
             
             -- Apply bounds check if required
             if not use_follow_outside_bounds then
                 -- Check if raw mouse (unsmoothed) is within source bounds? 
                 -- Or check smoothed mouse? Usually checking smoothed mouse is better for physics consistency.
                 if zoom_target.raw_center.x >= zoom_target.crop.x and
                    zoom_target.raw_center.x <= zoom_target.crop.x + zoom_target.crop.w and
                    zoom_target.raw_center.y >= zoom_target.crop.y and
                    zoom_target.raw_center.y <= zoom_target.crop.y + zoom_target.crop.h then
                     -- Keep target
                 else
                     -- Only update if valid? Or should we clamp?
                 end
             end
             
             -- Position Calculation: Rigid Lerp towards smoothed target
             -- Since the "weight" is already in smoothed_mouse_pos, we just rigidly track it.
             if is_zooming or (zoom_state == ZoomState.ZoomedIn and is_following_mouse) then
                 crop_filter_info.x = lerp(zoom_start_crop.x, zoom_target.crop.x, t_eased)
                 crop_filter_info.y = lerp(zoom_start_crop.y, zoom_target.crop.y, t_eased)
             else
                 -- Static ZoomedIn (not following) or IDLE
                 if zoom_state == ZoomState.ZoomedIn then
                     crop_filter_info.x = zoom_target.crop.x
                     crop_filter_info.y = zoom_target.crop.y
                 end
             end
        else
            -- Zooming Out OR Static (Zoomed In but not following)
            -- We just ease to the target (which is fixed for ZoomOut or fixed for Static)
            if is_zooming then
                crop_filter_info.x = lerp(zoom_start_crop.x, zoom_target.crop.x, t_eased)
                crop_filter_info.y = lerp(zoom_start_crop.y, zoom_target.crop.y, t_eased)
            end
        end

        -- Apply Updated Settings
        set_crop_settings(crop_filter_info)
        
        -- 3. Update Zoom Blur (Independent)
        if use_zoom_blur and zoom_blur_filter ~= nil then
             local z_radius = 0
             if is_zooming then
                -- Bell Curve: Smooth eased start (0), Peak at 50% (1), Smooth eased end (0)
                local t = math.min(1.0, zoom_time)
                local curve = math.sin(t * math.pi)
                local blur_weight = curve * curve
                z_radius = blur_weight * zoom_blur_intensity
             end
             
             if z_radius > 0 or last_blur_radius > 0 then -- Reusing last_blur_radius for generic check
                -- Update settings
                if zoom_blur_settings == nil then zoom_blur_settings = obs.obs_source_get_settings(zoom_blur_filter) end
                
                obs.obs_data_set_double(zoom_blur_settings, "radius", z_radius)
                
                -- Center of the ZOOMED AREA
                local blur_cx = crop_filter_info.x + (crop_filter_info.w / 2)
                local blur_cy = crop_filter_info.y + (crop_filter_info.h / 2)
                
                obs.obs_data_set_double(zoom_blur_settings, "center_x", blur_cx)
                obs.obs_data_set_double(zoom_blur_settings, "center_y", blur_cy)
                obs.obs_data_set_double(zoom_blur_settings, "inactive_radius", zoom_blur_inactive_radius)
                
                obs.obs_source_update(zoom_blur_filter, zoom_blur_settings)
             end
        end

        -- 4. Update Motion Blur (Independent)
        if use_motion_blur and motion_blur_filter ~= nil then
            local m_radius = 0
            if not is_zooming then
                -- Calculate velocity based on camera movement
                local cam_dx = crop_filter_info.x - last_camera_x
                local cam_dy = crop_filter_info.y - last_camera_y 
                local current_speed = math.sqrt(cam_dx*cam_dx + cam_dy*cam_dy)
                
                if current_speed > 1.0 then
                    m_radius = math.min(10, current_speed * motion_blur_intensity * 0.5)
                    local m_angle = math.deg(math.atan2(cam_dy, cam_dx))
                    
                    if m_radius > 0.5 then
                        if motion_blur_settings == nil then motion_blur_settings = obs.obs_source_get_settings(motion_blur_filter) end
                        obs.obs_data_set_double(motion_blur_settings, "radius", m_radius)
                        obs.obs_data_set_double(motion_blur_settings, "angle", m_angle)
                        obs.obs_source_update(motion_blur_filter, motion_blur_settings)
                    end
                else
                     -- Reset radius if speed is low
                     if motion_blur_settings == nil then motion_blur_settings = obs.obs_source_get_settings(motion_blur_filter) end
                     obs.obs_data_set_double(motion_blur_settings, "radius", 0)
                     obs.obs_source_update(motion_blur_filter, motion_blur_settings)
                end
            else
                -- Disable motion blur when zooming to avoid conflict visual noise
                 if motion_blur_settings == nil then motion_blur_settings = obs.obs_source_get_settings(motion_blur_filter) end
                 obs.obs_data_set_double(motion_blur_settings, "radius", 0)
                 obs.obs_source_update(motion_blur_filter, motion_blur_settings)
            end
        end
        
        -- Update last camera position for velocity calc
        last_camera_x = crop_filter_info.x
        last_camera_y = crop_filter_info.y
        


        -- State Transitions
        if zoom_time >= 1 and is_zooming then
            local should_stop_timer = false
            
            if zoom_state == ZoomState.ZoomingOut then
                log("Zoomed out")
                zoom_state = ZoomState.None
                should_stop_timer = true
            elseif zoom_state == ZoomState.ZoomingIn then
                log("Zoomed in")
                zoom_state = ZoomState.ZoomedIn
                
                if use_auto_follow_mouse and not is_following_mouse then
                    is_following_mouse = true
                    log("Tracking mouse ON (Auto)")
                    -- Reset velocities for smooth transition if needed, but usually 0 is fine
                    -- velocity_x.val = 0
                    -- velocity_y.val = 0
                end
                
                should_stop_timer = (not use_auto_follow_mouse) and (not is_following_mouse)
            end

            -- Don't stop timer if smooth cursor is enabled (needs continuous updates)
            if should_stop_timer and cursor_source_name == "" and cursor_pointer_source_name == "" then
                is_timer_running = false
                obs.timer_remove(on_timer)
            end
        end
    end
end

-- ...



function on_socket_timer()
    if not socket_server then
        return
    end

    repeat
        local data, status = socket_server:receive_from()
        if data then
            local sx, sy = data:match("(-?%d+) (-?%d+)")
            if sx and sy then
                local x = tonumber(sx, 10)
                local y = tonumber(sy, 10)
                if not socket_mouse then
                    log("Socket server client connected")
                    socket_mouse = { x = x, y = y }
                else
                    socket_mouse.x = x
                    socket_mouse.y = y
                end
            end
        elseif status ~= "timeout" then
            error(status)
        end
    until data == nil
end

function start_server()
    if socket_available then
        local address = socket.find_first_address("*", socket_port)

        socket_server = socket.create("inet", "dgram", "udp")
        if socket_server ~= nil then
            socket_server:set_option("reuseaddr", 1)
            socket_server:set_blocking(false)
            socket_server:bind(address, socket_port)
            obs.timer_add(on_socket_timer, socket_poll)
            log("Socket server listening on port " .. socket_port .. "...")
        end
    end
end

function stop_server()
    if socket_server ~= nil then
        log("Socket server stopped")
        obs.timer_remove(on_socket_timer)
        socket_server:close()
        socket_server = nil
        socket_mouse = nil
    end
end

function set_crop_settings(crop)
    if crop_filter ~= nil then
        local crop_filter_settings = obs.obs_source_get_settings(crop_filter)
        -- Call into OBS to update our crop filter with the new settings
        -- I have no idea how slow/expensive this is, so we could potentially only do it if something changes
        obs.obs_data_set_int(crop_filter_settings, "left", math.floor(crop.x))
        obs.obs_data_set_int(crop_filter_settings, "top", math.floor(crop.y))
        obs.obs_data_set_int(crop_filter_settings, "cx", math.floor(crop.w))
        obs.obs_data_set_int(crop_filter_settings, "cy", math.floor(crop.h))
        obs.obs_source_update(crop_filter, crop_filter_settings)
        obs.obs_data_release(crop_filter_settings)
    end
end

function on_transition_start(t)
    log("Transition started")
    -- We need to remove the crop from the sceneitem as the transition starts to avoid
    -- a delay with the rendering where you see the old crop and jump to the new one
    release_sceneitem()
end

function on_frontend_event(event)
    if event == obs.OBS_FRONTEND_EVENT_SCENE_CHANGED then
        log("OBS Scene changed")
        -- If the scene changes we attempt to find a new source with the same name in this new scene
        -- TODO: There probably needs to be a way for users to specify what source they want to use in each scene
        -- Scene change can happen before OBS has completely loaded, so we check for that here
        if is_obs_loaded then
            refresh_sceneitem(true)
            refresh_cursor_item(cursor_source_name, false)
            refresh_cursor_item(cursor_pointer_source_name, true)
        end
    elseif event == obs.OBS_FRONTEND_EVENT_FINISHED_LOADING then
        log("OBS Loaded")
        -- Once loaded we perform our initial lookup
        is_obs_loaded = true
        monitor_info = get_monitor_info(source)
        refresh_sceneitem(true)
        
        -- Initial cursor setup
        refresh_cursor_item(cursor_source_name, false)
        refresh_cursor_item(cursor_pointer_source_name, true)
    elseif event == obs.OBS_FRONTEND_EVENT_SCRIPTING_SHUTDOWN then
        log("OBS Shutting down")
        -- Add a fail-safe for unloading the script during shutdown
        if is_script_loaded then
            script_unload()
        end
    end
end

function refresh_cursor_item(name, is_pointer)
    if name == "" then 
        if is_pointer then 
            cursor_pointer_sceneitem = nil
            cursor_pointer_source = nil
        else
            cursor_sceneitem = nil
            cursor_source = nil
        end
        return 
    end
    
    local sceneitem = nil
    local src = nil
    
    local current_scene_source = obs.obs_frontend_get_current_scene()
    if current_scene_source ~= nil then
        local scene = obs.obs_scene_from_source(current_scene_source)
        if scene ~= nil then
            sceneitem = obs.obs_scene_find_source(scene, name)
            if sceneitem ~= nil then
                src = obs.obs_sceneitem_get_source(sceneitem)
                log("Smooth Cursor source found: " .. name)
                
                -- Start timer if needed
                if not is_timer_running then
                    is_timer_running = true
                    obs.timer_add(on_timer, 1)
                    get_dt()
                end
                
                -- Initial position
                local mouse = get_mouse_pos()
                cursor_pos.x = mouse.x
                cursor_pos.y = mouse.y
            else
                log("Smooth Cursor source not found in scene: " .. name)
            end
        end
        obs.obs_source_release(current_scene_source)
    end
    
    if is_pointer then
        cursor_pointer_sceneitem = sceneitem
        cursor_pointer_source = src
    else
        cursor_sceneitem = sceneitem
        cursor_source = src
    end
end

function on_update_transform()
    -- Update the crop/size settings based on whatever the source in the current scene looks like
    if is_obs_loaded then
        refresh_sceneitem(true)
    end

    return true
end

function on_settings_modified(props, prop, settings)
    local name = obs.obs_property_name(prop)

    -- Show/Hide the settings based on if the checkbox is checked or not
    if name == "use_monitor_override" then
        local visible = obs.obs_data_get_bool(settings, "use_monitor_override")

        obs.obs_property_set_visible(obs.obs_properties_get(props, "monitor_override_x"), visible)
        obs.obs_property_set_visible(obs.obs_properties_get(props, "monitor_override_y"), visible)
        obs.obs_property_set_visible(obs.obs_properties_get(props, "monitor_override_w"), visible)
        obs.obs_property_set_visible(obs.obs_properties_get(props, "monitor_override_h"), visible)
        obs.obs_property_set_visible(obs.obs_properties_get(props, "monitor_override_sx"), visible)
        obs.obs_property_set_visible(obs.obs_properties_get(props, "monitor_override_sy"), visible)
        obs.obs_property_set_visible(obs.obs_properties_get(props, "monitor_override_dw"), visible)
        obs.obs_property_set_visible(obs.obs_properties_get(props, "monitor_override_dh"), visible)
        return true
    elseif name == "use_socket" then
        local visible = obs.obs_data_get_bool(settings, "use_socket")
        obs.obs_property_set_visible(obs.obs_properties_get(props, "socket_label"), not visible)
        obs.obs_property_set_visible(obs.obs_properties_get(props, "socket_port"), visible)
        obs.obs_property_set_visible(obs.obs_properties_get(props, "socket_poll"), visible)
        return true
    elseif name == "allow_all_sources" then
        local sources_list = obs.obs_properties_get(props, "source")
        populate_zoom_sources(sources_list)
        return true
    elseif name == "zoom_preset" then
        local preset = obs.obs_data_get_string(settings, "zoom_preset")
        
        -- Apply Preset Values from global table
        if global_presets[preset] then
            local p = global_presets[preset]
            obs.obs_data_set_double(settings, "zoom_duration", p.dur)
            obs.obs_data_set_double(settings, "zoom_overshoot", p.ovr)
            obs.obs_data_set_double(settings, "follow_smooth_time", p.smt)
        end
        -- We return true to refresh the property widget with new values
        return true
    elseif name == "debug_logs" then
        if obs.obs_data_get_bool(settings, "debug_logs") then
            log_current_settings()
        end
    end

    return false
end

-- Helper to detect if user manually changed a value from a preset
function on_slider_modified(props, prop, settings)
    local name = obs.obs_property_name(prop)
    
    -- Get current values
    local dur = obs.obs_data_get_double(settings, "zoom_duration")
    local ovr = obs.obs_data_get_double(settings, "zoom_overshoot")
    local smt = obs.obs_data_get_double(settings, "follow_smooth_time")
    local preset = obs.obs_data_get_string(settings, "zoom_preset")
    
    -- Check if current values match any preset in our global table
    local matches_preset = false
    for pname, pvals in pairs(global_presets) do
        if math.abs(dur - pvals.dur) < 0.01 and 
           math.abs(ovr - pvals.ovr) < 0.01 and 
           math.abs(smt - pvals.smt) < 0.01 then
            matches_preset = true
            if preset ~= pname then
                obs.obs_data_set_string(settings, "zoom_preset", pname)
                return true
            end
            break
        end
    end
    
    -- If no preset matches, switch to Custom
    if not matches_preset and preset ~= "Custom" then
        obs.obs_data_set_string(settings, "zoom_preset", "Custom")
        return true
    end
    
    return false
end

----------------------------------------------------------
-- UI Callbacks
----------------------------------------------------------
function on_zoom_blur_changed(props, p, settings)
    local use_blur = obs.obs_data_get_bool(settings, "use_zoom_blur")
    local p_intensity = obs.obs_properties_get(props, "zoom_blur_intensity")
    local p_radius = obs.obs_properties_get(props, "zoom_blur_inactive_radius")
    if p_intensity then obs.obs_property_set_visible(p_intensity, use_blur) end
    if p_radius then obs.obs_property_set_visible(p_radius, use_blur) end
    return true
end

function on_motion_blur_changed(props, p, settings)
    local use_blur = obs.obs_data_get_bool(settings, "use_motion_blur")
    local p_intensity = obs.obs_properties_get(props, "motion_blur_intensity")
    if p_intensity then obs.obs_property_set_visible(p_intensity, use_blur) end
    return true
end

function script_properties(settings)
    global_settings = settings
    refresh_presets_table(settings)
    local props = obs.obs_properties_create()

    -- ==========================================================
    -- GENERAL SETTINGS
    -- ==========================================================
    local grp_gen = obs.obs_properties_create()
    
    -- Source Selection
    local sources_list = obs.obs_properties_add_list(grp_gen, "source", "Zoom Source", obs.OBS_COMBO_TYPE_LIST, obs.OBS_COMBO_FORMAT_STRING)
    populate_zoom_sources(sources_list)
    
    obs.obs_properties_add_button(grp_gen, "refresh", "Refresh zoom sources", function()
        populate_zoom_sources(sources_list)
        return true
    end)

    -- Preset Selection
    local p_preset = obs.obs_properties_add_list(grp_gen, "zoom_preset", "Animation Preset", obs.OBS_COMBO_TYPE_LIST, obs.OBS_COMBO_FORMAT_STRING)
    obs.obs_property_list_add_string(p_preset, "Custom", "Custom")
    local sorted_keys = {}
    for k, v in pairs(global_presets) do table.insert(sorted_keys, k) end
    table.sort(sorted_keys)
    for _, k in ipairs(sorted_keys) do obs.obs_property_list_add_string(p_preset, k, k) end
    obs.obs_property_set_modified_callback(p_preset, on_settings_modified)
    obs.obs_property_set_long_description(p_preset, "Apply a preset for recommended values.\nChanging sliders manually switches to 'Custom'.")

    -- Manage Presets
    local grp_manage = obs.obs_properties_create()
    obs.obs_properties_add_text(grp_manage, "new_preset_name", "New Name", obs.OBS_TEXT_DEFAULT)
    obs.obs_properties_add_button(grp_manage, "save_preset", "Save Current", function()
        local name = obs.obs_data_get_string(global_settings, "new_preset_name")
        if name == "" or name == "Custom" then return false end
        local array = obs.obs_data_get_array(global_settings, "custom_presets") or obs.obs_data_array_create()
        local found = false
        for i = 0, obs.obs_data_array_count(array) - 1 do
            local item = obs.obs_data_array_item(array, i)
            if obs.obs_data_get_string(item, "name") == name then
                obs.obs_data_set_double(item, "dur", obs.obs_data_get_double(global_settings, "zoom_duration"))
                obs.obs_data_set_double(item, "ovr", obs.obs_data_get_double(global_settings, "zoom_overshoot"))
                obs.obs_data_set_double(item, "smt", obs.obs_data_get_double(global_settings, "follow_smooth_time"))
                found = true
                obs.obs_data_release(item)
                break
            end
            obs.obs_data_release(item)
        end
        if not found then
            local item = obs.obs_data_create()
            obs.obs_data_set_string(item, "name", name)
            obs.obs_data_set_double(item, "dur", obs.obs_data_get_double(global_settings, "zoom_duration"))
            obs.obs_data_set_double(item, "ovr", obs.obs_data_get_double(global_settings, "zoom_overshoot"))
            obs.obs_data_set_double(item, "smt", obs.obs_data_get_double(global_settings, "follow_smooth_time"))
            obs.obs_data_array_push_back(array, item)
            obs.obs_data_release(item)
        end
        obs.obs_data_set_array(global_settings, "custom_presets", array)
        obs.obs_data_array_release(array)
        obs.obs_data_set_string(global_settings, "zoom_preset", name)
        script_update(global_settings)
        return true
    end)
    obs.obs_properties_add_button(grp_manage, "delete_preset", "Delete Current", function()
        local cur = obs.obs_data_get_string(global_settings, "zoom_preset")
        if cur == "Custom" or cur == "Smooth" or cur == "Bounce" or cur == "Snappy" then return false end
        local array = obs.obs_data_get_array(global_settings, "custom_presets")
        if not array then return false end
        local new_array = obs.obs_data_array_create()
        for i = 0, obs.obs_data_array_count(array) - 1 do
            local item = obs.obs_data_array_item(array, i)
            if obs.obs_data_get_string(item, "name") ~= cur then obs.obs_data_array_push_back(new_array, item) end
            obs.obs_data_release(item)
        end
        obs.obs_data_set_array(global_settings, "custom_presets", new_array)
        obs.obs_data_array_release(new_array)
        obs.obs_data_array_release(array)
        obs.obs_data_set_string(global_settings, "zoom_preset", "Custom")
        script_update(global_settings)
        return true
    end)
    obs.obs_properties_add_group(grp_gen, "manage_presets", "Manage Custom Presets", obs.OBS_GROUP_NORMAL, grp_manage)
    
    obs.obs_properties_add_group(props, "gen_settings", "General Settings", obs.OBS_GROUP_NORMAL, grp_gen)

    -- ==========================================================
    -- ANIMATION & ZOOM
    -- ==========================================================
    local grp_anim = obs.obs_properties_create()
    local p_zoom_value = obs.obs_properties_add_float_slider(grp_anim, "zoom_value", "Zoom Factor (X.X)", 1.0, 10.0, 0.1)
    obs.obs_property_set_long_description(p_zoom_value, "How much to zoom in. 2.0 = 200%.")
    
    local p_zoom_dur = obs.obs_properties_add_float_slider(grp_anim, "zoom_duration", "Zoom Duration (s)", 0.05, 3.0, 0.05)
    obs.obs_property_set_modified_callback(p_zoom_dur, on_slider_modified)
    
    local p_overshoot = obs.obs_properties_add_float_slider(grp_anim, "zoom_overshoot", "Zoom Bounce (Overshoot)", 0.0, 1.0, 0.01)
    obs.obs_property_set_modified_callback(p_overshoot, on_slider_modified)
    
    obs.obs_properties_add_group(props, "anim_settings", "Animation & Zoom", obs.OBS_GROUP_NORMAL, grp_anim)

    -- ==========================================================
    -- MOUSE FOLLOW
    -- ==========================================================
    local grp_follow = obs.obs_properties_create()
    local follow = obs.obs_properties_add_bool(grp_follow, "follow", "Enable Auto-Follow Mouse")
    obs.obs_property_set_long_description(follow, "Automatically track mouse when zoomed in.")
    
    local p_smoothness = obs.obs_properties_add_float_slider(grp_follow, "follow_smooth_time", "Follow Weight (Smoothness)", 0.01, 1.0, 0.01)
    obs.obs_property_set_modified_callback(p_smoothness, on_slider_modified)
    
    obs.obs_properties_add_int_slider(grp_follow, "follow_dead_zone", "Dead Zone (Pixels)", 0, 500, 1)
    
    local follow_outside = obs.obs_properties_add_bool(grp_follow, "follow_outside_bounds", "Follow Outside Source Bounds")
    obs.obs_property_set_long_description(follow_outside, "Continue tracking even when cursor leaves the source region.")
        
    obs.obs_properties_add_group(props, "mouse_follow_settings", "Mouse Follow", obs.OBS_GROUP_NORMAL, grp_follow)

    -- ==========================================================
    -- EFFECTS (BLUR)
    -- ==========================================================
    local grp_effects = obs.obs_properties_create()
    obs.obs_properties_add_text(grp_effects, "blur_info", "Requires 'Composite Blur' plugin.\nSet up filters named 'Zoom Blur' and 'Motion Blur' manually.", obs.OBS_TEXT_INFO)
    
    local p_use_zoom_blur = obs.obs_properties_add_bool(grp_effects, "use_zoom_blur", "Enable Focal Zoom Blur")
    local p_zoom_intensity = obs.obs_properties_add_float_slider(grp_effects, "zoom_blur_intensity", "Blur Intensity", 0, 20, 0.5)
    local p_zoom_radius = obs.obs_properties_add_float_slider(grp_effects, "zoom_blur_inactive_radius", "Clear Center Radius", 0, 2000, 1)
    obs.obs_property_set_modified_callback(p_use_zoom_blur, on_zoom_blur_changed)
    
    local p_use_motion_blur = obs.obs_properties_add_bool(grp_effects, "use_motion_blur", "Enable Camera Motion Blur")
    local p_motion_intensity = obs.obs_properties_add_float_slider(grp_effects, "motion_blur_intensity", "Motion Intensity", 0, 20, 0.5)
    obs.obs_property_set_modified_callback(p_use_motion_blur, on_motion_blur_changed)

    -- Sync initial visibility
    on_zoom_blur_changed(props, p_use_zoom_blur, settings)
    on_motion_blur_changed(props, p_use_motion_blur, settings)

    obs.obs_properties_add_group(props, "effect_settings", "Effects (Blur)", obs.OBS_GROUP_NORMAL, grp_effects)

    -- ==========================================================
    -- SMOOTH CURSOR
    -- ==========================================================
    local grp_cursor = obs.obs_properties_create()
    local cursor_source_list = obs.obs_properties_add_list(grp_cursor, "cursor_source", "Arrow Cursor Source", obs.OBS_COMBO_TYPE_LIST, obs.OBS_COMBO_FORMAT_STRING)
    obs.obs_property_list_add_string(cursor_source_list, "None (Disabled)", "")
    
    local p_cursor_pointer_source = obs.obs_properties_add_list(grp_cursor, "cursor_pointer_source", "Hand Cursor Source (Optional)", obs.OBS_COMBO_TYPE_LIST, obs.OBS_COMBO_FORMAT_STRING)
    obs.obs_property_list_add_string(p_cursor_pointer_source, "None", "")
    
    local sources = obs.obs_enum_sources()
    if sources ~= nil then
        for _, src in ipairs(sources) do
            local src_id = obs.obs_source_get_unversioned_id(src)
            if src_id == "image_source" or src_id == "browser_source" then
                local name = obs.obs_source_get_name(src)
                obs.obs_property_list_add_string(cursor_source_list, name, name)
                obs.obs_property_list_add_string(p_cursor_pointer_source, name, name)
            end
        end
        obs.source_list_release(sources)
    end
    
    obs.obs_properties_add_float_slider(grp_cursor, "cursor_scale", "Cursor Scale", 0.1, 5.0, 0.05)
    obs.obs_properties_add_int_slider(grp_cursor, "cursor_offset_x", "X Offset", -100, 100, 1)
    obs.obs_properties_add_int_slider(grp_cursor, "cursor_offset_y", "Y Offset", -100, 100, 1)

    -- Dynamic Cursor
    local rot_mode = obs.obs_properties_add_list(grp_cursor, "cursor_rotation_mode", "Movement Rotation", obs.OBS_COMBO_TYPE_LIST, obs.OBS_COMBO_FORMAT_STRING)
    obs.obs_property_list_add_string(rot_mode, "None (Stay Upright)", "None")
    obs.obs_property_list_add_string(rot_mode, "Lean (Horizontal Tilt)", "Lean")
    obs.obs_property_list_add_string(rot_mode, "Directional (Face Velocity)", "Directional")
    
    obs.obs_properties_add_float_slider(grp_cursor, "cursor_angle_offset", "Base Angle Offset", -180, 180, 1)
    obs.obs_properties_add_float_slider(grp_cursor, "cursor_tilt_strength", "Dynamic Tilt Strength", 0.0, 2.0, 0.05)
    
    obs.obs_properties_add_group(props, "cursor_settings", "Smooth Cursor & Effects", obs.OBS_GROUP_NORMAL, grp_cursor)

    -- ==========================================================
    -- ADVANCED / SYSTEM
    -- ==========================================================
    local grp_adv = obs.obs_properties_create()
    
    local p_debug = obs.obs_properties_add_bool(grp_adv, "debug_logs", "Enable Debug Logging")
    obs.obs_property_set_modified_callback(p_debug, on_settings_modified)
    
    local p_allow_all = obs.obs_properties_add_bool(grp_adv, "allow_all_sources", "List All Sources (Warning: Performance)")
    obs.obs_property_set_modified_callback(p_allow_all, on_settings_modified)
    
    local override_check = obs.obs_properties_add_bool(grp_adv, "use_monitor_override", "Manual Source Override")
    obs.obs_property_set_modified_callback(override_check, on_settings_modified)
    
    local override_x = obs.obs_properties_add_int(grp_adv, "monitor_override_x", "X", -10000, 10000, 1)
    local override_y = obs.obs_properties_add_int(grp_adv, "monitor_override_y", "Y", -10000, 10000, 1)
    local override_w = obs.obs_properties_add_int(grp_adv, "monitor_override_w", "Width", 0, 10000, 1)
    local override_h = obs.obs_properties_add_int(grp_adv, "monitor_override_h", "Height", 0, 10000, 1)
    local override_sx = obs.obs_properties_add_float(grp_adv, "monitor_override_sx", "Scale X", 0, 100, 0.01)
    local override_sy = obs.obs_properties_add_float(grp_adv, "monitor_override_sy", "Scale Y", 0, 100, 0.01)
    local override_dw = obs.obs_properties_add_int(grp_adv, "monitor_override_dw", "Mon. Width", 0, 10000, 1)
    local override_dh = obs.obs_properties_add_int(grp_adv, "monitor_override_dh", "Mon. Height", 0, 10000, 1)
    
    -- Sync override visibility
    on_settings_modified(props, override_check, settings)
    
    if socket_available then
        local r_label = obs.obs_properties_add_text(grp_adv, "socket_label", "Socket requires 'luasocket'.", obs.OBS_TEXT_INFO)
        local socket_check = obs.obs_properties_add_bool(grp_adv, "use_socket", "Remote Network Listener")
        obs.obs_property_set_modified_callback(socket_check, on_settings_modified)
        obs.obs_properties_add_int(grp_adv, "socket_port", "Listener Port", 1024, 65535, 1)
        obs.obs_properties_add_int(grp_adv, "socket_poll", "Poll Rate (ms)", 1, 1000, 1)
        
        -- Sync socket visibility
        on_settings_modified(props, socket_check, settings)
    end

    obs.obs_properties_add_group(props, "adv_settings", "Advanced & System", obs.OBS_GROUP_NORMAL, grp_adv)

    -- ==========================================================
    -- HELP & FAQ
    -- ==========================================================
    local grp_help = obs.obs_properties_create()
    obs.obs_properties_add_text(grp_help, "help_txt", 
        "QUICK START:\n" ..
        "1. Select your Display/Game Capture in 'Zoom Source'.\n" ..
        "2. Set a hotkey in OBS Settings > Hotkeys > 'Toggle zoom to mouse'.\n" ..
        "3. Adjust 'Zoom Factor' and 'Animation Preset' to your liking.\n\n" ..
        "TIPS:\n" ..
        "• Dead Zone: Prevents tiny mouse jitters from moving the camera.\n" ..
        "• Smoothness: Higher values feel more 'cinematic' but laggier.\n" ..
        "• Smooth Cursor: Overlay an image to fix 'original cursor' vanishing in some captures.", 
        obs.OBS_TEXT_INFO)
    obs.obs_properties_add_group(props, "help_section", "Help & FAQ", obs.OBS_GROUP_NORMAL, grp_help)

    return props
end


function script_load(settings)
    sceneitem_info_orig = nil

    -- Workaround for detecting if OBS is already loaded and we were reloaded using "Reload Scripts"
    local current_scene = obs.obs_frontend_get_current_scene()
    is_obs_loaded = current_scene ~= nil -- Current scene is nil on first OBS load
    obs.obs_source_release(current_scene)

    -- Add our hotkey
    hotkey_zoom_id = obs.obs_hotkey_register_frontend("toggle_zoom_hotkey", "Toggle zoom to mouse",
        on_toggle_zoom)

    hotkey_follow_id = obs.obs_hotkey_register_frontend("toggle_follow_hotkey", "Toggle follow mouse during zoom",
        on_toggle_follow)

    -- Attempt to reload existing hotkey bindings if we can find any
    local hotkey_save_array = obs.obs_data_get_array(settings, "obs_zoom_to_mouse.hotkey.zoom")
    obs.obs_hotkey_load(hotkey_zoom_id, hotkey_save_array)
    obs.obs_data_array_release(hotkey_save_array)

    hotkey_save_array = obs.obs_data_get_array(settings, "obs_zoom_to_mouse.hotkey.follow")
    obs.obs_hotkey_load(hotkey_follow_id, hotkey_save_array)
    obs.obs_data_array_release(hotkey_save_array)

    obs.obs_frontend_add_event_callback(on_frontend_event)

    if debug_logs then
        log_current_settings()
    end

    -- Add the transition_start event handlers to each transition (the global source_transition_start event never fires)
    local transitions = obs.obs_frontend_get_transitions()
    if transitions ~= nil then
        for i, s in pairs(transitions) do
            local name = obs.obs_source_get_name(s)
            log("Adding transition_start listener to " .. name)
            local handler = obs.obs_source_get_signal_handler(s)
            obs.signal_handler_connect(handler, "transition_start", on_transition_start)
        end
        obs.source_list_release(transitions)
    end

    if ffi.os == "Linux" and not x11_display then
        log("ERROR: Could not get X11 Display for Linux\n" ..
            "Mouse position will be incorrect.")
    end

    source_name = ""
    use_socket = false
    is_script_loaded = true
    script_update(settings)
end

function script_unload()
    is_script_loaded = false

    -- Clean up the memory usage
    if major > 29.1 or (major == 29.1 and minor > 2) then -- 29.1.2 and below seems to crash if you do this, so we ignore it as the script is closing anyway
        local transitions = obs.obs_frontend_get_transitions()
        if transitions ~= nil then
            for i, s in pairs(transitions) do
                local handler = obs.obs_source_get_signal_handler(s)
                obs.signal_handler_disconnect(handler, "transition_start", on_transition_start)
            end
            obs.source_list_release(transitions)
        end

        obs.obs_hotkey_unregister(on_toggle_zoom)
        obs.obs_hotkey_unregister(on_toggle_follow)
        obs.obs_frontend_remove_event_callback(on_frontend_event)
        release_sceneitem()
    end

    if x11_lib ~= nil and x11_display ~= nil then
        x11_lib.XCloseDisplay(x11_display)
        x11_display = nil
        x11_lib = nil
    end

    if socket_server ~= nil then
        stop_server()
    end
end

function script_defaults(settings)
    -- Default values for the script
    obs.obs_data_set_default_double(settings, "zoom_value", 2)
    -- obs.obs_data_set_default_double(settings, "zoom_speed", 0.06) -- Deprecated
    obs.obs_data_set_default_double(settings, "zoom_duration", 0.6)
    obs.obs_data_set_default_double(settings, "zoom_overshoot", 0.0)
    obs.obs_data_set_default_string(settings, "zoom_preset", "Smooth")
    
    obs.obs_data_set_default_bool(settings, "follow", true)
    obs.obs_data_set_default_bool(settings, "follow_outside_bounds", false)
    -- obs.obs_data_set_default_double(settings, "follow_speed", 0.25) -- Deprecated
    obs.obs_data_set_default_double(settings, "follow_smooth_time", 0.15)
    obs.obs_data_set_default_int(settings, "follow_dead_zone", 5)
    
    -- Animation Defaults
    obs.obs_data_set_default_double(settings, "zoom_value", 2.0)
    obs.obs_data_set_default_double(settings, "zoom_speed", 0.12)
    obs.obs_data_set_default_bool(settings, "use_zoom_blur", false)
    obs.obs_data_set_default_double(settings, "zoom_blur_intensity", 5)
    obs.obs_data_set_default_double(settings, "zoom_blur_inactive_radius", 150)

    -- Mouse Follow Defaults
    obs.obs_data_set_default_bool(settings, "start_enabled", true)
    obs.obs_data_set_default_bool(settings, "use_motion_blur", false)
    obs.obs_data_set_default_double(settings, "motion_blur_intensity", 1.0)
    
    obs.obs_data_set_default_bool(settings, "allow_all_sources", false)
    obs.obs_data_set_default_bool(settings, "use_monitor_override", false)
    obs.obs_data_set_default_int(settings, "monitor_override_x", 0)
    obs.obs_data_set_default_int(settings, "monitor_override_y", 0)
    obs.obs_data_set_default_int(settings, "monitor_override_w", 1920)
    obs.obs_data_set_default_int(settings, "monitor_override_h", 1080)
    obs.obs_data_set_default_double(settings, "monitor_override_sx", 1)
    obs.obs_data_set_default_double(settings, "monitor_override_sy", 1)
    obs.obs_data_set_default_int(settings, "monitor_override_dw", 1920)
    obs.obs_data_set_default_int(settings, "monitor_override_dh", 1080)
    obs.obs_data_set_default_bool(settings, "use_socket", false)
    obs.obs_data_set_default_int(settings, "socket_port", 12345)
    obs.obs_data_set_default_int(settings, "socket_poll", 10)
    obs.obs_data_set_default_bool(settings, "debug_logs", false)
    
    -- Smooth Cursor Defaults
    obs.obs_data_set_default_string(settings, "cursor_source", "")
    obs.obs_data_set_default_string(settings, "cursor_pointer_source", "")
    obs.obs_data_set_default_double(settings, "cursor_scale", 1.0)
    obs.obs_data_set_default_int(settings, "cursor_offset_x", -6)
    obs.obs_data_set_default_int(settings, "cursor_offset_y", -2)
    
    -- Dynamic Cursor Defaults
    obs.obs_data_set_default_string(settings, "cursor_rotation_mode", "None")
    obs.obs_data_set_default_double(settings, "cursor_angle_offset", 0.0)
    obs.obs_data_set_default_double(settings, "cursor_tilt_strength", 0.0)
end

function script_save(settings)
    -- Save the custom hotkey information
    if hotkey_zoom_id ~= nil then
        local hotkey_save_array = obs.obs_hotkey_save(hotkey_zoom_id)
        obs.obs_data_set_array(settings, "obs_zoom_to_mouse.hotkey.zoom", hotkey_save_array)
        obs.obs_data_array_release(hotkey_save_array)
    end

    if hotkey_follow_id ~= nil then
        local hotkey_save_array = obs.obs_hotkey_save(hotkey_follow_id)
        obs.obs_data_set_array(settings, "obs_zoom_to_mouse.hotkey.follow", hotkey_save_array)
        obs.obs_data_array_release(hotkey_save_array)
    end
end

function script_update(settings)
    global_settings = settings
    refresh_presets_table(settings)
    
    local old_source_name = source_name
    local old_override = use_monitor_override
    local old_x = monitor_override_x
    local old_y = monitor_override_y
    local old_w = monitor_override_w
    local old_h = monitor_override_h
    local old_sx = monitor_override_sx
    local old_sy = monitor_override_sy
    local old_dw = monitor_override_dw
    local old_dh = monitor_override_dh
    local old_socket = use_socket
    local old_port = socket_port
    local old_poll = socket_poll
    local old_use_zoom_blur = use_zoom_blur
    local old_use_motion_blur = use_motion_blur

    -- Update the settings
    source_name = obs.obs_data_get_string(settings, "source")
    zoom_value = obs.obs_data_get_double(settings, "zoom_value")
    -- zoom_speed = obs.obs_data_get_double(settings, "zoom_speed")
    zoom_duration = obs.obs_data_get_double(settings, "zoom_duration")
    zoom_overshoot = obs.obs_data_get_double(settings, "zoom_overshoot")
    zoom_preset = obs.obs_data_get_string(settings, "zoom_preset")
    
    use_auto_follow_mouse = obs.obs_data_get_bool(settings, "follow")
    use_follow_outside_bounds = obs.obs_data_get_bool(settings, "follow_outside_bounds")
    -- follow_speed = obs.obs_data_get_double(settings, "follow_speed")
    follow_smooth_time = obs.obs_data_get_double(settings, "follow_smooth_time")
    
    -- Apply preset logic AFTER loading from settings (so presets can override if active)
    if global_presets[zoom_preset] then
        local p = global_presets[zoom_preset]
        zoom_duration = p.dur
        zoom_overshoot = p.ovr
        follow_smooth_time = p.smt
    end
    follow_dead_zone = obs.obs_data_get_int(settings, "follow_dead_zone")
    
    use_zoom_blur = obs.obs_data_get_bool(settings, "use_zoom_blur")
    zoom_blur_intensity = obs.obs_data_get_double(settings, "zoom_blur_intensity")
    zoom_blur_inactive_radius = obs.obs_data_get_double(settings, "zoom_blur_inactive_radius")
    
    -- Mouse Follow
    local start_enabled = obs.obs_data_get_bool(settings, "start_enabled")
    use_motion_blur = obs.obs_data_get_bool(settings, "use_motion_blur")
    motion_blur_intensity = obs.obs_data_get_double(settings, "motion_blur_intensity")
    
    allow_all_sources = obs.obs_data_get_bool(settings, "allow_all_sources")
    use_monitor_override = obs.obs_data_get_bool(settings, "use_monitor_override")
    monitor_override_x = obs.obs_data_get_int(settings, "monitor_override_x")
    monitor_override_y = obs.obs_data_get_int(settings, "monitor_override_y")
    monitor_override_w = obs.obs_data_get_int(settings, "monitor_override_w")
    monitor_override_h = obs.obs_data_get_int(settings, "monitor_override_h")
    monitor_override_sx = obs.obs_data_get_double(settings, "monitor_override_sx")
    monitor_override_sy = obs.obs_data_get_double(settings, "monitor_override_sy")
    monitor_override_dw = obs.obs_data_get_int(settings, "monitor_override_dw")
    monitor_override_dh = obs.obs_data_get_int(settings, "monitor_override_dh")
    use_socket = obs.obs_data_get_bool(settings, "use_socket")
    socket_port = obs.obs_data_get_int(settings, "socket_port")
    socket_poll = obs.obs_data_get_int(settings, "socket_poll")
    debug_logs = obs.obs_data_get_bool(settings, "debug_logs")

    -- Only do the expensive refresh if the user selected a new source
    if source_name ~= old_source_name and is_obs_loaded then
        refresh_sceneitem(true)
    end

    if use_zoom_blur ~= old_use_zoom_blur or use_motion_blur ~= old_use_motion_blur or source_name ~= old_source_name then
        refresh_blur_filters()
    end

    -- Update the monitor_info if the settings changed
    if source_name ~= old_source_name or
        use_monitor_override ~= old_override or
        monitor_override_x ~= old_x or
        monitor_override_y ~= old_y or
        monitor_override_w ~= old_w or
        monitor_override_h ~= old_h or
        monitor_override_sx ~= old_sx or
        monitor_override_sy ~= old_sy or
        monitor_override_w ~= old_dw or
        monitor_override_h ~= old_dh then
        if is_obs_loaded then
            monitor_info = get_monitor_info(source)
        end
    end

    if old_socket ~= use_socket then
        if use_socket then
            start_server()
        else
            stop_server()
        end
    elseif use_socket and (old_poll ~= socket_poll or old_port ~= socket_port) then
        stop_server()
        start_server()
    end
    
    local new_cursor_name = obs.obs_data_get_string(settings, "cursor_source")
    local new_pointer_name = obs.obs_data_get_string(settings, "cursor_pointer_source")
    cursor_scale = obs.obs_data_get_double(settings, "cursor_scale")
    if cursor_scale <= 0 then cursor_scale = 1.0 end
    
    cursor_offset_x = obs.obs_data_get_int(settings, "cursor_offset_x")
    cursor_offset_y = obs.obs_data_get_int(settings, "cursor_offset_y")
    
    -- Dynamic Cursor
    cursor_rotation_mode = obs.obs_data_get_string(settings, "cursor_rotation_mode")
    cursor_angle_offset = obs.obs_data_get_double(settings, "cursor_angle_offset")
    cursor_tilt_strength = obs.obs_data_get_double(settings, "cursor_tilt_strength")
    
    -- Refresh both cursor and pointer items if changed (or force on first load)
    if new_cursor_name ~= cursor_source_name or (cursor_sceneitem == nil and new_cursor_name ~= "") then
        cursor_source_name = new_cursor_name
        refresh_cursor_item(cursor_source_name, false)
    end
    if new_pointer_name ~= cursor_pointer_source_name or (cursor_pointer_sceneitem == nil and new_pointer_name ~= "") then
        cursor_pointer_source_name = new_pointer_name
        refresh_cursor_item(cursor_pointer_source_name, true)
    end
end

function populate_zoom_sources(list)
    obs.obs_property_list_clear(list)

    local sources = obs.obs_enum_sources()
    if sources ~= nil then
        local dc_info = get_dc_info()
        obs.obs_property_list_add_string(list, "<None>", "obs-zoom-to-mouse-none")
        for _, source in ipairs(sources) do
            local source_type = obs.obs_source_get_id(source)
            if source_type == dc_info.source_id or allow_all_sources then
                local name = obs.obs_source_get_name(source)
                obs.obs_property_list_add_string(list, name, name)
            end
        end

        obs.source_list_release(sources)
    end
end