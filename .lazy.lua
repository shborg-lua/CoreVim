-- require("telescope").extensions.egrepify.picker()
local Util = require("corevim.util")
local uv = vim.uv
local dir_lists_path = "~/.local/share/repodb/includes"
local dir_lists = {}
dir_lists.languages = vim.fs.joinpath(dir_lists_path, "languages")
dir_lists.topics = vim.fs.joinpath(dir_lists_path, "topics")

---@alias ulf.local.ui.picker_spec_handler fun(opts:ulf.local.ui.PickerSpec):ulf.local.ui.PickerSpec

---@class ulf.local.ui.PickerSpec
---@field picker_opts table|ulf.local.ui.picker_spec_handler: Picker options are passed to the resolved picker
---@field name string: The object path to the picker
---@field prefix string: Mapping prefix
---@field desc string: Mapping description
---@field next? ulf.local.ui.PickerSpec
---@field label string? String used for labels
---@field value any? Value of a picker

---FIXME: make available
---
---@class LazyKeysBase
---@field desc? string
---@field noremap? boolean
---@field remap? boolean
---@field expr? boolean
---@field nowait? boolean
---@field ft? string|string[]

---@class LazyKeysSpec: LazyKeysBase
---@field [1] string lhs
---@field [2]? string|fun()|false rhs
---@field mode? string|string[]

---@class LazyKeys: LazyKeysBase
---@field lhs string lhs
---@field rhs? string|fun() rhs
---@field mode? string
---@field id string
---@field name string

---@class ulf.local.ui.filedata_map
---@field languages string[]
local filedata = setmetatable({}, {
  ---comment
  ---@param t table
  ---@param k {[1]:string,[2]:string}
  ---@return string[]
  __index = function(t, k)
    local list_kind = k[1]
    local list_item = k[2]
    local path = vim.fs.normalize(vim.fs.joinpath(dir_lists[list_kind], list_item))
    local v = Util.fs.read_file(path)
    if type(v) == "string" then
      ---@type table
      local lines = {}
      lines = vim.split(v, "\n", { plain = true })
      rawset(t, k, lines)
      return lines
    end
  end,
})
--- tests if directory exists
---@param path string path to directory
---@return boolean?
local function dir_exists(path)
  local stat = uv.fs_stat(path)

  if not stat then
    return false
  end
  if type(stat) == "table" then
    return stat.type == "directory"
  end
end

