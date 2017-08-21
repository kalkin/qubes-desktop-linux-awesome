----------------------------------------------------------------------------
-- Qubes OS bridge
-- @copyright 2014 Invisible Things Lab
-- @copyright 2014 Wojciech Porczyk <woju@invisiblethingslab.com>
-- license: GPL-2+
----------------------------------------------------------------------------

local io = io
local math = math
local string = string
local tonumber = tonumber
local table = table

local util = require('awful.util')
local color = require('gears.color')
local beautiful = require('beautiful')
local menubar = require('menubar')

local qubes = {}

local naughty = require("naughty")

-- the following three functions are lifted from
--  /usr/lib64/python2.7/colorsys.py

-- XXX this belongs to /usr/share/awesome/lib/gears/colors.lua

local function rgb_to_hls(r, g, b)
    maxc = math.max(r, g, b)
    minc = math.min(r, g, b)
    -- XXX Can optimize (maxc+minc) and (maxc-minc)
    l = (minc+maxc)/2.0
    if minc == maxc then
        return 0.0, l, 0.0
    end
    if l <= 0.5 then
        s = (maxc-minc) / (maxc+minc)
    else
        s = (maxc-minc) / (2.0-maxc-minc)
    end
    rc = (maxc-r) / (maxc-minc)
    gc = (maxc-g) / (maxc-minc)
    bc = (maxc-b) / (maxc-minc)
    if r == maxc then
        h = bc-gc
    elseif g == maxc then
        h = 2.0+rc-bc
    else
        h = 4.0+gc-rc
    end
    h = (h/6.0) % 1.0
    return h, l, s
end

local function v(m1, m2, hue)
    hue = hue % 1.0
    if hue < 1/6 then
        return m1 + (m2-m1)*hue*6.0
    end
    if hue < 0.5 then
        return m2
    end
    if hue < 2/3 then
        return m1 + (m2-m1)*(2/3-hue)*6.0
    end
    return m1
end

local function hls_to_rgb(h, l, s)
    if s == 0.0 then
        return l, l, l
    end
    if l <= 0.5 then
        m2 = l * (1.0+s)
    else
        m2 = l+s-(l*s)
    end
    m1 = 2.0*l - m2
    return v(m1, m2, h+1/3), v(m1, m2, h), v(m1, m2, h-1/3)
end

-- end of codelifting

local function parse_desktop_file(desktop)
    local entry = {}
    for line in io.lines(desktop) do
        key, value = line:match('^(%w+)%s*=%s*(.*)$')
        if key ~= nil then
            entry[key] = value
        end
    end
    return entry
end

local function shift_luminance(colour, factor)
    local r, g, b = color.parse_color(colour)

    h, l, s = rgb_to_hls(r, g, b)
    l = math.max(math.min(l * factor, 1), 0)
    r, g, b = hls_to_rgb(h, l, s)

    return string.format('#%02x%02x%02x',
        math.floor(r * 0xff), math.floor(g * 0xff), math.floor(b * 0xff))
end

local function pread(cmd)
    local f, err = io.popen(cmd, 'r')
    if f then
        local data = f:read("*all")
        f:close()
        return data
    else
        error("Command failed:\n" .. cmd .. "\nwith error:\n" .. err )
    end
end

function qubes.init()
    -- read labels
    qubes.labels = { ['*'] = {
        colour = beautiful.border_normal,
        colour_focus = "#000000" 
     } }

    local cmd = [[python3 -c "
import qubesadmin.app
app = qubesadmin.Qubes()
print(''.join('{}:{}\n'.format(l.index, l.color)
    for l in app.labels))
"]]

    local data = pread(cmd)
    for index, colour in string.gmatch(data, '(%d):0x([0-9a-f]+)') do
        colour = '#' .. colour
            qubes.labels[index] = { colour = shift_luminance(colour, 0.5),
            colour_focus = shift_luminance(colour, 1.0) }
    end
end


function qubes.manage(c)
    if c.qubes_vmname ~= nil then return end

    local cmd = 'xprop -id ' .. c.window .. ' -notype _QUBES_VMNAME _QUBES_LABEL'
    local data = pread(cmd)
    c.qubes_vmname = string.match(data, '_QUBES_VMNAME = "(.+)"') or 'dom0'
    c.qubes_label = string.match(data, '_QUBES_LABEL = (%d+)') or '*'
    c.prefix = '[' .. c.qubes_vmname .. '] '
    c.border_color = qubes.get_colour_focus (c)
end

function qubes.get_label(c)
    if qubes.labels == nil then
        qubes.init()
    end
    local label = c.qubes_label
    return qubes.labels[label] or qubes.labels['*']
end

function qubes.get_colour(c)
    return qubes.get_label(c).colour
end

function qubes.get_colour_focus(c)
    return qubes.get_label(c).colour_focus
end

function qubes.make_vm_menu(vmname, vmpath)
    local menu = {}

--    for desktop in io.popen('ls -1 ' .. vmpath .. '/apps/*.desktop'):lines() do
--        local entry = parse_desktop_file(desktop)
--      if entry['Icon'] == nil then
--          entry['Icon'] = vmpath .. '/icon.png'
--      end
--        table.insert(menu, {entry['Name'], entry['Exec'], entry['Icon']})
--    end

    for _, program in ipairs(menubar.utils.parse_dir(vmpath .. '/apps')) do
        table.insert(menu, {program.Name, program.cmdline, program.icon_path})
end
    return {vmname, menu, vmpath .. '/icon.png'}
end

function qubes.make_menu()
    local menu = {}
    for line in io.popen([[python -c "
import os.path
import qubes.qubes
qvmc = qubes.qubes.QubesVmCollection()
qvmc.lock_db_for_reading()
qvmc.load()
qvmc.unlock_db()
print('\n'.join('{} {}'.format(vm.name, vm.dir_path)
    for vm in sorted(qvmc.values(), key=lambda vm: vm.name)
    if os.path.isdir(vm.dir_path)))
"]]):lines() do
        local vmname, vmpath = line:match('^(.+) (.+)$')
        io.stderr:write('line=' .. line .. '\n')
        table.insert(menu, qubes.make_vm_menu(vmname, vmpath))
    end
    table.insert(menu, {'Qubes Manager', 'qubes-manager',
        '/usr/share/icons/hicolor/16x16/apps/qubes-logo-icon.png'})
    return menu
end

return qubes

-- vim: ts=4 sw=4 et
