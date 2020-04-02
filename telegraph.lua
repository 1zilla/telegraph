local format, lower, gsub = string.format, string.lower, string.gsub
local insert, concat = table.insert, table.concat
local ceil = math.ceil
local _fail = fail -- luacheck: ignore

local request = require("lapis.http").request
local util = require("lapis.util")
local encode_query_string = util.encode_query_string
local to_json = util.to_json
local from_json = util.from_json

-- luarocks install web_sanitize
--local whitelist = require("web_sanitize.whitelist"):clone()
local scanner = require("web_sanitize.query.scan_html")
local sanitizer = require("web_sanitize.html").Sanitizer({strip_comments = true})

local telegraph = {}
telegraph.__index = telegraph

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

-- https://telegra.ph/api#NodeElement
local allowed_tags = {a = true, aside = true, b = true, blockquote = true, br = false, code = true, em = true, figcaption = true, figure = true, h3 = true, h4 = true, hr = false, i = true, iframe = true, img = false, li = true, ol = true, p = true, pre = true, s = true, strong = true, u = true, ul = true, video = true}

setmetatable(telegraph, {
  __call = function(self, ...)
    return self.new(...)
  end
})

function telegraph.new()
  local self = setmetatable({}, telegraph)
  return self
end

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
    local page_count = self:getAccountInfo({}, true).page_count
    if page_count > 0 then
      local limit = 200
      local total = ceil(limit / tonumber(page_count))
      local Pages
      for current = 1, total do 
        local offset = (current * limit) - limit
        local PageList = self:PageList(assert(self:getPageList({offset = offset, limit = limit})))
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
    if not getmetatable(data.pages[index]) then
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
  return setmetatable(data, {type = "Node"})
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
function telegraph:toNode(content)
  
  content = sanitizer(content)
  
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
          insert(current, node:inner_text())
        else
          current[num] = {
            tag = node.tag,
            attr = node.attr
          }
          current = current[num]
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
        local tag = lower(value.tag)
        if allowed_tags[tag] ~= nil then
          local attrs
          if value.attr then
            -- https://telegra.ph/api#NodeElement
            attrs = {href = value.attr.href, src = value.attr.src}
          end
          insert(nodes, {tag = tag, attrs = attrs, children = children(value)})
        end
      end
    end
    return #nodes == 0 and nil or nodes
  end
  
  return self:Node(children(tree) or {})
end

-- https://telegra.ph/api#Content-format
function telegraph:toContent(Node)
  
  local function node(node_element)
    local content = {}
    for index = 1, #node_element do
      local element = node_element[index]
      if type(element) == "string" then
        insert(content, element)
      elseif type(element) == "table" then
        local tag = element.tag
        local href = ""
        local src = ""
        if element.attrs then
          if element.attrs.href then
            href = format(" href=%q", element.attrs.href)
          end
          if element.attrs.src then
            src = format(" src=%q", element.attrs.src)
          end
        end
        if allowed_tags[tag] == true then
          local children = ""
          if element.children then
            children = node(element.children)
          end
          insert(content, format("<%s%s%s>%s</%s>", tag, href, src, children, tag))
        elseif allowed_tags[tag] == false then
          insert(content, format("<%s%s%s />", tag, href, src))
        end
      end
    end
    return concat(content)
  end

  return node(Node)

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
  local response, status = request(url, encode_query_string(params))
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