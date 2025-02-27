local insert, concat = table.insert, table.concat
local format, lower = string.format, string.lower
local ceil = math.ceil
local _fail = fail -- luacheck: ignore

local request = require("lapis.http").request
local util = require("lapis.util")
local encode_query_string = util.encode_query_string
local to_json = util.to_json
local from_json = util.from_json

-- luarocks install web_sanitize
local whitelist = require("web_sanitize.whitelist"):clone()
local scanner = require("web_sanitize.query.scan_html")
local sanitizer = require("web_sanitize.html").Sanitizer
local raw_text_tags = require("web_sanitize.data").raw_text_tags
local escape_html_text = require("web_sanitize.patterns").escape_html_text

for index = 1, #raw_text_tags do
  raw_text_tags[raw_text_tags[index]] = true
end

-- https://telegra.ph/api#NodeElement
whitelist.tags = {a = {href = whitelist.tags.a.href}, aside = true, b = true, blockquote = true, br = true, code = true, em = true, figcaption = true, figure = true, h3 = true, h4 = true, hr = true, i = true, iframe = {src = whitelist.tags.img.src}, img = {src = whitelist.tags.img.src}, li = true, ol = true, p = true, pre = true, s = true, strong = true, u = true, ul = true, video = {src = whitelist.tags.img.src}}
whitelist.self_closing = {br = true, hr = true, img = true}
whitelist.add_attributes = {}

local API = "https://api.telegra.ph/%s%s"

local function assert_path(method, path, position)
  assert(type(path) == "string", format("bad argument #%i to '%s' (string expected, got %s)", position or 1, method, type(path)))
end

local function assert_params(method, params, position)
  params = params or {}
  assert(type(params) == "table", format("bad argument #%i to '%s' (table expected, got %s)", position or 1, method, type(params)))
end

local function assert_data(method, data, position)
  assert(type(data) == "table", format("bad argument #%i to '%s' (table expected, got %s)", position or 1, method, type(data)))
end

local telegraph = {}
telegraph.__index = telegraph

telegraph.request = request

-- STATIC METHODS

function telegraph.new(access_token)
  local self = setmetatable({}, telegraph)
  self.access_token = access_token
  return self
end

setmetatable(telegraph, {
  __call = function(self, ...)
    return self.new(...)
  end
})

-- METHODS

-- https://telegra.ph/api#createAccount
function telegraph:createAccount(params, no_define_access_token)
  assert_params("createAccount", params)
  local Account = self:Account(assert(self:_request("createAccount", nil, false, params)))
  self.access_token = nil
  if not no_define_access_token then
    self.access_token = Account.access_token 
  end
  return Account
end

-- https://telegra.ph/api#editAccountInfo
function telegraph:editAccountInfo(params)
  assert_params("editAccountInfo", params)
  local Account = self:Account(assert(self:_request("editAccountInfo", nil, true, params)))
  return Account
end

-- https://telegra.ph/api#getAccountInfo
function telegraph:getAccountInfo(params, all_fields)
  assert_params("getAccountInfo", params)
  if all_fields then
    params.fields = {"short_name", "author_name", "author_url", "auth_url", "page_count"}
  end
  local Account = self:Account(assert(self:_request("getAccountInfo", nil, true, params)))
  return Account
end

-- https://telegra.ph/api#revokeAccessToken
function telegraph:revokeAccessToken(params, no_define_access_token)
  assert_params("revokeAccessToken", params)
  local Account = self:Account(assert(self:_request("revokeAccessToken", nil, true, params)))
  self.access_token = nil
  if not no_define_access_token then
    self.access_token = Account.access_token 
  end
  return Account
end

-- https://telegra.ph/api#createPage
function telegraph:createPage(params, return_content)
  assert_params("createPage", params)
  if return_content then
    params.return_content = true
  end
  local Page = self:Page(assert(self:_request("createPage", nil, true, params)))
  return Page
end

-- https://telegra.ph/api#editPage
function telegraph:editPage(path, params, return_content)
  assert_path("editPage", path)
  assert_params("editPage", params, 2)
  if return_content then
    params.return_content = true
  end
  local Page = self:Page(assert(self:_request("editPage", path, true, params)))
  return Page
end

-- https://telegra.ph/api#getPage
function telegraph:getPage(path, params, return_content)
  assert_path("getPage", path)
  assert_params("getPage", params, 2)
  if return_content then
    params.return_content = true
  end
  local Page = self:Page(assert(self:_request("getPage", path, true, params)))
  return Page
end

-- https://telegra.ph/api#getPageList
function telegraph:getPageList(params, get_all)
  assert_params("getPageList", params)
  if get_all then
    local page_count = tonumber(self:getAccountInfo({}, true).page_count)
    if page_count and page_count > 0 then
      local limit = 200
      local total = ceil(limit / page_count)
      local Pages
      for current = 1, total do 
        local offset = (current * limit) - limit
        local PageList = self:PageList(self:getPageList({offset = offset, limit = limit}, false))
        if Pages then
          for page = 1, #PageList.pages do 
            insert(Pages, PageList.pages[page])
          end
        else
          Pages = PageList.pages
        end
      end
      return self:PageList({total_count = page_count, pages = Pages})
    end
  end
  local PageList = self:PageList(assert(self:_request("getPageList", nil, true, params)))
  return PageList
