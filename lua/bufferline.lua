require 'buffers'
local colors = require 'colors'
local highlights = require 'highlights'
local helpers = require 'helpers'

local api = vim.api
-- string.len counts number of bytes and so the unicode icons are counted
-- larger than their display width. So we use nvim's strwidth
local strwidth = vim.fn.strwidth

---------------------------------------------------------------------------//
-- Constants
---------------------------------------------------------------------------//
local padding = " "

local superscript_numbers = {
  [0] = '⁰',
  [1] = '¹',
  [2] = '²',
  [3] = '³',
  [4] = '⁴',
  [5] = '⁵',
  [6] = '⁶',
  [7] = '⁷',
  [8] = '⁸',
  [9] = '⁹',
  [10] = '¹⁰',
  [11] = '¹¹',
  [12] = '¹²',
  [13] = '¹³',
  [14] = '¹⁴',
  [15] = '¹⁵',
  [16] = '¹⁶',
  [17] = '¹⁷',
  [18] = '¹⁸',
  [19] = '¹⁹',
  [20] = '²⁰'
}
-------------------------------------------------------------------------//
-- EXPORT
---------------------------------------------------------------------------//

local M = {
  shade_color = colors.shade_color
}

-- Source: https://teukka.tech/luanvim.html
local function nvim_create_augroups(definitions)
  for group_name, definition in pairs(definitions) do
    vim.cmd('augroup '..group_name)
    vim.cmd('autocmd!')
    for _,def in pairs(definition) do
      local command = table.concat(vim.tbl_flatten{'autocmd', def}, ' ')
      vim.cmd(command)
    end
    vim.cmd('augroup END')
  end
end

--- @param mode string | nil
--- @param item string
--- @param buf_num number
local function make_clickable(mode, item, buf_num)
  if not vim.fn.has('tablineat') then return item end
  -- v:lua does not support function references in vimscript so
  -- the only way to implement this is using autoload viml functions
  if mode == "multiwindow" then
    return "%"..buf_num.."@nvim_bufferline#handle_win_click@"..item
  else
    return "%"..buf_num.."@nvim_bufferline#handle_click@"..item
  end
end

-- @param buf_id number
local function close_button(buf_id)
  local symbol = ""..padding
  local size = strwidth(symbol)
  return "%" .. buf_id .. "@nvim_bufferline#handle_close_buffer@".. symbol, size
end
---------------------------------------------------------------------------//
-- CORE
---------------------------------------------------------------------------//
function M.handle_close_buffer(buf_id)
  vim.cmd("bdelete ".. buf_id)
end

function M.handle_win_click(id)
  local win_id = vim.fn.bufwinid(id)
  vim.fn.win_gotoid(win_id)
end

function M.handle_click(id)
  if id then
    vim.cmd('buffer '..id)
  end
end

local function get_buffer_highlight(buffer)
  if buffer:current() then
    return highlights.selected, highlights.modified_selected
  elseif buffer:visible() then
    return highlights.inactive, highlights.modified_inactive
  else
    return highlights.background, highlights.modified
  end
end

local function get_number_prefix(buffer, mode, style)
  local n = mode == "ordinal" and buffer.ordinal or buffer.id
  local num = style == "superscript" and superscript_numbers[n] or n .. "."
  return num
end

local function truncate_filename(filename, word_limit)
  local trunc_symbol = '…' -- '...'
  local too_long = string.len(filename) > word_limit
  return too_long and string.sub(filename, 0, word_limit) .. trunc_symbol or filename
end

