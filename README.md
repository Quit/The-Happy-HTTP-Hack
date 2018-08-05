# **DISCLAIMER**
In order for this "mod" to work, it needs to ship around a few security options that lua and Stonehearth out of the box provide. **USE AT YOUR OWN RISK**. The binaries have been created with the best of my intentions  and although I am somewhat certain that they do not contain any gaping security issues, the code has not been reviewed. Therefore, httplib, its associated mods and dlls come without any warranty, to the extent permitted by applicable law.

# General Stuff and Architecture

This "mod" allows you to create HTTP(S) connections to the outside world. Whether you want to integrate some chat functionality, statistics, sharing of information, or some player-owned economy hosted in the cloud - you're pretty much free to do whatever.

Supported are HTTP calls (with or without SSL) using all HTTP verbs (except TRACE). You can define your own payload (e.g. JSON) using an own content type, or use url-encoded forms (by supplying a table - the library handles the whole encoding bits). The response can either be read as a string (which can be binary, but parsing it in lua might not be nice) or as base 64 encoded representation (e.g. for media). The example mod utilises both.

## Installation

1. Make a backup of the two soon-to-be-overwritten dlls in your game directory: `lua-5.1.5.dll` and `x64\lua-5.1.5.dll`.
2. Copy the two dlls (lua-5.1.5.dll and x64/lua-5.1.5.dll) from this zip into your Stonehearth folder and overwrite the two existing lua dlls. 
3. If you want to see the example Discourse mod in action, copy over the mods/ folder.

## Deinstallation
Restore the original lua-5.1.5.dlls (either from your backup, by validating the game cache using Steam, or by re-extracting them from your Humble Bundle download).

# httplib

