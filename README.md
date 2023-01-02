# RetroGadgets Web

## Basic usage

Make sure you have a security chip, a wifi chip and a CPU on your gadget, then
configure your gadget's security permissions to allow your gadget to send and receive network data.

Import `web.lua` into RetroGadgets asset list, or copy/paste the contents of it into a lua asset with the same name.

Then, in your `CPU0.lua` file (or other CPU file):

```lua
-- Require the library
local Web = require("web.lua")

-- Create an instance of Web.
-- (The defaults used are Wifi0, CPU0 and the first available event channel on the CPU)
local web: Web.Web = Web.create()

-- Make a web request
local request: Web.Request = web.get(
    "https://example.com",
    function(result: Web.Result) 
        -- check if the response code is 200
        if result.ok then
            print(result.text) -- do something with the data
        else
            print(result.errorMessage) -- handle error
        end
    end
)
```
