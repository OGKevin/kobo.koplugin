David Kolf's JSON module for Lua 5.1 - 5.4
==========================================

*Version 2.8*

In the default configuration this module writes no global values, not even
the module table. Import it using

    json = require ("dkjson")

In environments where `require` or a similiar function are not available
and you cannot receive the return value of the module, you can set the
option `register_global_module_table` to `true`.  The module table will
then be saved in the global variable with the name given by the option
`global_module_name`.

Exported functions and values:

`json.encode (object [, state])`
--------------------------------

Create a string representing the object. `Object` can be a table,
a string, a number, a boolean, `nil`, `json.null` or any object with
a function `__tojson` in its metatable. A table can only use strings
and numbers as keys and its values have to be valid objects as
well. It raises an error for any invalid data types or reference
cycles.

`state` is an optional table with the following fields:

  - `indent`  
    When `indent` (a boolean) is set, the created string will contain
    newlines and indentations. Otherwise it will be one long line.
  - `keyorder`  
    `keyorder` is an array to specify the ordering of keys in the
    encoded output. If an object has keys which are not in this array
    they are written after the sorted keys.
  - `level`  
    This is the initial level of indentation used when `indent` is
    set. For each level two spaces are added. When absent it is set
    to 0.
  - `buffer`  
    `buffer` is an array to store the strings for the result so they
    can be concatenated at once. When it isn't given, the encode
    function will create it temporary and will return the
    concatenated result.
  - `bufferlen`  
    When `bufferlen` is set, it has to be the index of the last
    element of `buffer`.
  - `tables`  
    `tables` is a set to detect reference cycles. It is created
    temporary when absent. Every table that is currently processed
    is used as key, the value is `true`.
  - `exception`  
    When `exception` is given, it will be called whenever the encoder
    cannot encode a given value.  
    The parameters are `reason`, `value`, `state` and `defaultmessage`.
    `reason` is either `"reference cycle"`, `"custom encoder failed"` or
    `"unsupported type"`. `value` is the original value that caused the
    exception, `state` is this state table, `defaultmessage` is the message
    of the error that would usually be raised.  
    You can either return `true` and add directly to the buffer or you can
    return the string directly. To keep raising an error return `nil` and
    the desired error message.  
    An example implementation for an exception function is given in
    `json.encodeexception`.

When `state.buffer` was set, the return value will be `true` on
success. Without `state.buffer` the return value will be a string.

`json.decode (string [, position [, null]])`
--------------------------------------------

Decode `string` starting at `position` or at 1 if `position` was
omitted.

`null` is an optional value to be returned for null values. The
default is `nil`, but you could set it to `json.null` or any other
value.

The return values are the object or `nil`, the position of the next
character that doesn't belong to the object, and in case of errors
an error message.

Two metatables are created. Every array or object that is decoded gets
a metatable with the `__jsontype` field set to either `array` or
`object`. If you want to provide your own metatables use the syntax

    json.decode (string, position, null, objectmeta, arraymeta)

To prevent the assigning of metatables pass `nil`:

    json.decode (string, position, null, nil)

`<metatable>.__jsonorder`
-------------------------

`__jsonorder` can overwrite the `keyorder` for a specific table.

`<metatable>.__jsontype`
------------------------

`__jsontype` can be either `"array"` or `"object"`. This value is only
checked for empty tables. (The default for empty tables is `"array"`).

`<metatable>.__tojson (self, state)`
------------------------------------

You can provide your own `__tojson` function in a metatable. In this
function you can either add directly to the buffer and return true,
or you can return a string. On errors nil and a message should be
returned.

`json.null`
-----------

You can use this value for setting explicit `null` values.

`json.version`
--------------

Set to `"dkjson 2.8"`.

`json.quotestring (string)`
---------------------------

Quote a UTF-8 string and escape critical characters using JSON
escape sequences. This function is only necessary when you build
your own `__tojson` functions.

`json.addnewline (state)`
-------------------------

When `state.indent` is set, add a newline to `state.buffer` and spaces
according to `state.level`.

`json.encodeexception (reason, value, state, defaultmessage)`
-------------------------------------------------------------

This function can be used as value to the `exception` option. Instead of
raising an error this function encodes the error message as a string. This
can help to debug malformed input data.

    x = json.encode(value, { exception = json.encodeexception })

LPeg support
------------

When the local configuration variable `always_use_lpeg` is set,
this module tries to load LPeg to replace the `decode` function. The
speed increase is significant. You can get the LPeg module at
  <http://www.inf.puc-rio.br/~roberto/lpeg/>.

Without changing the module configuration you can get LPeg support by
calling the function `use_lpeg`:

### `json.use_lpeg ()`

Require the LPeg module and return a copy of the module table where the
`decode` function was replaced by a version that uses LPeg:

    json = require "dkjson".use_lpeg()

Without the configuration to always use LPEG the original module table is
unchanged and still available by calls to

    json = require "dkjson"

### `json.using_lpeg`

This variable is set to `true` in the copy of the module table that uses
LPeg support.

---------------------------------------------------------------------

Contact
-------

You can contact the author by sending an e-mail to 'david' at the
domain 'dkolf.de'.

---------------------------------------------------------------------

*Copyright (C) 2010-2024 David Heiko Kolf*

Permission is hereby granted, free of charge, to any person obtaining
a copy of this software and associated documentation files (the
"Software"), to deal in the Software without restriction, including
without limitation the rights to use, copy, modify, merge, publish,
distribute, sublicense, and/or sell copies of the Software, and to
permit persons to whom the Software is furnished to do so, subject to
the following conditions:

The above copyright notice and this permission notice shall be
included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS
BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN
ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

