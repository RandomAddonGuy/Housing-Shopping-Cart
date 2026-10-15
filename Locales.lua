local _, HSC = ...

HSC.L = setmetatable({}, {
	__index = function(_, key)
		return key;
	end,
});