--[[
 In order to get the accurate character width of a buffer tab
 each buffer's length is manually calculated to avoid accidentally
 incorporating highlight strings into the buffer tab count
 e.g. %#HighlightName%filename.js should be 11 but strwidth will
 include the highlight in the count
 TODO
 Workout a function either using vim's regex or lua's to remove
 a highlight string. For example:
 -----------------------------------
  [WIP]
 -----------------------------------
 function get_actual_length(component)
  local formatted = string.gsub(component, '%%#.*#', '')
  print(formatted)
  return strwidth(formatted)
 end
--]]
--- @param options table
--- @param buffer Buffer
--- @param diagnostic_count number
--- @param buffer_length number
--- @return function | number @comment returns a render function and length
local function render_buffer(options, buffer, diagnostic_count, buffer_length)
  local buf_highlight, modified_hl_to_use = get_buffer_highlight(buffer)
  local length = 0
  local is_current = buffer:current()
  local is_visible = buffer:visible()

  local filename = truncate_filename(buffer.filename, options.max_name_length)
  local component = buffer.icon..padding..filename..padding
  -- Initial component size without highlights
  length = length + strwidth(component)

  local modified_icon = helpers.get_plugin_variable("modified_icon", "●")
  local modified_section = modified_icon..padding
  local m_size = strwidth(modified_section)
  local m_padding = string.rep(padding, m_size)

  -- If the buffer is modifiable add an icon but even if it isn't pad
  -- the buffer so it doesn't "jump" when it becomes modified i.e. due
  -- to the sudden addition of a new character
  if buffer.modifiable and buffer.modified then
    component = m_padding..component..modified_hl_to_use..modified_section
  else
    component = m_padding..component.. m_padding
  end
  -- Add the length of modified symbol and the associated padding
  length = length + (m_size * 2)

  -- Check if the component is smaller than the max size if so
  -- pad it so to make it's size consistent with the maximum
  -- allowed size
  if strwidth(length) < buffer_length then
    local difference = buffer_length - string.len(component)
    local pad = string.rep(padding, math.ceil((difference / 2)))
    component = pad .. component .. pad
    -- Add the size of the padding to the length of the buffer
    length = strwidth(pad) * 2
  end

  if options.numbers ~= "none" then
    local number_prefix = get_number_prefix(
      buffer,
      options.numbers,
      options.number_style
    )
    local number_component = number_prefix .. padding
    component = number_component  .. component
    length = length + strwidth(number_component)
  end

  component = make_clickable(options.mode, component, buffer.id)

  if is_current then
    -- U+2590 ▐ Right half block, this character is right aligned so the
    -- background highlight doesn't appear in th middle
    -- alternatives:  right aligned => ▕ ▐ ,  left aligned => ▍
    local indicator_symbol = '▎'
    local indicator = highlights.indicator .. indicator_symbol .. '%*'

    length = length + strwidth(indicator_symbol)
    component = indicator .. buf_highlight .. component
  else
    -- since all non-current buffers do not have an indicator they need
    -- to be padded to make up the difference in size
    length = length + strwidth(padding)
    component = buf_highlight .. padding .. component
  end

  if diagnostic_count > 0 then
    local diagnostic_section = diagnostic_count..padding
    component = component..highlights.diagnostic..diagnostic_section
    length = length + strwidth(diagnostic_section)
  end

  if options.show_buffer_close_icons then
    local close_btn, size = close_button(buffer.id)
    component = component .. buf_highlight ..close_btn
    length = length + size
  end

  -- Use: https://en.wikipedia.org/wiki/Block_Elements
  local separator_component
  if options.separator_style == 'thick' then
    separator_component = (is_visible or is_current) and "▌" or "▐"-- "▍" "░"
  else
    separator_component = (is_visible or is_current) and "▏" or "▕"
  end

  local separator = highlights.separator..separator_component

  -- NOTE: the component is wrapped in an item -> %(content) so
  -- vim counts each item as one rather than all of its individual
  -- sub-components. Vim only allows a maximum of 80 items in a tabline
  -- so it is important that these are correctly group as one
  local buffer_component = "%("..component.."%)"


  -- We increment the buffer length by the separator although the final
  -- buffer will not have a separator so we are technically off by 1
  length = length + strwidth(separator_component)

  -- We return a function from render buffer as we do not yet have access to
  -- information regarding which buffers will actually be rendered

  --- @param index number
  --- @param num_of_bufs number
  --- @returns string
  local render_fn  = function (index, num_of_bufs)
    if index < num_of_bufs then
      buffer_component =  buffer_component .. separator
    end
    return buffer_component
  end

  return render_fn, length
end

local function tab_click_component(num)
  return "%"..num.."T"
end

local function render_tab(tab, is_active)
  local hl = is_active and highlights.tab_selected or highlights.tab
  local name = padding..tab.tabnr..padding
  local length = strwidth(name)
  return hl .. tab_click_component(tab.tabnr) .. name, length
end

