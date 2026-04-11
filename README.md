# Expression
Evaluate math expressions from user input safely.
* Call functions inside of expressions with variable length parameters and results
* Return variable length results
* Provide custom sets of functions and values, for use inside of expressions
* Small library size

With some caveats...
* Only supports returning numbers
* Also only as safe as the functions in the environment
* `inf` and `nan` can be inserted and returned

## Example
```lua
local Expression = require "expression"

-- Expressions are solved with proper order of operations
print(Expression.solve("5 + 10 * 15"))
--> true, 155
print(Expression.solve("3 + 4 * 2 / (1 - 5) ^ 2 ^ 3"))
--> true, 3.00
print(Expression.solve("3 + 4 * 2 / (1 - 5) ** 2 ** 3"))
--> true, 3.00

-- Multiple results can be returned
print(Expression.solve("2^3, pi * 2"))
--> true, 8, 6.283

-- Functions and values depend on the environment provided.
-- By default, the `math` table is used, but can be replaced by
-- setting the second parameter to a different table or `false`.

-- These work without erroring, as each symbol is in `math`
print(Expression.solve("atan2(0, -1) / pi"))
--> true, 1
print(Expression.solve("atan2(0, -1) / pi", math))
--> true, 1

-- Both will lack the `atan2` function and the `pi` constant
print(Expression.solve("atan2(-1, 0) / pi", false))
--> false, "Invalid symbol 'atan2'"
print(Expression.solve("atan2(-1, 0) / pi", {}))
--> false, "Invalid symbol 'atan2'"

-- Tables can provide functions and numbers to the expression
print(Expression.solve("x + 5, y * 2", {x = 10, y = 20}))
--> true, 15, 40
print(Expression.solve("x + 5, y * 2"))
--> false, "Invalid symbol 'x'"

-- The first table also prevents the `math` table from being used.
-- Pass it again as another parameter.
print(Expression.solve("atan2(y, x) / pi"))
--> false, "Invalid symbol 'y'"
print(Expression.solve("atan2(y, x) / pi", {x = -1, y = 0}))
--> false, "Invalid symbol 'atan2'"
print(Expression.solve("atan2(y, x) / pi", {x = -1, y = 0}, math))
--> true, 1

-- Symbols are looked up from the first parameter to the last parameter.
-- Earlier parameters are prioritized.

-- Functions are provided the parameters as normal numbers.
-- Variable count parameters are supported, too.
-- Here's a functional way of summing up every number in a tuple.

local mySymbols = {
	meaningOfLife = 42,
	sum = function(...)
		local sum = 0
		for i = 1, select("#", ...) do
			sum = sum + select(i, ...)
		end
		return sum
	end,
}

print(Expression.solve("sum(1, 2, 3)"))
--> false, "Invalid symbol 'sum'"
print(Expression.solve("sum(1, 2, 3)", mySymbols))
--> true, 6
print(Expression.solve("sum(meaningOfLife, 6, 6, 6, 7)", mySymbols))
--> true, 67

-- You can parse an expression without running it.
-- This allows you to check if an expression looks correct, but solve it later.
-- Parsing early is useful if you would like to use an expression repeatedly.
local success, parsedTokens = Expression.parse("x * 2, y * 2")
print(success, parsedTokens)
---> true, <table>
print(Expression.solve(parsedTokens, {x = 1, y = 2}))
---> true, 2, 4
print(Expression.solve(parsedTokens, {x = 10, y = 20}))
---> true, 20, 40
print(Expression.solve(parsedTokens, {x = 20, y = 40}))
---> true, 40, 80
print(Expression.solve(parsedTokens))
---> false, "Invalid symbol 'x'"
```

## Usage
Paste `expression.lua` into your project, or add it with a git submodule:

`git submodule add https://github.com/duckthing/expression.git ./lib/expression`

## License
This project is licensed under the terms of the zlib license.
