mediator\_lua
===========

Version 1.0

For more information, please see 

[View the project on Github](https://github.com/OlivineLabs/mediator_lua)

[View the documentation](http://olivinelabs.com/mediator_lua)

If you have [luarocks](http://luarocks.org), install it with `luarocks install mediator_lua`.
If you don't, get it. If you really don't want to, just copy mediator.lua from the 
[Git repository](https://github.com/OlivineLabs/mediator_lua).

A utility class to help you manage events.
------------------------------------------

mediator\_lua is a simple class that allows you to listen to events by subscribing to
and sending data to channels. Its purpose is to help you decouple code where you
might otherwise have functions calling functions calling functions, and instead
simply call `mediator.publish("chat", { message = "hi" })`

Why?
----

My specific use case: manage HTTP routes called in OpenResty. There's an excellent 
article that talks about the Mediator pattern (in Javascript) in more in detail by 
[Addy Osmani](http://addyosmani.com/largescalejavascript/#mediatorpattern)
(that made me go back and refactor this code a bit.)

Usage
-----

You can register events with the mediator two ways: using channels, or with a 
*predicate* to perform more complex matching (a predicate is a function that
returns a true/false value that determines if mediator should run the callback.) 

Instantiate a new mediator, and then you can being subscribing, removing, and publishing.

Example:

```lua
Mediator = require "mediator_lua"
mediator = Mediator() -- instantiate a new mediator

mediator:publish(channel, <data, data, ... >)
mediator:remove(<channel>) 
```

Subscription signature:

```lua
(channel, callback, <options>, <context>);
```

Callback signature:

```lua
function(<data, data ...>, channel);
```

Mediator:subscribe `options` (all are optional; default is empty):


```lua
{
  predicate = function(arg1, arg2) return arg1 == arg2 end
  priority = 0|1|... (array index; max of callback array length, min of 0)
}
```

When you call `subscribe`, you get a `subscriber` object back that you can use to
update and change options. It looks like:


```lua
{
  id, -- unique identifier
  fn, -- function you passed in
  options, -- options
  context, -- context for fn to be called within
  channel, -- provides a pointer back to its channel
  update(options) -- function that accepts { fn, options, context }
}
```

Examples:


```lua
Mediator = require("mediator_lua")
local mediator = Mediator()

-- Print data when the "message" channel is published to
-- Subscribe returns a "Subscriber" object
mediator:subscribe({ "message" }, function(data) print(data) end);
mediator:publish({ "message" }, "Hello, world");

  >> Hello, world

-- Print the message when the predicate function returns true
local predicate = function(data) 
  return data.From == "Jack" 
end

mediator.Subscribe({ "channel" }, function(data) print(data.Message) end, { predicate = predicate });
mediator.Publish({ "channel" }, { Message = "Hey!", From = "Jack" })
mediator.Publish({ "channel" }, { Message = "Hey!", From = "Drew" })

  >> Hey!
```

You can remove events by passing in a type or predicate, and optionally the 
function to remove.


```lua
-- removes all methods bound to a channel 
mediator:remove({ "channel" })

-- unregisters MethodFN, a named function we defined elsewhere, from "channel" 
mediator:remove({ "channel" }, MethodFN)
```

You can call the registered functions with the `publish` method, which accepts 
an args array:


```lua
mediator:publish({ "channel" }, "argument", "another one", { etc: true }); # args go on forever
```

You can namespace your subscribing / removing / publishing. This will recurisevely
call children, and also subscribers to direct parents.


```lua
mediator:subscribe({ "application:chat:receiveMessage" }, function(data){ ... })

-- will recursively call anything in the appllication:chat:receiveMessage namespace 
-- will also call thins directly subscribed to application and application:chat,
-- but not their children
mediator:publish({ "application", "chat", "receiveMessage" }, "Jack Lawson", "Hey")

-- will recursively remove everything under application:chat
mediator:remove({ "application", "chat" })
```

You can update Subscriber priority:


```lua
local sub = mediator:subscribe({ "application", "chat" }, function(data){ ... })
local sub2 = mediator:subscribe({ "application", "chat" }, function(data){ ... })

-- have sub2 executed first
mediator.GetChannel({ "application", "chat" }).SetPriority(sub2.id, 0);
```

You can update Subscriber callback, context, and/or options:


```lua
sub:update({ fn: ..., context = { }, options = { ... })
```

You can stop the chain of execution by calling channel:stopPropagation()


```lua
-- for example, let's not post the message if the `from` and `to` are the same
mediator.Subscribe({ "application", "chat" }, function(data, channel) 
  -- throw an error message or something
  channel:stopPropagation()
end, options = {
  predicate = function(data) return data.From == data.To end,
  priority = 0
})
```


Testing
-------

Uses [lunit](http://www.nessie.de/mroth/lunit/) for testing; you can install it
through [luarocks](http://luarocks.org).

Contributing
------------

Build stuff, run the tests, then submit a pull request with comments and a
description of what you've done, and why.

License
-------
This code and its accompanying README and are 
[MIT licensed](http://www.opensource.org/licenses/mit-license.php). 


In Closing
----------
Have fun, and please submit suggestions and improvements! You can leave any 
issues here, or contact me on Twitter (@ajacksified).