local function get_tabs()
  local all_tabs = {}
  local tabs = vim.fn.gettabinfo()
  local current_tab = vim.fn.tabpagenr()

  -- use ordinals to ensure a contiguous keys in the table i.e. an array
  -- rather than an object
  -- GOOD = {1: thing, 2: thing} BAD: {1: thing, [5]: thing}
  for i,tab in ipairs(tabs) do
    local is_active_tab = current_tab == tab.tabnr
    local component, length = render_tab(tab, is_active_tab)
    all_tabs[i] = {
      component = component,
      length = length,
      id = tab.tabnr,
      windows = tab.windows,
    }
  end
  return all_tabs
end

local function render_close(icon)
  local component = padding .. icon .. padding
  return component, strwidth(component)
end

-- The provided api nvim_is_buf_loaded filters out all hidden buffers
local function is_valid(buf_num)
  if not buf_num or buf_num < 1 then return false end
  local listed = vim.fn.getbufvar(buf_num, "&buflisted") == 1
  local exists = api.nvim_buf_is_valid(buf_num)
  return listed and exists
end

local function get_sections(buffers)
  local current = Buffers:new()
  local before = Buffers:new()
  local after = Buffers:new()

  for _,buf in ipairs(buffers) do
    if buf:current() then
      current:add(buf)
    -- We haven't reached the current buffer yet
    elseif current.length == 0 then
      before:add(buf)
    else
      after:add(buf)
    end
  end
  return before, current, after
end

local function get_marker_size(count, element_size)
  return count > 0 and strwidth(count) + element_size or 0
end

local function render_trunc_marker(count, icon)
  return highlights.fill..padding..count..padding..icon..padding
end