end

-- https://telegra.ph/api#getViews
function telegraph:getViews(path, params)
  assert_path("getViews", path)
  assert_params("getViews", params, 2)
  local PageViews = self:PageViews(assert(self:_request("getViews", path, true, params)))
  return PageViews
end

-- TYPES

-- https://telegra.ph/api#Account
function telegraph:Account(data)
  assert_data("Account", data)
  return setmetatable(data, {type = "Account"})
end

-- https://telegra.ph/api#PageList
function telegraph:PageList(data)
  assert_data("PageList", data)
  for index = 1, #data.pages do
    if self:type(data.pages[index]) ~= "Page" then
      data.pages[index] = self:Page(data.pages[index])
    end
  end
  return setmetatable(data, {type = "PageList"})
end

-- https://telegra.ph/api#Page
function telegraph:Page(data)
  assert_data("Page", data)
  if data.content then
    data.content = self:Node(data.content)
  end
  return setmetatable(data, {type = "Page"})
end

-- https://telegra.ph/api#PageViews
function telegraph:PageViews(data)
  assert_data("PageViews", data)
  return setmetatable(data, {type = "PageViews"})
end

-- https://telegra.ph/api#Node
function telegraph:Node(data)
  assert_data("Node", data)
  for index = 1, #data do
    if type(data[index]) == "table" then
      data[index] = self:NodeElement(data[index])
    end
  end
  return setmetatable(data, {type = "Node", __tostring = function(node) return telegraph:toContent(node) end})
end

-- https://telegra.ph/api#NodeElement
function telegraph:NodeElement(data)
  assert_data("NodeElement", data)
  if data.children then
    data.children = self:Node(data.children)
  end
  return setmetatable(data, {type = "NodeElement"})
end

-- https://telegra.ph/api#Content-format
function telegraph:toNode(content, strip_tags)
  content = sanitizer({whitelist = whitelist, strip_comments = true, strip_tags = strip_tags})(content)
  -- https://github.com/olueiro/lapis_layout/blob/f43a52cfc5cbf631b6d3595d7748a85074b3286f/lapis_layout.lua#L28
  local tree = {}
  scanner.scan_html(content, function(stack)
    local current = tree
    for _, node in pairs(stack) do
      local num = node.num
      if current[num] then
        current = current[num]
      else
        if node.type == "text_node" then
          insert(current, escape_html_text:match(node:inner_text()))
        else
          current[num] = {tag = node.tag, attrs = node.attr}
          current = current[num]
          if raw_text_tags[node.tag] then
            insert(current, node:inner_text())
          end 
        end
      end
    end
  end, {text_nodes = true})
  local function children(node)
    local nodes = {}
    for index = 1, #node do
      local value = node[index]
      if type(value) == "string" then
        local text = {}
        for subindex = index, #node do
          if type(node[subindex]) == "string" then
            insert(text, node[subindex])
            node[subindex] = true
          else
            break
          end
        end
        insert(nodes, concat(text))
      elseif type(value) == "table" then
        local attrs = value.attrs
        local params = {}
        if attrs then
          for _, key in ipairs(attrs) do
            params[key] = attrs[key]
          end
        end
        insert(nodes, {tag = lower(value.tag), attrs = params, children = children(value)})
      end
    end
    return #nodes == 0 and nil or nodes
  end
  return self:Node(children(tree) or {})
end

-- https://telegra.ph/api#Content-format
function telegraph:toContent(Node)
  local function node(Node)
    local content = {}
    if self:type(Node) == "Node" then
      for index = 1, #Node do
        local NodeElement = Node[index]
        if type(NodeElement) == "string" then
          insert(content, NodeElement)
        elseif self:type(NodeElement) == "NodeElement" then
          local tag = NodeElement.tag
          local attrs = NodeElement.attrs
          local params = {}
          if attrs then
            for key, value in pairs(attrs) do
              insert(params, format(" %s=%q", key, value))
            end
          end
          local children = NodeElement.children and node(NodeElement.children)
          insert(content, format("<%s%s>%s</%s>", tag, concat(params), children or "", tag))
        end
      end
    end
    return concat(content)
  end
  return sanitizer({whitelist = whitelist, strip_comments = true})(node(Node))
end

function telegraph:type(object)
  if type(object) ~= "table" then
    return false
  end
  local mt = getmetatable(object)
  if not mt then
    return false
  end
  return mt.type or false
end

function telegraph:_request(method, path, access_token_required, params)
  params = params or {}
  if access_token_required then
    if not self.access_token then
      return _fail, "access token not found"
    end
    params.access_token = self.access_token
  end
  for key, value in pairs(params) do
    if type(value) == "table" then
      local ok, json = pcall(to_json, value)
      if not ok then
        return _fail, "unable to convert to json"
      end
      params[key] = json
    end
  end
  local url = format(API, method, path and "/" .. path or "")
  local response, status = telegraph.request(url, encode_query_string(params))
  if not response then
    return _fail, tostring(status)
  end
  local ok, json = pcall(from_json, response)
  if not ok then
    return _fail, "response is not a json"
  end
  if not json.ok then
    return _fail, tostring(json.error)
  end
  return json.result
end
  
return telegraph
