--[[
Copyright (C) 2026 duckthing

This software is provided 'as-is', without any express or implied
warranty.  In no event will the authors be held liable for any damages
arising from the use of this software.

Permission is granted to anyone to use this software for any purpose,
including commercial applications, and to alter it and redistribute it
freely, subject to the following restrictions:

1. The origin of this software must not be misrepresented; you must not
   claim that you wrote the original software. If you use this software
   in a product, an acknowledgment in the product documentation would be
   appreciated but is not required.
2. Altered source versions must be plainly marked as such, and must not be
   misrepresented as being the original software.
3. This notice may not be removed or altered from any source distribution.
--]]
local tclear
do
	-- Load LuaJIT's table.clear function, if possible, just for clearing arrays
	local success, lib = pcall(require, "table.clear")
	if success then
		tclear = lib
	else
		tclear = function(t)
			for i = #t, 1, -1 do
				t[i] = nil
			end
		end
	end
end

local unpack = unpack
if not unpack then unpack = table.unpack end

local EMPTY_TABLE = {}
---@type number[]
local outputQueue = {}
---@type string[]
local operatorStack = {}
---@type integer[]
local parameterCountStack = {}
---@type number[] # Where the final results go
local finalStack = {}
---@type number[] # The parameters that go into the function calls
local paramArr = {}

local operatorPriority = {
	["^"] = 4,
	["*"] = 3,
	["/"] = 3,
	["+"] = 2,
	["-"] = 2,
	unary = 4,
	noop = 4,
}

local operatorAssociativity = {
	["^"] = "right",
	["*"] = "left",
	["/"] = "left",
	["+"] = "left",
	["-"] = "left",
	unary = "right",
	noop = "right",
}

local operatorFunc = {
	["^"] = function(a, b) return a ^ b end,
	["*"] = function(a, b) return a * b end,
	["/"] = function(a, b) return a / b end,
	["+"] = function(a, b) return a + b end,
	["-"] = function(a, b) return a - b end,
	unary = function(a) return -a end,
	noop = function(a) return a end,
}