--[[
PREREQUISITE: active buffer always remains in view
1. Find amount of available space in the window
2. Find the amount of space the bufferline will take up
3. If the bufferline will be too long remove one tab from the before or after
section
4. Re-check the size, if still too long truncate recursively till it fits
5. Add the number of truncated buffers as an indicator
--]]
local function truncate(before, current, after, available_width, marker)
  local line = ""
  local left_trunc_marker = get_marker_size(marker.left_count, marker.left_element_size)
  local right_trunc_marker = get_marker_size(marker.right_count, marker.right_element_size)
  local markers_length = left_trunc_marker + right_trunc_marker
  local total_length = before.length + current.length + after.length + markers_length

  if available_width >= total_length then
    -- Merge all the buffers and render the components
    local buffers = helpers.array_concat(
      before.buffers,
      current.buffers,
      after.buffers
    )
    for index,buf in ipairs(buffers) do
      line = line .. buf.component(index, table.getn(buffers))
    end
    return line, marker
  else
    if before.length >= after.length then
      before:drop(1)
      marker.left_count = marker.left_count + 1
    else
      after:drop(#after.buffers)
      marker.right_count = marker.right_count + 1
    end
    return truncate(before, current, after, available_width, marker), marker
  end
end

local function render(buffers, tabs, close_icon)
  local right_align = "%="
  local tab_components = ""
  local close_component, close_length = render_close(close_icon)
  local tabs_length = close_length

  -- Add the length of the tabs + close components to total length
  if table.getn(tabs) > 1 then
    for _,t in pairs(tabs) do
      if not vim.tbl_isempty(t) then
        tabs_length = tabs_length + t.length
        tab_components = tab_components .. t.component
      end
    end
  end

  -- Icons from https://fontawesome.com/cheatsheet
  local left_trunc_icon = helpers.get_plugin_variable("left_trunc_marker", "")
  local right_trunc_icon = helpers.get_plugin_variable("right_trunc_marker", "")
  -- measure the surrounding trunc items: padding + count + padding + icon + padding
  local left_element_size = strwidth(padding..padding..left_trunc_icon..padding..padding)
  local right_element_size = strwidth(padding..padding..right_trunc_icon..padding)

  local available_width = vim.o.columns - tabs_length - close_length
  local before, current, after = get_sections(buffers)
  local line, marker = truncate(
    before,
    current,
    after,
    available_width,
    {
      left_count = 0,
      right_count = 0,
      left_element_size = left_element_size,
      right_element_size = right_element_size,
    }
  )

  if marker.left_count > 0 then
    local icon = render_trunc_marker(marker.left_count, left_trunc_icon)
    line = highlights.background..icon..padding..line
  end
  if marker.right_count > 0 then
    local icon = render_trunc_marker(marker.right_count, right_trunc_icon)
    line = line..highlights.background..icon
  end

  return line..highlights.fill..right_align..tab_components..highlights.close..close_component
end

--- @param bufs table | nil
local function get_valid_buffers(bufs)
  local buf_nums = bufs or api.nvim_list_bufs()
  local valid_bufs = {}

  -- NOTE: In lua in order to iterate an array, indices should
  -- not contain gaps otherwise "ipairs" will stop at the first gap
  -- i.e the indices should be contiguous
  local count = 0
  for _,buf in ipairs(buf_nums) do
    if is_valid(buf) then
      count = count + 1
      valid_bufs[count] = buf
    end
  end
  return valid_bufs
end

--- @param mode string | nil
local function get_buffers_by_mode(mode)
--[[
  show only relevant buffers depending on the layout of the current tabpage:
    - In tabs with only one window all buffers are listed.
    - In tabs with more than one window, only the buffers that are being displayed are listed.
--]]
  if mode == "multiwindow" then
    local current_tab = vim.fn.tabpagenr()
    local is_single_tab = vim.fn.tabpagenr('$') == 1
    local number_of_tab_wins = vim.fn.tabpagewinnr(current_tab, '$')
    local valid_wins = 0
    -- Check that the window contains a listed buffer, if the buffre isn't
    -- listed we shouldn't be hiding the remaining buffers because of it
    -- FIXME this is sending an invalid buf_nr to is_valid buf
    for i=1,number_of_tab_wins do
      local buf_nr = vim.fn.winbufnr(i)
      if is_valid(buf_nr) then
        valid_wins = valid_wins + 1
      end
    end
    if valid_wins > 1 and not is_single_tab then
      -- TODO filter out duplicates because currently I don't know
      -- how to make it clear which buffer relates to which window
      -- buffers don't have an identifier to say which buffer they are in
      local unique = helpers.filter_duplicates(vim.fn.tabpagebuflist())
      return get_valid_buffers(unique), mode
    end
  end
  return get_valid_buffers(), nil
end

--[[
TODO
===========
 [ ] Investigate using guibg=none for modified symbol highlight instead of multiple highlight groups per status
 [ ] Highlight file type icons if possible see:
  https://github.com/weirongxu/coc-explorer/blob/59bd41f8fffdc871fbd77ac443548426bd31d2c3/src/icons.nerdfont.json#L2
--]]
--- @param options table<string, string>
--- @return string
local function bufferline(options)
  local buf_nums, current_mode = get_buffers_by_mode(options.view)
  local buffers = {}
  local tabs = get_tabs()
  options.view = current_mode

  local buffer_length = options.max_name_length
  for i, buf_id in ipairs(buf_nums) do
      local name =  vim.fn.bufname(buf_id)
      local buf = Buffer:new {path = name, id = buf_id, ordinal = i}
      local render_fn, length = render_buffer(options, buf, 0, buffer_length)
      buf.length = length
      buf.component = render_fn
      buffers[i] = buf
  end

  return render(buffers, tabs, options.close_icon)
end

-- Ideally this plugin should generate a beautiful tabline a little similar
-- to what you would get on other editors. The aim is that the default should
-- be so nice it's what anyone using this plugin sticks with. It should ideally
-- work across any well designed colorscheme deriving colors automagically.
local function get_defaults()
  -- TODO add a fallback argument for get_hex
  local comment_fg = colors.get_hex('Comment', 'fg')
  local normal_fg = colors.get_hex('Normal', 'fg')
  local normal_bg = colors.get_hex('Normal', 'bg')
  local string_fg = colors.get_hex('String', 'fg')
  local tabline_sel_bg = colors.get_hex('TabLineSel', 'bg')
  if not tabline_sel_bg == "none" then
    tabline_sel_bg = colors.get_hex('WildMenu', 'bg')
  end

  -- If the colorscheme is bright we shouldn't do as much shading
  -- as this makes light color schemes harder to read
  local is_bright_background = colors.color_is_bright(normal_bg)
  local separator_shading = is_bright_background and -20 or -45
  local tabline_fill_shading = is_bright_background and -15 or -30
  local background_shading = is_bright_background and -12 or -25

  local tabline_fill_color = M.shade_color(normal_bg, tabline_fill_shading)
  local separator_background_color = M.shade_color(normal_bg, separator_shading)
  local background_color = M.shade_color(normal_bg, background_shading)

  return {
    options = {
      view = "default",
      numbers = "none",
      number_style = "superscript",
      mappings = false,
      close_icon = "",
      max_name_length = 15,
      show_buffer_close_icons = true,
      separator_style = 'thin'
    };
    highlights = {
      bufferline_tab = {
        guifg = comment_fg,
        guibg = normal_bg,
      };
      bufferline_tab_selected = {
        guifg = comment_fg,
        guibg = tabline_sel_bg,
      };
      bufferline_tab_close = {
        guifg = comment_fg,
        guibg = background_color
      };
      bufferline_fill = {
        guifg = comment_fg,
        guibg = tabline_fill_color,
      };
      bufferline_background = {
        guifg = comment_fg,
        guibg = background_color,
      };
      bufferline_buffer_inactive = {
        guifg = comment_fg,
        guibg = normal_bg,
      };
      bufferline_modified = {
        guifg = string_fg,
        guibg = background_color,
      };
      bufferline_modified_inactive = {
        guifg = string_fg,
        guibg = normal_bg
      };
      bufferline_modified_selected = {
        guifg = string_fg,
        guibg = normal_bg
      };
      bufferline_separator = {
        guifg = separator_background_color,
        guibg = background_color,
      };
      bufferline_selected_indicator = {
        guifg = tabline_sel_bg,
        guibg = normal_bg,
      };
      bufferline_selected = {
        guifg = normal_fg,
        guibg = normal_bg,
        gui = "bold,italic",
      };
    }
  }
end

function M.go_to_buffer(num)
  local buf_nums = get_buffers_by_mode()
  if num <= table.getn(buf_nums) then
    vim.cmd("buffer "..buf_nums[num])
  end
end

-- TODO then validate user preferences and only set prefs that exists
function M.setup(prefs)
  local preferences = get_defaults()
  -- Combine user preferences with defaults preferring the user's own settings
  -- NOTE this should happen outside any of these inner functions to prevent the
  -- value being set within a closure
  if prefs and type(prefs) == "table" then
    helpers.deep_merge(preferences, prefs)
  end

  function _G.__setup_bufferline_colors()
    local user_colors = preferences.highlights
    colors.set_highlight('BufferLineFill', user_colors.bufferline_fill)
    colors.set_highlight('BufferLineInactive', user_colors.bufferline_buffer_inactive)
    colors.set_highlight('BufferLineBackground', user_colors.bufferline_background)
    colors.set_highlight('BufferLineSelected', user_colors.bufferline_selected)
    colors.set_highlight('BufferLineSelectedIndicator', user_colors.bufferline_selected_indicator)
    colors.set_highlight('BufferLineModified', user_colors.bufferline_modified)
    colors.set_highlight('BufferLineModifiedSelected', user_colors.bufferline_modified_selected)
    colors.set_highlight('BufferLineModifiedInactive', user_colors.bufferline_modified_inactive)
    colors.set_highlight('BufferLineTab', user_colors.bufferline_tab)
    colors.set_highlight('BufferLineSeparator', user_colors.bufferline_separator)
    colors.set_highlight('BufferLineTabSelected', user_colors.bufferline_tab_selected)
    colors.set_highlight('BufferLineTabClose', user_colors.bufferline_tab_close)
  end

  nvim_create_augroups({
      BufferlineColors = {
        {"VimEnter", "*", [[lua __setup_bufferline_colors()]]};
        {"ColorScheme", "*", [[lua __setup_bufferline_colors()]]};
      }
    })

  -- The user's preferences are passed inside of a closure so they are accessible
  -- inside the globally defined lua function which is passed to the tabline setting
  function _G.__bufferline_render()
      return bufferline(preferences.options)
  end

  -- TODO / idea: consider allowing these mappings to open buffers based on their
  -- visual position i.e. <leader>1 maps to the first visible buffer regardless
  -- of it actual ordinal number i.e. position in the full list or it's actual
  -- buffer id
  if preferences.options.mappings then
    for i=1, 10 do
      api.nvim_set_keymap('n', '<leader>'..i, ':lua require"bufferline".go_to_buffer('..i..')<CR>', {
          silent = true, nowait = true, noremap = true
        })
    end
  end

  vim.o.showtabline = 2
  vim.o.tabline = "%!v:lua.__bufferline_render()"
end

return M
