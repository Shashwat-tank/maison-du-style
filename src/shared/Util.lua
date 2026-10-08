local Util = {}

local rng = Random.new()

-- In-place Fisher-Yates shuffle. Returns the same list for chaining.
function Util.shuffle(list: { any }): { any }
	for i = #list, 2, -1 do
		local j = rng:NextInteger(1, i)
		list[i], list[j] = list[j], list[i]
	end
	return list
end

return Util