local function pushToStack(t, value)
	t[#t+1] = value
end

---@param t any[]
---@return any?
local function popFromStack(t)
	local last = #t
	if last > 0 then
		local val = t[last]
		t[last] = nil
		return val
	end
end

---@return any?
local function peekStack(t) return t[#t] end

local function enqueue(t, value)
	if value then
		table.insert(t, 1, value)
	end
end

local function getSymbol(name, ...)
	for i = 1, select("#", ...) do
		local t = select(i, ...)
		if t then
			local result = t[name]
			if result then return result end
		end
	end
end

local pos = 1
local str = ""
local lastToken = "none"

---@return "operator" | "symbol" | "number" | "comma" | "leftParen" | "rightParen" | "invalid" | nil
---@return string | number | nil
local function _eachTokenIter(_, args)
	while pos <= #str do
		local char = str:sub(pos, pos)

		if char ~= " " then
			if char == "," then
				-- Comma, return it
				pos = pos + 1
				lastToken = "comma"
				return "comma", ","
			elseif char == "(" then
				-- Left parenthesis, return it
				pos = pos + 1
				lastToken = "leftParen"
				return "leftParen", "("
			elseif char == ")" then
				-- Right parenthesis, return it
				pos = pos + 1
				lastToken = "rightParen"
				return "rightParen", ")"
			elseif operatorPriority[char] then
				-- Operator...

				-- ...if it looks like a negative number, try and turn it into one
				if lastToken ~= "number" and char == "-" then
					-- A negative number makes sense after a non-number token
					local negativeSignsStr, endPos = str:match("([%-%s]*)()", pos)
					if negativeSignsStr then
						-- Both strings exist
						local negativeCount = 0

						-- Count the negative signs
						for _ in negativeSignsStr:gmatch("-") do negativeCount = negativeCount + 1 end

						-- Do nothing by default
						local action = "noop"

						-- If there's an odd amount of negative signs, flip it
						if negativeCount % 2 == 1 then
							action = "unary"
						end

						pos = endPos
						lastToken = "operator"
						return "operator", action
					end
				end

				-- ...otherwise, return it
				pos = pos + 1
				lastToken = "operator"
				return "operator", char
			elseif char:match("^[%d%.]") then
				-- It looks like a number if it starts with a number or period
				-- "123"
				-- ".123"
				local numStr, newPos = str:match("([%d%.]+)()", pos)
				local num = tonumber(numStr)
				if num then
					pos = newPos
					lastToken = "number"
					return "number", num
				else
					-- Invalid number
					pos = math.huge
					return "invalid", nil
				end
			elseif char:match("^[_%a]") then
				-- It looks like a symbol if it starts with a letter/underscore, and has letters/underscores/numbers later
				local funcName, newPos = str:match("([_%a]?[_%a%d]*)()", pos)
				pos = newPos
				lastToken = "symbol"
				return "symbol", funcName
			else
				-- Invalid
				pos = math.huge
				return "invalid", nil
			end
		else
			-- Space, do nothing
			pos = pos + 1
		end
	end

	-- Consumed whole string
	return nil, nil
end

local function _eachParsedTokenIter(arr)
	local tokenType, token = arr[pos], arr[pos + 1]
	pos = pos + 2
	return tokenType, token
end

local function _errIter() return "invalid" end

---@param s string | (string | number)[]
local function eachToken(s)
	local sType = type(s)
	pos = 1
	if sType == "string" then
		-- Simplify exponent "**" into "^"
		str = s:gsub("%*%*", "%^")
		lastToken = "none"
		return _eachTokenIter, str
	elseif sType == "table" then
		-- Iterate through each
		return _eachParsedTokenIter, s
	else
		-- Invalid type
		return _errIter, 0
	end
end

---@param expr string
---@return boolean success
---@return (string | number)[] | string | nil tokens
local function parse(expr)
	---@type table # Reusing an existing table, replaced later if expr is valid
	local parsedTokens = outputQueue
	tclear(parsedTokens)

	local i = 1
	for tokenType, token in eachToken(expr) do
		if tokenType ~= "invalid" then
			parsedTokens[i] = tokenType
			parsedTokens[i + 1] = token
			i = i + 2
		elseif tokenType == "invalid" then
			tclear(outputQueue)
			return false, "Invalid expression"
		else
			break
		end
	end

	-- Replace the output queue
	outputQueue = {}
	return true, parsedTokens
end

---For a given expression, returns `true` if evaluation was successful, and a tuple with each result.
---If unsuccessful, returns `false` and the error string.
---
---`expr` may be a string or an array of tokens from the `parse` function.
---By default, `env` is equal to the `math` global table. It can be replace with other tables, or
---set to nothing by passing `false` instead.
---@param expr string | (string | number)[] # Either the expression or parsed tokens
---@param env table | false | nil # Symbols to use
---@param ... table? # Additional symbols
---@return boolean success
---@return ...|number
local function solve(expr, env, ...)
	tclear(outputQueue)
	tclear(operatorStack)
	tclear(parameterCountStack)

	if not env then
		if env == nil and select("#", ...) == 0 then
			-- Make default environment the `math` library if nothing else was found
			env = math
		else
			-- Make default environment have nothing
			env = EMPTY_TABLE
		end
	end
	---@cast env table

	for tokenType, token in eachToken(expr) do
		local shouldContinue = false

		if tokenType == "symbol" then
			-- Parse symbols
			---@type number | string | function | nil
			local value = getSymbol(token, env, ...)

			if not value then
				-- Not found
				return false, ("Invalid symbol '%s'"):format(token)
			end

			local valueType = type(value)
			if valueType == "number" then
				-- Switch token to number
				tokenType, token = "number", value
			elseif valueType == "function" then
				-- It's a function
				pushToStack(operatorStack, value)

				-- Fix functions with only 1 parameter
				if peekStack(parameterCountStack) == 0 then
					pushToStack(parameterCountStack, popFromStack(parameterCountStack) + 1)
				end

				shouldContinue = true
			else
				-- Invalid value type
				return false, ("Invalid symbol type '%s' (from symbol '%s')"):format(valueType, token)
			end
		end

		if not shouldContinue and tokenType == "number" then
			enqueue(outputQueue, token)

			-- Fix functions with only 1 parameter
			if peekStack(parameterCountStack) == 0 then
				pushToStack(parameterCountStack, popFromStack(parameterCountStack) + 1)
			end

			shouldContinue = true
		end

		if not shouldContinue then
			if tokenType == "operator" then
				local o1Precedence = operatorPriority[token]
				while true do
					local o2 = peekStack(operatorStack)
					if not o2 or o2 == "(" then break end
					local o2Precedence = operatorPriority[o2]
					if not (o2Precedence > o1Precedence or (o1Precedence == o2Precedence and operatorAssociativity[token] == "left")) then
						break
					end

					enqueue(outputQueue, popFromStack(operatorStack))
				end
				pushToStack(operatorStack, token)
			elseif tokenType == "comma" then
				local foundParen = false
				while true do
					local nextOperator = peekStack(operatorStack)
					if nextOperator == nil then break end
					if nextOperator == "(" then foundParen = true break end
					enqueue(outputQueue, popFromStack(operatorStack))
				end

				if foundParen then
					pushToStack(parameterCountStack, popFromStack(parameterCountStack) + 1)
				end
			elseif tokenType == "leftParen" then
				pushToStack(operatorStack, "(")
				pushToStack(parameterCountStack, 0)
			elseif tokenType == "rightParen" then
				while true do
					if #operatorStack == 0 then return false, "Invalid expression" end
					local nextOperator = peekStack(operatorStack)
					if nextOperator == "(" then break end
					enqueue(outputQueue, popFromStack(operatorStack))
				end

				if peekStack(operatorStack) ~= "(" then return false, "Invalid expression" end
				popFromStack(operatorStack)

				if type(peekStack(operatorStack)) == "function" then
					enqueue(outputQueue, popFromStack(operatorStack))
					enqueue(outputQueue, popFromStack(parameterCountStack))

					-- Fix functions with only 1 parameter
					if peekStack(parameterCountStack) == 0 then
						pushToStack(parameterCountStack, popFromStack(parameterCountStack) + 1)
					end
				end
			elseif tokenType == "invalid" then
				return false, "Invalid expression"
			end
		end
	end

	while #operatorStack > 0 do
		local nextOperator = popFromStack(operatorStack)
		if nextOperator == "(" then return false, "Invalid expression (mismatched parenthesis)" end
		enqueue(outputQueue, nextOperator)
	end

	-- Evaluate
	-- (from now on, `outputQueue` is used as a stack)
	tclear(finalStack)
	tclear(paramArr)

	while #outputQueue > 0 do
		local nextItem = popFromStack(outputQueue)
		if type(nextItem) == "number" then
			pushToStack(finalStack, nextItem)
		else
			if operatorPriority[nextItem] then
				-- It's an operator, verify there are two numbers
				if #nextItem == 1 then
					-- If the operator name is 1 character, it takes two parameter
					-- The parameters are flipped due to the stack
					local b, a = popFromStack(finalStack), popFromStack(finalStack)
					if not a or not b then return false, "Invalid expression" end
					pushToStack(finalStack, operatorFunc[nextItem](a, b))
				else
					-- If the operator name is 2+ characters, it takes 1 parameter
					local a = popFromStack(finalStack)
					if not a then return false, "Invalid expression" end
					pushToStack(finalStack, operatorFunc[nextItem](a))
				end
			else
				-- It's a function
				do
					-- Put the parameters into the field
					---@type integer # The parameters this next function will take
					local paramCount = popFromStack(outputQueue)

					local finalStackLength = #finalStack
					local startPoint = finalStackLength - paramCount

					-- Add the parameters
					for i = 1, paramCount do
						paramArr[i] = finalStack[startPoint + i]
					end

					-- Remove the elements from the stack
					for i = finalStackLength, startPoint + 1, -1 do
						finalStack[i] = nil
					end
				end

				-- Call the function and put the results into a table
				local results = {pcall(nextItem, unpack(paramArr))}
				tclear(paramArr)

				-- First element is false if the call errored
				if not results[1] then return false, ("Errored in function: %s"):format(results[2]) end

				-- Insert the function results into the final results stack
				local startPoint = #finalStack
				for i = 2, #results do
					finalStack[startPoint + i - 1] = results[i]
				end
			end
		end
	end

	if #finalStack > 0 then
		return true, unpack(finalStack)
	else
		return false
	end
end

local Expression = {
	parse = parse,
	solve = solve,
}

return Expression