---@class ulf.local.ui.filelist_map
---@field languages string[]
local filelists = setmetatable({}, {
  __index = function(t, k)
    local path = vim.fs.normalize(vim.fs.joinpath(dir_lists[k]))
    if not dir_exists(path) then
      return
    end
    ---@type string[]
    local lines = {}
    local dir = uv.fs_scandir(path)

    while true do
      local name = uv.fs_scandir_next(dir)
      if not name then
        break
      end
      lines[#lines + 1] = name
    end
    rawset(t, k, lines)
    return lines
  end,
})

---@alias ulf.local.ui.picker_func fun(map_conf:ulf.local.ui.PickerSpec):fun(opts:table)|table

---@class ulf.local.ui.handler
---@field picker  ulf.local.ui.picker_func
---@field merge_opts  fun(map_conf:ulf.local.ui.PickerSpec):ulf.local.ui.PickerSpec

---@class ulf.local.ui.handler_type_map : {[string]:ulf.local.ui.handler}
local handler = {
  select_topics = {}, ---@diagnostic disable-line: missing-fields
  select_language_picker = {}, ---@diagnostic disable-line: missing-fields
  telescope = {}, ---@diagnostic disable-line: missing-fields
}

---comment
---@param id string
---@return ulf.local.ui.picker_func
local function make_select_picker(id)
  return function(map_conf)
    local label = map_conf.label
    ---@type string[]
    local data = filelists[id]
    return function(opts)
      vim.ui.select(data, {
        prompt = label,
        format_item = function(item)
          return "I'd like to choose " .. item
        end,
      }, function(choice)
        vim.print({
          "coice",
          choice,
          map_conf.next,
        })

        ---TODO: generalize
        -- local path_filelist = vim.fs.joinpath(dir_lists.languages, choice)
        -- if assert(uv.stat(path_filelist)) then
        --   local data = Util.fs.read_file(path_filelist)
        -- end
        local data = filedata[{ id, choice }]

        map_conf.next.picker_opts.search_dirs = data
        local picker = handler.telescope.picker(map_conf.next)
        if type(picker) == "function" then
          picker(map_conf.next.picker_opts)
        end
      end)
    end
  end
end

handler.select_topics.picker = make_select_picker("topics")
function handler.select_topics.merge_opts(map_conf)
  return map_conf
end

handler.select_language_picker.picker = function(map_conf)
  local label = map_conf.label
  local data = filelists.languages
  return function(opts)
    vim.ui.select(data, {
      prompt = label,
      format_item = function(item)
        return "I'd like to choose " .. item
      end,
    }, function(choice)
      vim.print({
        "coice",
        choice,
        map_conf.next,
      })

      ---TODO: generalize
      -- local path_filelist = vim.fs.joinpath(dir_lists.languages, choice)
      -- if assert(uv.stat(path_filelist)) then
      --   local data = Util.fs.read_file(path_filelist)
      -- end
      local data = filedata[{ "languages", choice }]

      map_conf.next.picker_opts.search_dirs = data
      local picker = handler.telescope.picker(map_conf.next)
      if type(picker) == "function" then
        picker(map_conf.next.picker_opts)
      end
    end)
  end
end

function handler.select_language_picker.merge_opts(map_conf)
  return map_conf
end

function handler.telescope.picker(map_conf)
  local api_path = vim.split(map_conf.name, ".", {
    plain = true,
  })
  ---@type string
  local picker_name
  ---@type table
  local mod
  if #api_path == 3 then
    ---@type table
    -- mod = require("telescope").extensions[api_path[2]][api_path[3]]
    mod = require("telescope").extensions[api_path[2]][api_path[3]]
    map_conf.label = api_path[3]
  elseif #api_path == 2 then
    ---@type table
    mod = require("telescope").extensions[api_path[1]][api_path[2]]
    map_conf.label = api_path[2]
  end
  return mod
end

function handler.telescope.merge_opts(map_conf)
  if map_conf.picker_opts.cwd then
    map_conf.picker_opts.prompt_title = string.format("%s: %s", map_conf.label, map_conf.picker_opts.cwd)
  end
  return map_conf
end

---@class ulf.local.ui.PickerSpecList : ulf.local.ui.PickerSpec[][]
local slots = {
  [1] = {
    picker_opts = { cwd = vim.fs.normalize("~/dev/projects/ulf") },
    handler = "telescope",
    name = "extensions.egrepify.egrepify",
    prefix = "<leader>",
    desc = "Find in ULF root",
  },

  [2] = {
    picker_opts = {},
    handler = "select_language_picker",
    name = "extensions.egrepify.egrepify",
    prefix = "<leader>",
    desc = "Egrepify in Repo Languages",
    next = {
      picker_opts = {},
      handler = "telescope",
      name = "extensions.egrepify.egrepify",
      prefix = "<leader>",
      desc = "Find in ULF root",
    },
  },
  [3] = {
    picker_opts = {},
    handler = "select_topics",
    name = "extensions.egrepify.egrepify",
    prefix = "<leader>",
    desc = "Egrepify in Repo Topics",
    next = {
      picker_opts = {},
      handler = "telescope",
      name = "extensions.egrepify.egrepify",
      prefix = "<leader>",
      desc = "Find in ULF root",
    },
  },
}

local function keys(_, opts)
  ---@type table<string,LazyKeys>
  local mappings = {}

  local prefix = "<leader>"
  for id, map_conf in ipairs(slots) do
    mappings[#mappings + 1] = { ---@diagnostic disable-line: no-unknown
      prefix .. tostring(id),
      function()
        -- if map_conf.handler == "telescope" then
        --   local picker = handler.telescope.picker(map_conf)
        --   ---@type table
        --   local o = handler.telescope.merge_opts(map_conf).picker_opts
        --   return picker(o)
        -- elseif map_conf.handler == "select_language_picker" then
        --   map_conf.label = "Select Language"
        --   local picker = handler.select_language_picker.picker(map_conf)
        --   ---@type table
        --   local o = handler.select_language_picker.merge_opts(map_conf).picker_opts
        --   return picker(o)
        -- end
        local picker = handler[map_conf.handler].picker(map_conf)
        ---@type table
        local o = handler[map_conf.handler].merge_opts(map_conf).picker_opts
        return picker(o)
      end,
      desc = map_conf.desc,
    }
  end
  return vim.list_extend(opts, mappings)
end
return {

  -- change some telescope options and a keymap to browse plugin files
  {
    "nvim-telescope/telescope.nvim",
    keys = keys,
  },
}
