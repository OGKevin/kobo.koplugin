# Say

[![Busted](https://img.shields.io/github/workflow/status/lunarmodules/say/Busted?label=Busted&logo=Lua)](https://github.com/lunarmodules/say/actions?workflow=Busted)
[![Luacheck](https://img.shields.io/github/workflow/status/lunarmodules/say/Luacheck?label=Luacheck&logo=Lua)](https://github.com/lunarmodules/say/actions?workflow=Luacheck)
[![GitHub tag (latest SemVer)](https://img.shields.io/github/v/tag/lunarmodules/say?label=Tag&logo=GitHub)](https://github.com/lunarmodules/say/releases)
[![Luarocks](https://img.shields.io/luarocks/v/lunarmodules/say?label=Luarocks&logo=Lua)](https://luarocks.org/modules/lunarmodules/say)

say is a simple string key/value store for i18n or any other case where you want namespaced strings.

Check out [busted](https://lunarmodules.github.io/busted/) for extended examples.

```lua
s = require("say")

s:set_namespace("en")

s:set('money', 'I have %s dollars')
s:set('wow', 'So much money!')

print(s('money', {1000})) -- I have 1000 dollars

s:set_namespace("fr") -- switch to french!
s:set('so_much_money', "Tant d'argent!")

print(s('wow')) -- Tant d'argent!
s:set_namespace("en")  -- switch back to english!
print(s('wow')) -- So much money!
```

NOTE: the parameters table can have `nil` values, but in that case it must have an `n` field to indicate table size.

```lua
s = require("say")

s:set('money', 'I have %s %s')

print(s('money', {1000, "dollars"})) -- I have 1000 dollars
print(s('money', {nil, "euros", n = 2})) -- I have nil euros
```
