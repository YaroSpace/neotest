local async = require("plenary.async")
local config = require("neotest.config")
local hi = config.highlights
local lib = require("neotest.lib")

---@class SummaryComponent
---@field client NeotestClient
---@field expanded_positions table
---@field child_components table<number, SummaryComponent>
---@field adapter_id integer
local SummaryComponent = {}

function SummaryComponent:new(client, adapter_id)
  local elem = {
    client = client,
    expanded_positions = {},
    adapter_id = adapter_id,
  }
  setmetatable(elem, self)
  self.__index = self
  return elem
end

function SummaryComponent:toggle_reference(pos_id)
  self.expanded_positions[pos_id] = not self.expanded_positions[pos_id]
end

local async_func = function(f)
  return function()
    async.run(f)
  end
end

---@param render_state RenderState
---@param tree Tree
function SummaryComponent:render(render_state, tree, expanded, indent)
  indent = indent or ""
  local root_pos = tree:data()
  local children = tree:children()
  for index, node in pairs(children) do
    local is_last_child = index == #children
    local position = node:data()

    if expanded[position.id] then
      self.expanded_positions[position.id] = true
    end

    local node_indent = indent .. (is_last_child and "╰─" or "├─")
    local chid_indent = indent .. (is_last_child and "  " or "│ ")
    if #node_indent > 0 then
      render_state:write(node_indent, { group = hi.indent })
    end

    if position.type ~= "test" then
      render_state:add_mapping(
        "expand",
        async_func(function()
          self:toggle_reference(position.id)
          require("neotest").summary.render()
        end)
      )

      render_state:add_mapping(
        "expand_all",
        async_func(function()
          local positions = {}
          local root_type = position.type
          --  Don't want to load all files under dir to prevent memory issues
          if root_type == "dir" then
            for _, pos in node:iter() do
              if pos.type == "dir" then
                positions[pos.id] = true
              end
            end
          else
            for _, pos in self.client:get_position(position.id, { adapter = self.adapter_id }):iter() do
              positions[pos.id] = true
            end
          end
          require("neotest").summary.render(positions)
        end)
      )
    end
    if position.type ~= "dir" then
      render_state:add_mapping("jumpto", function()
        local buf = vim.fn.bufadd(position.path)
        vim.fn.bufload(buf)
        if position.type == "file" then
          lib.ui.open_buf(buf)
        else
          lib.ui.open_buf(buf, position.range[1], position.range[2])
        end
      end)
    end
    render_state:add_mapping(
      "attach",
      async_func(function()
        require("neotest").attach(position.id)
      end)
    )
    render_state:add_mapping(
      "output",
      async_func(function()
        require("neotest").output.open({ position_id = position.id })
      end)
    )

    render_state:add_mapping(
      "short",
      async_func(function()
        require("neotest").output.open({ position_id = position.id, short = true })
      end)
    )

    render_state:add_mapping("stop", function()
      require("neotest").stop(position.id)
    end)

    render_state:add_mapping("run", function()
      require("neotest").run(position.id)
    end)

    local prefix = config.icons[self.expanded_positions[position.id] and "expanded" or "collapsed"]
    render_state:write(prefix, { group = config.highlights.expand_marker })

    local icon, icon_group = self:_position_icon(position)
    render_state:write(" " .. icon .. " ", { group = icon_group })

    render_state:write(position.name .. "\n", { group = config.highlights[position.type] })

    if self.expanded_positions[position.id] then
      self:render(render_state, node, expanded, chid_indent)
    end
  end
  if #children == 0 and root_pos.type ~= "test" then
    if #indent > 0 then
      render_state:write(indent .. "  ", { group = hi.indent })
    end
    render_state:write("  No tests found\n", { group = hi.expand_marker })
  end
end

function SummaryComponent:_position_icon(position)
  local result = self.client:get_results(self.adapter_id)[position.id]
  if not result then
    if self.client:is_running(position.id, { adapter = self.adapter_id }) then
      return config.icons.running, config.highlights.running
    end
    return config.icons.unknown, "Normal"
  end
  return config.icons[result.status], config.highlights[result.status]
end

---@return SummaryComponent
return function(client, adapter_id)
  return SummaryComponent:new(client, adapter_id)
end
