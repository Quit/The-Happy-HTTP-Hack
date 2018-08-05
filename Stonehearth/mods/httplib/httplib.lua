local http = require('http')
local radiant, coroutine = radiant, coroutine
local HTTP_LIB_VERSION = 1

local logger = radiant.log.create_logger('httplib')
if not http then
   logger:error("Cannot find http library; did you use the proper lua-5.1.5.dll?")
   
   return nil
end

-- Make sure that if any other mod is using this library, and it's a newer version, then we'll be silent.
if http.lib_version and http.lib_version >= HTTP_LIB_VERSION then
   return http
end

local HttpPromise = class()

function HttpPromise:__init()
   self._on_success, self._on_failure = {}, {}
end

function HttpPromise:on_success(cb)
   table.insert(self._on_success, cb)
   return self
end

function HttpPromise:on_failure(cb)
   table.insert(self._on_failure, cb)
   return self
end

function HttpPromise:resolve(ctx)
   for k, v in pairs(self._on_success) do
      local ret, err = pcall(v, ctx)
      if not ret then
         logger:error('http success callback for %s failed: %s', tostring(ctx), err)
      end
   end

   self:_cleanup()
end

function HttpPromise:reject(ctx)
   for k, v in pairs(self._on_failure) do
      local ret, err = pcall(v, ctx)
      if not ret then
         logger:error('http failure callback for %s failed: %s', tostring(ctx), err)
      end
   end

   self:_cleanup()
end

function HttpPromise:_get_callback()
   return function(ctx)
      if ctx:get_status() == "success" then
         self:resolve(ctx)
      else
         self:reject(ctx)
      end
   end
end

function HttpPromise:_cleanup()
   self._on_success = nil
   self._on_failure = nil
end

local running = 0

-- Called by the game loop whenever a request is active.
-- To avoid being called all the time, we're unsubscribing when there's no work left.
-- For that purpose, http.update() returns the still-running requests.
-- Although it doesn't hurt from a logic point of view, calling http.update()
-- directly is NOT recommended.
-- (Technically, if you wish to have synchronous requests, you _could_ do
-- something like repeat http.update() until req:is_completed(), which would
-- block the game until the request is done)
local function client_update()
   running = http.update()

   return running > 0
end

-- Background task called by the server to update the threads
-- Same as client_update basically, but as a background task.
local function server_update()
   repeat
      running = http.update()
      coroutine.yield()
   until running == 0
end

function http.add_request()
   -- Manually increment the running requests
   running = running + 1

   if running == 1 then
      if radiant.is_server then
         radiant.create_background_task('update httplib', server_update)
      else
         local tracer = _radiant.client.trace_render_frame()
         
         local last_update, now = 0, 0
         tracer:on_frame_start('update httplib', function()
            -- Don't run the http update on every single frame (as that gets quite expensive real quick)
            -- All 100ms should be more than enough
            now = radiant.get_realtime()
            if now - last_update > 0.1 then
               last_update = now
               if not client_update() then
                  tracer:destroy()
               end
            end
         end)
      end
   end
end
-- function dump(ctx) print(ctx, ctx:get_status_code(), ctx:get_error()) end
-- http.get('http://localhost'):on_success(dump):on_failure(dump)
-- Prepares a HttpRequest object and returns the object and the promise to receive
-- the success/failure events.
-- If the uri is not whitelisted at all, an error is thrown right here and now.
function http.prepare(uri)
   local promise = HttpPromise()
   local req = HttpRequest()
                     :set_url(uri)
                     :set_callback(promise:_get_callback())
   http.add_request()

   return req, promise
end

-- GETs the uri and returns a promise for that request.
-- payload and content type are technically supported parameters,
-- but acceptance on the server side varies.
-- If the URI is not whitelisted, or not whitelisted for GET,
-- an error will be thrown.
function http.get(uri, payload, content_type)
   local req, promise = http.prepare(uri)
   req
      :set_method('GET')
      :execute(payload, content_type)
   return promise
end

-- POSTs to the uri, using data as the post body
-- and content_type as the content type header.
-- This method has effectively two possible arguments:
-- Either with two strings (payload, content_type), or a table.
-- The latter will be taken as a form, which will be serialized in
-- the same manner as the table (i.e. key-value pairs).
-- Use the first one to send JSON to a REST service, use the latter
-- if a normal wwwform is required.
-- If no content is to be submitted, submit an empty string.
-- If the URI is not whitelisted, or not whitelisted for POST,
-- an error will be thrown.
function http.post(uri, payload, content_type)
   local req, promise = http.prepare(uri)
   req:set_method('POST')
        :execute(payload, content_type)
   return promise
end

-- PUTs to the uri, using data as the post body
-- and content_type as the content type header.
-- This method has effectively two possible arguments:
-- Either with two strings (payload, content_type), or a table.
-- The latter will be taken as a form, which will be serialized in
-- the same manner as the table (i.e. key-value pairs).
-- Use the first one to send JSON to a REST service, use the latter
-- if a normal wwwform is required.
-- If no content is to be submitted, submit an empty string.
-- If the URI is not whitelisted, or not whitelisted for PUT,
-- an error will be thrown.
function http.put(uri, payload, content_type)
   local req, promise = http.prepare(uri)
   req:set_method('PUT')
        :execute(payload, content_type)
   return promise
end

-- DELETEs to the uri.
-- payload and content type are technically supported parameters,
-- but acceptance on the server side varies.
-- If the URI is not whitelisted, or not whitelisted for DELETE,
-- an error will be thrown.
function http.delete(uri, payload, content_type)
   local req, promise = http.prepare(uri)
   req:set_method('DELETE')
      :execute(payload, content_type)
   return promise
end

-- HEADs to the uri.
-- payload and content type are technically supported parameters,
-- but acceptance on the server side varies.
-- If the URI is not whitelisted, or not whitelisted for HEAD,
-- an error will be thrown.
function http.head(uri, payload, content_type)
   local req, promise = http.prepare(uri)
   req:set_method('HEAD')
        :execute(payload, content_type)
   return promise
end

-- PATCHes the uri.
-- payload and content type are technically supported parameters,
-- but acceptance on the server side varies.
-- If the URI is not whitelisted, or not whitelisted for PATCH,
-- an error will be thrown.
function http.patch(uri, payload, content_type)
   local req, promise = http.prepare(uri)
   req:set_method('PATCH')
        :execute(payload, content_type)
   return promise
end

http.lib_version = HTTP_LIB_VERSION

return http