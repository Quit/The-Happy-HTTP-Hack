local Commands = class()
local http = require 'httplib'

local logger = radiant.log.create_logger('httplib.callbacks')

-- Avoid hitting the CDN _too hard_
local avatar_cache = {}
local latestCache = nil

local Cache = class()

-- Initialize a cache at `url`, optionally serving the response as base64 if requested
function Cache:__init(url, base64)
   self.__resolvers = {}
   self.__resolved = nil
   
   if not http then
      self.__resolved = { success = false, response = 'http library not found' }
      return
   end
   
   http.get(url)
      :on_success(function(ctx)
         if ctx:get_status_code() == 200 then
            self:__resolve(base64 and ctx:get_response_base64() or ctx:get_response())
         else
            self:__reject(ctx)
         end
      end)
      :on_failure(function(ctx) self:__reject(ctx) end)
end

function Cache:add_resolver(response)
   if self.__resolved then
      if self.__resolved.success then
         response:resolve(self.__resolved.response)
      else
         response:reject(self.__resolved.response)
      end
   else
      table.insert(self.__resolvers, response)
   end
end

function Cache:__resolve(response)
   self.__resolved = { success = true, response = response }
   for k, v in pairs(self.__resolvers) do
      v:resolve(response)
   end
   
   self.__resolvers = nil
end

function Cache:__reject(ctx)
   local response = 'An error occured: ' .. tostring(ctx:get_status_code()) .. '; ' .. tostring(ctx:get_error())
   logger:error('an error occured with %s: %s', tostring(ctx), response)
   self.__resolved = { success = false, response = response }
   for k, v in pairs(self.__resolvers) do
      v:reject(response)
   end
   
   self.__resolvers = nil
end

-- Returns the latest.json
function Commands:get_latest(session, response)
   if not latestCache then
      latestCache = Cache('https://discourse.stonehearth.net/latest.json?order=activity')
   end
   
   latestCache:add_resolver(response)
   return
end

-- Returns an avatar from a location, returns it as base64 so we can nicely embed it in JS
function Commands:get_avatar(session, response, path)
   local relative = path:find('/user_avatar/discourse.stonehearth.net/') == 1
   if not relative and path:find('https://avatars.discourse.org/') ~= 1 then
      response:reject('invalid path')
      return
   end

   local cache = avatar_cache[path]
   if not cache then
      cache = Cache(relative and 'https://discourse.stonehearth.net' .. path or path, true)
      avatar_cache[path] = cache
   end
   
   cache:add_resolver(response)
end

return Commands
