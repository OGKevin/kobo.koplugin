local function getUniqueId(obj)
  return tonumber(tostring(obj):match(':%s*[0xX]*(%x+)'), 16)
end

local function Subscriber(fn, options)
  local sub = {
    options = options or {},
    fn = fn,
    channel = nil,
    update = function(self, options)
      if options then
        self.fn = options.fn or self.fn
        self.options = options.options or self.options
      end
    end
  }
  sub.id = getUniqueId(sub)
  return sub
end

-- Channel class and functions --

local function Channel(namespace, parent)
  return {
    stopped = false,
    namespace = namespace,
    callbacks = {},
    channels = {},
    parent = parent,

    addSubscriber = function(self, fn, options)
      local callback = Subscriber(fn, options)
      local priority = (#self.callbacks + 1)

      options = options or {}

      if options.priority and
        options.priority >= 0 and
        options.priority < priority
      then
          priority = options.priority
      end

      table.insert(self.callbacks, priority, callback)

      return callback
    end,

    getSubscriber = function(self, id)
      for i=1, #self.callbacks do
        local callback = self.callbacks[i]
        if callback.id == id then return { index = i, value = callback } end
      end
      local sub
      for _, channel in pairs(self.channels) do
        sub = channel:getSubscriber(id)
        if sub then break end
      end
      return sub
    end,

    setPriority = function(self, id, priority)
      local callback = self:getSubscriber(id)

      if callback.value then
        table.remove(self.callbacks, callback.index)
        table.insert(self.callbacks, priority, callback.value)
      end
    end,

    addChannel = function(self, namespace)
      self.channels[namespace] = Channel(namespace, self)
      return self.channels[namespace]
    end,

    hasChannel = function(self, namespace)
      return namespace and self.channels[namespace] and true
    end,

    getChannel = function(self, namespace)
      return self.channels[namespace] or self:addChannel(namespace)
    end,

    removeSubscriber = function(self, id)
      local callback = self:getSubscriber(id)

      if callback and callback.value then
        for _, channel in pairs(self.channels) do
          channel:removeSubscriber(id)
        end

        return table.remove(self.callbacks, callback.index)
      end
    end,

    publish = function(self, result, ...)
      for i = 1, #self.callbacks do
        local callback = self.callbacks[i]

        -- if it doesn't have a predicate, or it does and it's true then run it
        if not callback.options.predicate or callback.options.predicate(...) then
           -- just take the first result and insert it into the result table
          local value, continue = callback.fn(...)

          if value then table.insert(result, value) end
          if not continue then return result end
        end
      end

      if parent then
        return parent:publish(result, ...)
      else
        return result
      end
    end
  }
end

-- Mediator class and functions --

local Mediator = setmetatable(
{
  Channel = Channel,
  Subscriber = Subscriber
},
{
  __call = function (fn, options)
    return {
      channel = Channel('root'),

      getChannel = function(self, channelNamespace)
        local channel = self.channel

        for i=1, #channelNamespace do
          channel = channel:getChannel(channelNamespace[i])
        end

        return channel
      end,

      subscribe = function(self, channelNamespace, fn, options)
        return self:getChannel(channelNamespace):addSubscriber(fn, options)
      end,

      getSubscriber = function(self, id, channelNamespace)
        return self:getChannel(channelNamespace):getSubscriber(id)
      end,

      removeSubscriber = function(self, id, channelNamespace)
        return self:getChannel(channelNamespace):removeSubscriber(id)
      end,

      publish = function(self, channelNamespace, ...)
        return self:getChannel(channelNamespace):publish({}, ...)
      end
    }
  end
})
return Mediator