Welcome to the beautiful world of absolutely horrible hacks and Top 10 Things You Should Never Do (You Won't Believe Number Four!). Today, we are intentionally un-sandboxing something (with the intention to keep it somewhat boxed still, though) in order to communicate with the outside. Is this an AI Box experiment? Not yet!

**This is a proof of concept more than anything else.**

The httplib mod consists of three major parts:

- The **patched lua-5.1.5.dll**, which adds HTTP functionality to lua
- The **http_whitelist.json**, which defines what HTTP requests are allowed. This is a user-setting intended as some very, very rough security feature.
- The **httplib mod**, which makes use of the binary extensions to provide easy-to-use methods and interfaces to play around with.


## lua-5.1.5.dll

The lua-5.1.5.dll is the library that hosts the lua, and therefore all the scripting goodiness. To provide a safe experience, especially with multiplayer, Stonehearth's lua has been slightly stripped down. Notably, the io and debug libraries are (mostly) missing.

This "mod" changes that. By replacing the lua-5.1.5.dlls with another version with HTTP functionality, we're teaching lua HTTP. This allows us to make calls to external REST services. To prevent your game just going about everywhere, calls must be explicitly whitelisted.

## http_whitelist.json

In your game directory, there may be a `http_whitelist.json`. This is a JSON file with the following structure:

```json
{
   "allow": [
      "https://some-endpoint/",
      {
         "hostname": "discourse.stonehearth.net",
         "schemes": [ "https" ],
         "methods": [ "GET" ],
         "paths": [ "/latest.json", "/user_avatar/" ],
         "ports": [ 443 ]
      }
   ]
}
```

The whitelist knows two different kind of entries: Simple, and complex ones. In any case, the whitelist operates on URLs, which have the following format: `[scheme]://[hostname]:[port]/[path]`. The port is optional and may be omitted (resulting in `[scheme]://[hostname]/[path]`). If it isn't specified, it's implied 80 for HTTP and 443 for HTTPS. Scheme and hostname are case insensitive, whereas the path is always case sensitive.

The parsing is done using an proprietary JSON library ([JSON for Modern C++](https://github.com/nlohmann/json)) and is therefore not comparable with Stonehearth's normal JSON parsing. It is not affected by overrides or mixintos and must reside in the game root directory.

### Simple whitelist rules
Simple rules are just strings that define which endpoints may be called with all methods. The string is parsed as an URL, and requests will be whitelisted by the rule if and only if:

- The scheme matches (case insensitive)
- The hostname matches (case insensitive)
- The port matches
- The request path starts with the whitelist path (e.g. the request `/api/values` matches the whitelist `/api/`) **(case sensitive!)**

### Complex whitelist rules
Complex rules allow more granular control over what should be allowed and what shouldn't. Complex rules are objects that can have the following properties:

- **hostname**: Required. The hostname/domain that the rule should be applied to.
- **schemes**: Optional. Array of strings of schemes that should be allowed. Possible values are `http` and `https`.
- **methods:** Optional. Array of strings of HTTP verbs that should be allowed. Possible values are `GET`, `POST`, `PUT`, `DELETE`, `HEAD`,`OPTIONS`.
- **ports**: Optional. Array of integers (numbers) of ports that should be allowed.
- **paths**: Optional. Array of strings of (super-)paths that should be allowed.

For a complex rule to match, the request

1. Must have the same hostname
2. For each property that is set on the rule, at least one item must match the request's one.

As an example, let's take a look at the Discourse rules:

```json
    {
      "hostname": "discourse.stonehearth.net",
      "schemes": [ "https" ],
      "methods": [ "GET" ],
      "paths": [ "/latest.json", "/user_avatar/" ],
      "ports": [ 443 ]
    },
    {
      "hostname": "avatars.discourse.org",
      "schemes": [ "https" ],
      "methods": [ "GET" ]
    },
```

These two rules allow the following requests:

- GET on requests that start with `https://discourse.stonehearth.net/latest.json` and `https://discourse.stonehearth.net/user_avatar/` on port 443
- GET on requests on `https://avatars.discourse.org`, on any path and any port.

## httplib.lua
Using the raw API as provided by the DLL has a few disadvantages:

- The API is sleek and functional, but not very comfortable.
- There's no real error handling for callback methods provided.
- By its nature, the API requires frequent polling to execute requests. This is not super easy to do.

To deal with these, a httplib.lua is provided. It's a wrapper around the C API, which also deals with ways of polling the requests to make all the magic happen.

Usage of this lua file is completely optional, but if a mod requires on it, it should ship its own version of it (and require() it accordingly). The file itself does some version checks, so multiple mods can use the same file, and only the newest API will be used. This means that newer mods could patch "older" mods just by including the file. In theory.

Requiring the file either returns a http library table, or `nil` if the http module was not found (and therefore, the lua dll wasn't patched).

## API

The following methods are part of the C API. To use them, use `local http = require('http')`. If you are using the httplib.lua, this is implicitly done for you.

### http
A table that contains both members defined in C, as well as those defined in httplib. To use the `[httplib]` ones, make sure you have a copy of httplib.lua and use `require('httplib')` instead if `require('http')`.

#### http.update() [C]

- **No arguments.**
- Method used to tell curl to update the requests. This needs to be called frequently when performing requests, otherwise the requests will timeout/never be called. 
- If you are using httplib.lua, this is done implicitly for you when calling `http.add_request(request)`.
- **Returns** the number of still-running requests. If the function returns 0, no requests are running at the moment and further calls to `http.update()` will not do anything unless another request is started.

#### http.get_version() [C]

- **No arguments.**
- **Returns** the version of the C library. As of now, it should be 1.0.0.

#### http.is_request_allowed(string uri, string method = nil) [C]

- **Two arguments:**
  - **string uri**: The first is the URI to query.
  - **string method**: The method to use, or nil. If no method is specified, the check merely checks if ANY kind of operation is allowed. You can use this to check if a call is allowed to go through the whitelist (and e.g. inform the user about updating the whitelist).
- **Returns** a boolean. True if the request is allowed, false otherwise.

#### http.add_request() [httplib]

- **No arguments.**
- If called, assumes that at least one more request was started and therefore, the polling logic should be enabled (if it isn't running already).
- This is implicitly called by `http.prepare` and all other http-methods that immediately start a request (`http.head`, `http.get`, `http.post`, `http.put`, `http.delete`).
- **Returns** nothing.

#### http.prepare(string uri) [httplib]
- **One argument:**
  - **string uri**: The URI to prepare a request for (for convenience reasons).
- Implicitly calls `http.add_request` to enable the polling mechanics.
- **Returns two values:**
  - **HttpRequest request:** The created HttpRequest object. Use it to modify the request.
  - **HttpPromise promise:** A promise that will be resolved/rejected by httplib once the request completes (or fails).

#### http.get(string uri, string/table payload, string content_type) [httplib]
- **One, two or three arguments:**
  - **string uri:** Required. The URI to execute the request against.
  - **table/string payload:** Optional. The payload. If it's a string, it will be posted straight into the request body. If it's a table, it's expected to be a flat key-value mapping that will be posted as a url encoded wwwform.
  - **string content_type:** Optional. Only usable if the payload is a string. Specifies the Content-Type of the payload. If not specified, 'text/plain' will be used.
- Performs a GET request.
- **Returns:** The HttpPromise for this request.

#### http.post(string uri, string/table payload, string content_type) [httplib]
- **One, two or three arguments:**
  - **string uri:** Required. The URI to execute the request against.
  - **table/string payload:** Optional. The payload. If it's a string, it will be posted straight into the request body. If it's a table, it's expected to be a flat key-value mapping that will be posted as a url encoded wwwform.
  - **string content_type:** Optional. Only usable if the payload is a string. Specifies the Content-Type of the payload. If not specified, 'text/plain' will be used.
- Performs a POST request.
- **Returns:** The HttpPromise for this request.

#### http.delete(string uri, string/table payload, string content_type) [httplib]
- **One, two or three arguments:**
  - **string uri:** Required. The URI to execute the request against.
  - **table/string payload:** Optional. The payload. If it's a string, it will be posted straight into the request body. If it's a table, it's expected to be a flat key-value mapping that will be posted as a url encoded wwwform.
  - **string content_type:** Optional. Only usable if the payload is a string. Specifies the Content-Type of the payload. If not specified, 'text/plain' will be used.
- Performs a DELETE request.
- **Returns:** The HttpPromise for this request.

#### http.put(string uri, string/table payload, string content_type) [httplib]
- **One, two or three arguments:**
  - **string uri:** Required. The URI to execute the request against.
  - **table/string payload:** Optional. The payload. If it's a string, it will be posted straight into the request body. If it's a table, it's expected to be a flat key-value mapping that will be posted as a url encoded wwwform.
  - **string content_type:** Optional. Only usable if the payload is a string. Specifies the Content-Type of the payload. If not specified, 'text/plain' will be used.
- Performs a PUT request.
- **Returns:** The HttpPromise for this request.

#### http.head(string uri, string/table payload, string content_type) [httplib]
- **One, two or three arguments:**
  - **string uri:** Required. The URI to execute the request against.
  - **table/string payload:** Optional. The payload. If it's a string, it will be posted straight into the request body. If it's a table, it's expected to be a flat key-value mapping that will be posted as a url encoded wwwform.
  - **string content_type:** Optional. Only usable if the payload is a string. Specifies the Content-Type of the payload. If not specified, 'text/plain' will be used.
- Performs a HEAD request.
- **Returns:** The HttpPromise for this request.

#### http.patch(string uri, string/table payload, string content_type) [httplib]
- **One, two or three arguments:**
  - **string uri:** Required. The URI to execute the request against.
  - **table/string payload:** Optional. The payload. If it's a string, it will be posted straight into the request body. If it's a table, it's expected to be a flat key-value mapping that will be posted as a url encoded wwwform.
  - **string content_type:** Optional. Only usable if the payload is a string. Specifies the Content-Type of the payload. If not specified, 'text/plain' will be used.
- Performs a PATCH request.
- **Returns:** The HttpPromise for this request.

### HttpPromise

A stupidly simple promise implementation with some error logging in case things go south.

#### HttpPromise:on_success(function callback) [httplib]

- **One argument**: Function to call in case the request was successfully executed. The signature of the callback is `void callback(HttpRequest request)`.
- Adds this function to the callees in case the request succeeds. Note that "success" is defined as "valid HTTP request". If a valid answer was received, this function will be called - including if the server replied with a code like 4xx or 5xx.
- The passed parameter to the callback is the request, and can be used to read the response of the request.
- **Returns** the same promise for chaining.

#### HttpPromise:on_failure(function callback) [httplib]
- **One argument:** Function to call in case the request encountered an error. The signature of the callback is `void callback(HTtpRequest request)`.
- Adds this function to the callees in case the request fails. Failure is defined as any transport error (such as connection refused, invalid responses, and so forth). Note that whitelist errors occur during `HttpRequest:execute()` and do therefore not trigger this callback.
- **Returns** the same promise for chaining.

### HttpRequest
If you feel the need to go bare bones, you can create and modify the request yourself. Note that some methods must be called before the request is sent, and some can only be called after the request has completed.

All setter methods return the same HttpRequest object, so they can be chained, e.g. like this:

```lua
local req = HttpRequest()
	:set_url('http://localhost')
	:set_method('GET')
	:set_request_header('Authentication', 'Bearer XYZ')
	:execute()
```

#### HttpRequest()
Constructor. Creates a new HttpRequest object. Takes no parameters.

#### HttpRequest:get_url()
Getter. Returns the previously set url, or `nil` if none was set yet.

#### HttpRequest:set_url(string url)
Setter. Sets the url. This performs a whitelist check if _any_ method is allowed on the host. If it isn't, an error is thrown. Can only be called before the request is `execute`d.

#### HttpRequest:get_method()
Getter. Returns the method of the request. Defaults to GET.

#### HttpRequest:set_method(string method)
Setter. Sets the method of the request. Must be a valid option (GET, POST, PUT, DELETE, HEAD, OPTIONS, PATCH), otherwise an error is thrown. Can only be called before the request is `execute`d.

#### HttpRequest:get_status()
Getter. Returns a string with the current status of the request (e.g. "in progress"). Can be used for logging.

#### HttpRequest:get_response()
Getter. Returns a string representing the payload received from the server. Can only be called after the request has been completed. If there was a failure, or the server sent an empty response, it is `nil`.

#### HttpRequest:get_response_base64()
Getter. Returns a base64 representation of the payload received from the server. Can only be called after the request has been completed. If there was a failure, or the server sent an empty response, it is an empty string.

#### HttpRequest:get_status_code()
Getter. Returns the status code received from the server. It is only set after the request is completed successfully, otherwise it is 0.

#### HttpRequest:get_response_header(string name)
Getter. Returns the value of the header `name` of the response, or nil if the header was not present in the response. Can be called during the request, but may be incomplete depending on the status.

#### HttpRequest:get_response_headers(string name)
Getter. Returns all headers of the response, as a table, where the header names are the keys in lower case. Can be called during the request, but may be incomplete depending on the status.

#### HttpRequest:set_request_header(string name, string value)
Setter. Sets a request header `name` with the value `value`. `value` may not contain characters that are not allowed in headers (such as colons and newlines). Can only be called before the request is `:execute()`d.

#### HttpRequest:set_callback(function cb)
Setter. Sets the function to call once the request is complete, either successful or unsuccessful. Effectively `pcall`s the callback, if an error occurs, it is silently discarded. 

Only one callback may be specified per request. If this function is called multiple times, the last set callback is used. Can only be called before the request is completed.

#### HttpRequest:is_running()
Getter. Returns whether the request was started or not. Completed requests also count as "running".

#### HttpRequest:is_completed()
Getter. Returns whether the request has completed or not.

#### HttpRequest:get_error()
Getter. Returns the error as a string, if any occured. Otherwise, returns `nil`.

#### HttpRequest:get_error_code()
Getter. Returns the CURL error code, which might be set during completition. Defaults to 0, which is "OK".

#### HttpRequest:execute(string/table payload = nil, string content_type = nil)
Command (but for all intents and purposes 'setter', because it sets something and returns itself).

Attempts to initiate the request. If any configuration is conflicting (e.g. no url set), throws an error. If the url/method combination isn't whitelisted, throws an error.

If the validation succeeds, the request is initiated and will now be `:running()`. Frequent calls to `http.update()` (the message pump) are required to send or poll data.

This method allows three variants of arguments:

- **No arguments.** No payload will be sent. Recommended for GET, HEAD and DELETE.
- **A table.** The payload will be sent as url encoded wwwform, where the keys of the table are the form field names. Both keys and values must be strings, or convertible to strings by lua.
- **One or two strings.** The first string defines the payload to be sent, the second is optional and defines the content type, which defaults to 'text/plain' if none is specified.

Returns the same HttpRequest.

## Things to Note

- The whitelist check is evaluated twice: Once when `http_request:set_url(string)` is called, to see if any request to this domain is allowed, and once again when the request is executed, this time with the specified host + method.
- Any and all errors that may occur in the `http_request:set_callback(cb)` method are silently discarded in the C++ part. The standard lua wrapper (httplib mod) will, however, catch them and attempts to log them.
- In case the whitelist JSON is invalid, a message box is displayed that contains the error. There is no logging as of yet.
- Because of server-side limitations, it is not reliably possible to execute HTTP requests on the server realm while the game isn't running. Fire the request on the client side, or manually somehow call `http.update()` when it's convenient. If you really want blocking requests (i.e. in the main menu), you can also spam `http.update()` until it returns 0.

# Credits and Third Party Dependencies

- [lua 5.1.5](https://www.lua.org/): The base for this project.
- [coco](http://coco.luajit.org/): Required JIT bits for Stonehearth.
- max99x: The necessary patches to make this even work with Stonehearth, and guidance here and there with engine internal stuff.
- [libcurl](http://curl.haxx.se/): Used for the HTTP requests.