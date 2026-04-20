--[[

   ▄▄▄▄███▄▄▄▄      ▄████████     ███         ███             ▄████████  ▄████████    ▄████████  ▄█     ▄███████▄     ███        ▄████████    ▄████████ 
 ▄██▀▀▀███▀▀▀██▄   ███    ███ ▀█████████▄ ▀█████████▄        ███    ███ ███    ███   ███    ███ ███    ███    ███ ▀█████████▄   ███    ███   ███    ███ 
 ███   ███   ███   ███    ███    ▀███▀▀██    ▀███▀▀██        ███    █▀  ███    █▀    ███    ███ ███▌   ███    ███    ▀███▀▀██   ███    █▀    ███    ███ 
 ███   ███   ███   ███    ███     ███   ▀     ███   ▀        ███        ███         ▄███▄▄▄▄██▀ ███▌   ███    ███     ███   ▀  ▄███▄▄▄      ▄███▄▄▄▄██▀ 
 ███   ███   ███ ▀███████████     ███         ███          ▀███████████ ███        ▀▀███▀▀▀▀▀   ███▌ ▀█████████▀      ███     ▀▀███▀▀▀     ▀▀███▀▀▀▀▀   
 ███   ███   ███   ███    ███     ███         ███                   ███ ███    █▄  ▀███████████ ███    ███            ███       ███    █▄  ▀███████████ 
 ███   ███   ███   ███    ███     ███         ███             ▄█    ███ ███    ███   ███    ███ ███    ███            ███       ███    ███   ███    ███ 
  ▀█   ███   █▀    ███    █▀     ▄████▀      ▄████▀         ▄████████▀  ████████▀    ███    ███ █▀    ▄████▀         ▄████▀     ██████████   ███    ███ 
                                                                                     ███    ███                                              ███    ███
	-> Discord: @eo_mtzsz
	-> Portfolio: https://discord.gg/GWU5pJJTpD
	-> Roblox Creator / Experienced Programmer / Team Coordinator & Tech Lead / Dev
]]

export type Guard         = (from: string, to: string, context: any) -> boolean
export type StateCallback = (context: any, previous: string?) -> ()
export type HookCallback  = (from: string, to: string, context: any) -> boolean?
export type EventHandler  = (context: any, payload: any?) -> string?

export type TransitionDef = {
	target   : string,
	guard    : (Guard | boolean | string)?,
	priority : number?,
	label    : string?,
}

export type StateDefinition = {
	onEnter     : StateCallback?,
	onExit      : StateCallback?,
	onUpdate    : StateCallback?,
	on          : { [string]: EventHandler | string }?,
	tags        : { string }?,
	timeout     : number?,
	timeoutNext : string?,
	transitions : { TransitionDef }?,
	states      : { [string]: StateDefinition }?,
	initial     : string?,
}

export type Snapshot = {
	version           : number,
	current           : string,
	previous          : string?,
	history           : { string },
	stack             : { string },
	context           : { [string]: any },
	replay            : { ReplayEvent },
	deterministicTick : number?,
}

export type Delta = {
	version  : number,
	current  : string,
	previous : string?,
	context  : { [string]: any },
	tick     : number,
}

export type ReplayEvent = {
	time   : number,
	from   : string,
	to     : string,
	reason : string,
}

export type ProfileEntry = {
	totalTime  : number,
	enterCount : number,
	lastEnter  : number,
}

export type ValidationError = {
	state  : string,
	target : string,
	reason : string,
}

export type AnalysisResult = {
	unreachable : { string },
	deadEnds    : { string },
	loops       : { { string } },
}

export type StateMachine     = typeof(setmetatable({} :: any, {} :: any))
export type MachineGroupType = typeof(setmetatable({} :: any, {} :: any))

local VERSION = 8

local function deepCopy(t: any, _seen: { [any]: any }?): any
	if type(t) ~= "table" then return t end
	local seen = _seen or {}
	if seen[t] then return seen[t] end
	local c = setmetatable({}, getmetatable(t))
	seen[t] = c
	for k, v in pairs(t) do c[deepCopy(k, seen)] = deepCopy(v, seen) end
	return c
end

local function shallowCopy(t: { [any]: any }): { [any]: any }
	local c = {}
	for k, v in pairs(t) do c[k] = v end
	return c
end

local function removeFirst(list: { any }, value: any)
	for i = #list, 1, -1 do
		if list[i] == value then table.remove(list, i) return end
	end
end

local function unsub(list: { any }, fn: any): () -> ()
	return function() removeFirst(list, fn) end
end

local function jsonEncode(v: any, depth: number?): string
	local t = type(v)
	if t == "nil"                          then return "null"
	elseif t == "boolean" or t == "number" then return tostring(v)
	elseif t == "string" then
		return '"' .. v:gsub('\\','\\\\'):gsub('"','\\"'):gsub('\n','\\n'):gsub('\t','\\t') .. '"'
	elseif t == "table" then
		local pad   = depth and string.rep("  ", depth)   or ""
		local inner = depth and string.rep("  ", depth+1) or ""
		local nl    = depth and "\n" or ""
		local sep   = depth and ",\n" or ","
		if v[1] ~= nil then
			local parts = {}
			for _, item in ipairs(v) do
				table.insert(parts, inner .. jsonEncode(item, depth and depth+1))
			end
			return "[" .. nl .. table.concat(parts, sep) .. nl .. pad .. "]"
		else
			local parts, keys = {}, {}
			for k in pairs(v) do table.insert(keys, k) end
			table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
			for _, k in ipairs(keys) do
				if v[k] ~= nil then
					table.insert(parts,
						inner .. jsonEncode(tostring(k)) ..
							":" .. (depth and " " or "") ..
							jsonEncode(v[k], depth and depth+1))
				end
			end
			return "{" .. nl .. table.concat(parts, sep) .. nl .. pad .. "}"
		end
	end
	return "null"
end

local function compileGuard(expr: string): Guard?
	local fn, err = loadstring("return function(from,to,ctx) return " .. expr .. " end")
	if not fn then
		warn(("[SMP] guard compile '%s': %s"):format(expr, tostring(err)))
		return nil
	end
	local ok, g = pcall(fn)
	return (ok and type(g) == "function") and g or nil
end

local function normalizeTransitions(raw: any): { TransitionDef }
	if type(raw) ~= "table" then return {} end
	local out: { TransitionDef } = {}
	if raw[1] ~= nil then
		for _, e in ipairs(raw) do
			assert(type(e.target) == "string", "[SMP] transition.target must be a string.")
			local g, lbl = e.guard, e.label
			if type(g) == "string" then lbl = lbl or g; g = compileGuard(g) or false end
			table.insert(out, { target = e.target, guard = g, priority = e.priority or 0, label = lbl })
		end
	else
		for target, g in pairs(raw) do
			if type(g) == "string" then g = compileGuard(g) or false end
			table.insert(out, { target = target, guard = g, priority = 0 })
		end
	end
	table.sort(out, function(a, b) return (a.priority or 0) > (b.priority or 0) end)
	return out
end

local function flattenInto(
	defs    : { [string]: StateDefinition },
	prefix  : string,
	parent  : string?,
	out     : { [string]: any },
	idMap   : { [string]: number },
	counter : { n: number }
)
	for name, def in pairs(defs) do
		local full = prefix ~= "" and (prefix .. "." .. name) or name
		if not idMap[full] then counter.n += 1; idMap[full] = counter.n end
		local flat = {
			id          = idMap[full],
			onEnter     = def.onEnter,
			onExit      = def.onExit,
			onUpdate    = def.onUpdate,
			on          = def.on or {},
			tags        = def.tags or {},
			timeout     = def.timeout,
			timeoutNext = def.timeoutNext,
			transitions = normalizeTransitions(def.transitions or {}),
			parent      = parent,
			initial     = nil :: string?,
		}
		if def.states and next(def.states) then
			assert(type(def.initial) == "string",
				("[SMP] compound state '%s' requires 'initial'."):format(full))
			flat.initial = full .. "." .. def.initial
			flattenInto(def.states, full, full, out, idMap, counter)
		end
		out[full] = flat
	end
end

local function heapPush(h: { any }, item: any, prio: number)
	table.insert(h, { item = item, p = prio })
	local i = #h
	while i > 1 do
		local pi = math.floor(i / 2)
		if h[pi].p >= h[i].p then break end
		h[pi], h[i] = h[i], h[pi]
		i = pi
	end
end

local function heapPop(h: { any }): any?
	local n = #h
	if n == 0 then return nil end
	local top = h[1].item
	h[1] = h[n]
	table.remove(h)
	n -= 1
	local i = 1
	while true do
		local l, r, best = 2*i, 2*i+1, i
		if l <= n and h[l].p > h[best].p then best = l end
		if r <= n and h[r].p > h[best].p then best = r end
		if best == i then break end
		h[i], h[best] = h[best], h[i]
		i = best
	end
	return top
end

local SMP   = {}
SMP.__index = SMP

function SMP.new(initialState: string, context: any?): StateMachine
	assert(type(initialState) == "string" and #initialState > 0,
		"[SMP] initialState must be a non-empty string.")
	local self = setmetatable({}, SMP)
	local now  = os.clock()
	self._rawInitial      = initialState
	self._states          = {} :: { [string]: any }
	self._idMap           = {} :: { [string]: number }
	self._idCounter       = { n = 0 }
	self._current         = initialState
	self._currentId       = 0
	self._previous        = nil :: string?
	self._previousId      = nil :: number?
	self._context         = context or {}
	self._prevCtxSnap     = {}
	self._running         = true
	self._paused          = false
	self._locked          = false
	self._debug           = false
	self._maxStackDepth   = 32
	self._timeScale       = 1
	self._deterministic   = false
	self._detTick         = 0
	self._stateStart      = now
	self._wallStart       = now
	self._history         = { initialState }
	self._stack           = {}
	self._compiled        = false
	self._matrix          = {}
	self._dtrees          = {}
	self._dtreesValid     = false
	self._transCache      = {}
	self._cacheValid      = false
	self._tagIdx          = {}
	self._tagIdxValid     = false
	self._listeners       = {}
	self._globalCbs       = {}
	self._beforeHooks     = {}
	self._afterHooks      = {}
	self._replayEnabled   = false
	self._replayLog       = {}
	self._inputLogEnabled = false
	self._inputLog        = {}
	self._profile         = {}
	self._evQueue         = {}
	self._evProcessing    = false
	self._regions         = {}
	self._regionOrder     = {}
	self._parallelRegions = false
	self._logBuf          = {}
	return self
end

function SMP:_rawNow(): number
	return self._deterministic and self._detTick or os.clock()
end

function SMP:_elapsed(since: number): number
	return (self:_rawNow() - since) * self._timeScale
end

function SMP:_syncIds()
	local d = self._states[self._current]
	if d then self._currentId = d.id end
	if self._previous then
		local pd = self._states[self._previous]
		if pd then self._previousId = pd.id end
	end
end

function SMP:_resolveLeaf(name: string, _seen: { [string]: boolean }?): string
	local seen = _seen or {}
	if seen[name] then
		warn(("[SMP] initial-chain cycle at '%s'"):format(name))
		return name
	end
	local def = self._states[name]
	if def and def.initial then
		seen[name] = true
		return self:_resolveLeaf(def.initial, seen)
	end
	return name
end

function SMP:_resolveGuard(guard: any, from: string, to: string): boolean
	if guard == nil or guard == true  then return true  end
	if guard == false                 then return false end
	if type(guard) == "function" then
		local ok, r = pcall(guard, from, to, self._context)
		if not ok then
			warn(("[SMP] guard error '%s'→'%s': %s"):format(from, to, r))
			return false
		end
		return r ~= false and r ~= nil
	end
	return false
end

function SMP:_ancestorChain(name: string): { string }
	local chain, cur = {}, name
	while cur do
		table.insert(chain, 1, cur)
		local def = self._states[cur]
		cur = def and def.parent and self._states[def.parent] and def.parent or nil
	end
	return chain
end

-- Returns the lowest common ancestor of a and b, or nil if they share none.
-- For a self-transition (a == b) returns the PARENT of a so that
-- onExit/onEnter fire correctly on the state itself.
function SMP:_lca(a: string, b: string): string?
	if a == b then
		local def = self._states[a]
		return def and def.parent or nil
	end
	local ca = self:_ancestorChain(a)
	local cb = self:_ancestorChain(b)
	local lca: string? = nil
	local i = 1
	while i <= #ca and i <= #cb do
		if ca[i] == cb[i] then lca = ca[i]; i += 1 else break end
	end
	return lca
end

function SMP:_log(msg: string)
	if not self._debug then return end
	local t    = self._deterministic and self._detTick or (os.clock() - self._wallStart)
	local line = ("[SMP %.4f] %s"):format(t, msg)
	print(line)
	table.insert(self._logBuf, line)
	if #self._logBuf > 500 then table.remove(self._logBuf, 1) end
end

function SMP:_buildCache()
	self._transCache = {}
	for name in pairs(self._states) do
		local merged, seen = {}, {}
		local cur = name
		while cur and not seen[cur] do
			seen[cur] = true
			local def = self._states[cur]
			if not def then break end
			for _, t in ipairs(def.transitions) do table.insert(merged, t) end
			cur = def.parent and self._states[def.parent] and def.parent or nil
		end
		table.sort(merged, function(a, b) return (a.priority or 0) > (b.priority or 0) end)
		self._transCache[name] = merged
	end
	self._cacheValid = true
end

function SMP:_buildTagIndex()
	self._tagIdx = {}
	for name, def in pairs(self._states) do
		for _, tag in ipairs(def.tags) do
			if not self._tagIdx[tag] then self._tagIdx[tag] = {} end
			table.insert(self._tagIdx[tag], name)
		end
	end
	for _, list in pairs(self._tagIdx) do table.sort(list) end
	self._tagIdxValid = true
end

function SMP:_buildDecisionTrees()
	if not self._cacheValid then self:_buildCache() end
	self._dtrees = {}
	for name in pairs(self._states) do
		local ts = self._transCache[name]
		if ts and #ts > 0 then
			local nodes = {}
			for _, t in ipairs(ts) do
				if t.guard == nil or t.guard == true then
					table.insert(nodes, { always = true, target = t.target, label = t.label })
					break
				end
				table.insert(nodes, { guard = t.guard, target = t.target, label = t.label })
			end
			self._dtrees[name] = nodes
		end
	end
	self._dtreesValid = true
end

function SMP:_evalTransitions(): (string?, string?)
	if self._compiled then
		local entries = self._matrix[self._currentId]
		if entries then
			for _, e in ipairs(entries) do
				if self:_resolveGuard(e.guard, self._current, e.target) then
					return e.target, e.label
				end
			end
		end
		return nil, nil
	end
	if not self._dtreesValid then self:_buildDecisionTrees() end
	local nodes = self._dtrees[self._current]
	if nodes then
		for _, node in ipairs(nodes) do
			if node.always then return node.target, node.label end
			if self:_resolveGuard(node.guard, self._current, node.target) then
				return node.target, node.label
			end
		end
	end
	return nil, nil
end

function SMP:_invalidate()
	self._cacheValid  = false
	self._dtreesValid = false
	self._tagIdxValid = false
	self._compiled    = false
end

function SMP:addState(name: string, def: StateDefinition): StateMachine
	assert(type(name) == "string" and #name > 0, "[SMP] state name must be a non-empty string.")
	assert(type(def) == "table",                  "[SMP] definition must be a table.")
	flattenInto({ [name] = def }, "", nil, self._states, self._idMap, self._idCounter)
	self:_syncIds()
	self:_invalidate()
	return self
end

function SMP:addStates(defs: { [string]: StateDefinition }): StateMachine
	assert(type(defs) == "table", "[SMP] definitions must be a table.")
	flattenInto(defs, "", nil, self._states, self._idMap, self._idCounter)
	self:_syncIds()
	self:_invalidate()
	return self
end

function SMP:reloadStates(defs: { [string]: StateDefinition })
	assert(self._running, "[SMP] machine has been destroyed.")
	assert(type(defs) == "table", "[SMP] definitions must be a table.")
	local flat = {}
	flattenInto(defs, "", nil, flat, self._idMap, self._idCounter)
	for name, nd in pairs(flat) do
		local ex = self._states[name]
		if ex then
			ex.onEnter     = nd.onEnter
			ex.onExit      = nd.onExit
			ex.onUpdate    = nd.onUpdate
			ex.on          = nd.on
			ex.tags        = nd.tags
			ex.timeout     = nd.timeout
			ex.timeoutNext = nd.timeoutNext
			ex.transitions = nd.transitions
		else
			self._states[name] = nd
		end
	end
	self:_syncIds()
	self:_invalidate()
	self:_log("hot reload applied")
end

function SMP:compile()
	assert(self._running, "[SMP] machine has been destroyed.")
	self:_syncIds()
	if not self._cacheValid then self:_buildCache() end
	self._matrix = {}
	for name, def in pairs(self._states) do
		local entries = {}
		for _, t in ipairs(self._transCache[name] or {}) do
			local leaf = self:_resolveLeaf(t.target)
			if self._states[leaf] then
				table.insert(entries, { guard = t.guard, target = leaf, label = t.label })
			end
		end
		self._matrix[def.id] = entries
	end
	self._compiled = true
	self:_log(("compiled %d states"):format(self._idCounter.n))
end

function SMP:validate(): { ValidationError }
	local errors: { ValidationError } = {}
	for name, def in pairs(self._states) do
		for _, t in ipairs(def.transitions) do
			if not self._states[self:_resolveLeaf(t.target)] then
				table.insert(errors, { state = name, target = t.target, reason = "target does not exist" })
			end
		end
		if def.timeoutNext and not self._states[self:_resolveLeaf(def.timeoutNext)] then
			table.insert(errors, { state = name, target = def.timeoutNext, reason = "timeoutNext does not exist" })
		end
		if def.initial and not self._states[def.initial] then
			table.insert(errors, { state = name, target = def.initial, reason = "initial sub-state does not exist" })
		end
	end
	for _, e in ipairs(errors) do
		warn(("[SMP:validate] '%s' → '%s': %s"):format(e.state, e.target, e.reason))
	end
	return errors
end

function SMP:analyze(): AnalysisResult
	assert(self._running, "[SMP] machine has been destroyed.")
	local reachable = {}
	local function dfs(name)
		if reachable[name] then return end
		reachable[name] = true
		local def = self._states[name]
		if not def then return end
		for _, t in ipairs(def.transitions)  do dfs(self:_resolveLeaf(t.target)) end
		if def.timeoutNext                    then dfs(self:_resolveLeaf(def.timeoutNext)) end
		for _, h in pairs(def.on)            do if type(h) == "string" then dfs(self:_resolveLeaf(h)) end end
	end
	dfs(self:_resolveLeaf(self._rawInitial))

	local unreachable, deadEnds = {}, {}
	for name, def in pairs(self._states) do
		if not reachable[name] then
			table.insert(unreachable, name)
		elseif not def.initial and #def.transitions == 0 and not def.timeoutNext and not next(def.on) then
			table.insert(deadEnds, name)
		end
	end

	local loops, onStack, visited, path = {}, {}, {}, {}
	local function dfsLoop(name)
		if visited[name] then return end
		visited[name] = true
		onStack[name] = true
		table.insert(path, name)
		local def = self._states[name]
		if def then
			local targets = {}
			for _, t in ipairs(def.transitions) do
				table.insert(targets, self:_resolveLeaf(t.target))
			end
			if def.timeoutNext then
				table.insert(targets, self:_resolveLeaf(def.timeoutNext))
			end
			for _, h in pairs(def.on) do
				if type(h) == "string" then table.insert(targets, self:_resolveLeaf(h)) end
			end
			for _, leaf in ipairs(targets) do
				if onStack[leaf] then
					local loop = {}
					for i = #path, 1, -1 do
						table.insert(loop, 1, path[i])
						if path[i] == leaf then break end
					end
					table.insert(loops, loop)
				elseif not visited[leaf] then
					dfsLoop(leaf)
				end
			end
		end
		table.remove(path)
		onStack[name] = false
	end
	dfsLoop(self:_resolveLeaf(self._rawInitial))

	table.sort(unreachable)
	table.sort(deadEnds)
	if #unreachable > 0 then
		warn(("[SMP:analyze] unreachable: %s"):format(table.concat(unreachable, ", ")))
	end
	for _, loop in ipairs(loops) do
		warn(("[SMP:analyze] loop: %s"):format(table.concat(loop, " → ")))
	end
	return { unreachable = unreachable, deadEnds = deadEnds, loops = loops }
end

function SMP:optimize(): { [string]: number }
	assert(self._running, "[SMP] machine has been destroyed.")
	local result = self:analyze()
	local removed, dead, dedup, folded = 0, 0, 0, 0
	for _, name in ipairs(result.unreachable) do
		self._states[name] = nil
		removed += 1
	end
	for _, def in pairs(self._states) do
		local seen, clean = {}, {}
		for _, t in ipairs(def.transitions) do
			if t.guard == false then
				dead += 1
			else
				local key = t.target .. "|" .. tostring(t.priority or 0)
				if not seen[key] then
					seen[key] = t
					table.insert(clean, t)
				else
					local ex = seen[key]
					if type(ex.guard) == "function" and type(t.guard) == "function" then
						local a, b = ex.guard, t.guard
						ex.guard = function(f, to, ctx) return a(f, to, ctx) or b(f, to, ctx) end
						ex.label = (ex.label or t.target) .. "|merged"
						folded += 1
					else
						dedup += 1
					end
				end
			end
		end
		def.transitions = clean
	end
	self:_invalidate()
	self:_log(("optimize: -%d states -%d dead -%d dup +%d folded"):format(removed, dead, dedup, folded))
	return { removedStates = removed, deadBranches = dead, removedTransitions = dedup, foldedGuards = folded }
end

-- Core transition executor. Implements proper HSM LCA-based exit/enter.
-- Exit chain: walk up from `prev` stopping at (not entering) the LCA.
-- Enter chain: walk down from just below LCA to `resolved`.
-- Self-transition: _lca returns parent, so prev.onExit and resolved.onEnter both fire.
-- Cross-root transition (no LCA): _lca returns nil, full exit then full enter.
function SMP:_executeTransition(target: string, reason: string?): boolean
	local resolved  = self:_resolveLeaf(target)
	local targetDef = self._states[resolved]
	if not targetDef then
		warn(("[SMP] _executeTransition: state '%s' not found"):format(resolved))
		return false
	end
	local prev    = self._current
	local prevDef = self._states[prev]
	local why     = reason or "manual"

	self:_log(("'%s'[%d] → '%s'[%d] [%s]"):format(
		prev, prevDef and prevDef.id or 0,
		resolved, targetDef.id, why))

	for _, hook in ipairs(self._beforeHooks) do
		local ok, r = pcall(hook, prev, resolved, self._context)
		if ok and r == false then
			self:_log("CANCELLED by beforeHook")
			return false
		end
	end

	local lca = self:_lca(prev, resolved)

	-- Exit: walk up from prev, stop before lca (exclusive).
	local exit = prev
	while exit and exit ~= lca do
		local def = self._states[exit]
		if not def then break end
		if def.onExit then
			local ok, err = pcall(def.onExit, self._context, prev)
			if not ok then warn(("[SMP] onExit '%s': %s"):format(exit, err)) end
		end
		exit = def.parent and self._states[def.parent] and def.parent or nil
	end

	local rawNow   = self:_rawNow()
	local prevProf = self._profile[prev]
	if prevProf then prevProf.totalTime += rawNow - prevProf.lastEnter end

	self._prevCtxSnap = shallowCopy(self._context)
	self._previous    = prev
	self._previousId  = prevDef and prevDef.id
	self._current     = resolved
	self._currentId   = targetDef.id
	self._stateStart  = rawNow
	table.insert(self._history, resolved)

	if not self._profile[resolved] then
		self._profile[resolved] = { totalTime = 0, enterCount = 0, lastEnter = rawNow }
	end
	local prof = self._profile[resolved]
	prof.enterCount += 1
	prof.lastEnter   = rawNow

	if self._replayEnabled then
		local t = self._deterministic and self._detTick or (rawNow - self._wallStart)
		table.insert(self._replayLog, { time = t, from = prev, to = resolved, reason = why })
	end

	-- Enter: walk down chain from just below lca to resolved (inclusive).
	-- When lca == nil every state in the chain is entered.
	local chain   = self:_ancestorChain(resolved)
	local pastLca = (lca == nil) -- nil LCA means enter all
	for _, name in ipairs(chain) do
		if not pastLca then
			if name == lca then pastLca = true end
		else
			local def = self._states[name]
			if def and def.onEnter then
				local ok, err = pcall(def.onEnter, self._context, prev)
				if not ok then warn(("[SMP] onEnter '%s': %s"):format(name, err)) end
			end
		end
	end

	local list = self._listeners[resolved]
	if list then for _, cb in ipairs(list) do pcall(cb, self._context, prev) end end
	for _, cb   in ipairs(self._globalCbs)  do pcall(cb, prev, resolved, self._context) end
	for _, hook in ipairs(self._afterHooks) do pcall(hook, prev, resolved, self._context) end
	return true
end

function SMP:canTransitionTo(target: string): boolean
	assert(self._running, "[SMP] machine has been destroyed.")
	local leaf = self:_resolveLeaf(target)
	if self._compiled then
		local entries = self._matrix[self._currentId]
		if not entries then return false end
		for _, e in ipairs(entries) do
			if e.target == leaf then
				return self:_resolveGuard(e.guard, self._current, leaf)
			end
		end
		return false
	end
	if not self._cacheValid then self:_buildCache() end
	for _, t in ipairs(self._transCache[self._current] or {}) do
		if t.target == target or self:_resolveLeaf(t.target) == leaf then
			return self:_resolveGuard(t.guard, self._current, t.target)
		end
	end
	return false
end

function SMP:transition(target: string): boolean
	assert(self._running, "[SMP] machine has been destroyed.")
	assert(type(target) == "string" and #target > 0, "[SMP] target must be a non-empty string.")
	assert(self._states[self:_resolveLeaf(target)],
		("[SMP] state '%s' does not exist."):format(target))
	if self._paused or self._locked then
		self:_log(("BLOCKED p=%s l=%s → '%s'"):format(
			tostring(self._paused), tostring(self._locked), target))
		return false
	end
	if not self:canTransitionTo(target) then
		self:_log(("DENIED '%s' → '%s'"):format(self._current, target))
		return false
	end
	return self:_executeTransition(target, "manual")
end

function SMP:forceTransition(target: string)
	assert(self._running, "[SMP] machine has been destroyed.")
	assert(type(target) == "string" and #target > 0, "[SMP] target must be a non-empty string.")
	assert(self._states[self:_resolveLeaf(target)],
		("[SMP] state '%s' does not exist."):format(target))
	self:_executeTransition(target, "forced")
end

function SMP:push(target: string)
	assert(self._running, "[SMP] machine has been destroyed.")
	assert(not self._paused and not self._locked, "[SMP] cannot push while paused or locked.")
	assert(#self._stack < self._maxStackDepth,
		("[SMP] stack limit (%d) reached."):format(self._maxStackDepth))
	assert(self._states[self:_resolveLeaf(target)],
		("[SMP] state '%s' does not exist."):format(target))
	table.insert(self._stack, self._current)
	self:_executeTransition(target, "push")
end

function SMP:pop(): boolean
	assert(self._running, "[SMP] machine has been destroyed.")
	if #self._stack == 0 then return false end
	local restored = table.remove(self._stack)
	assert(self._states[restored],
		("[SMP] stacked state '%s' no longer exists."):format(restored))
	self:_executeTransition(restored, "pop")
	return true
end

function SMP:getStackDepth(): number
	return #self._stack
end

-- Event routing: capture (ancestors, root→parent) → target → bubble (parent→root).
-- Only capture handlers registered as "capture:EVENT_NAME" intercept before target.
-- A handler that runs but returns no state name does NOT block subsequent phases.
-- A handler that transitions returns (true, true), stopping further routing.
function SMP:_dispatchEvent(evName: string, payload: any?): boolean
	local function run(h: any, stateName: string, phase: string): (boolean, boolean)
		if type(h) == "string" then
			local leaf = self:_resolveLeaf(h)
			if self._states[leaf] then
				self:_executeTransition(h, phase .. evName)
				return true, true
			end
			return false, false
		elseif type(h) == "function" then
			local ok, r = pcall(h, self._context, payload)
			if not ok then
				warn(("[SMP] handler '%s'/%s: %s"):format(evName, stateName, r))
				return true, false
			end
			if type(r) == "string" and #r > 0 then
				local leaf = self:_resolveLeaf(r)
				if self._states[leaf] then
					self:_executeTransition(r, phase .. evName)
					return true, true
				end
			end
			return true, false
		end
		return false, false
	end

	-- Capture phase: ancestors from root down to (not including) current.
	local chain = self:_ancestorChain(self._current)
	for _, name in ipairs(chain) do
		if name ~= self._current then
			local def = self._states[name]
			local h   = def and def.on and def.on["capture:" .. evName]
			if h then
				local _, transitioned = run(h, name, "capture:")
				if transitioned then return true end
			end
		end
	end

	-- Target phase: current state.
	local def = self._states[self._current]
	local h   = def and def.on and def.on[evName]
	if h ~= nil then
		local ran, transitioned = run(h, self._current, "event:")
		if ran then return transitioned end
	end

	-- Bubble phase: walk up from parent to root.
	local cur  = def and def.parent
	local seen = {}
	while cur and not seen[cur] do
		seen[cur] = true
		local pdef = self._states[cur]
		if not pdef then break end
		local bh = pdef.on and pdef.on[evName]
		if bh ~= nil then
			local ran, transitioned = run(bh, cur, "bubble:")
			if ran then return transitioned end
		end
		cur = pdef.parent and self._states[pdef.parent] and pdef.parent or nil
	end
	return false
end

function SMP:send(evName: string, payload: any?, priority: number?)
	assert(self._running, "[SMP] machine has been destroyed.")
	assert(type(evName) == "string" and #evName > 0,
		"[SMP] eventName must be a non-empty string.")
	if self._paused then return end
	if self._inputLogEnabled then
		local t = self._deterministic and self._detTick or (os.clock() - self._wallStart)
		table.insert(self._inputLog, { tick = t, event = evName, payload = payload })
	end
	heapPush(self._evQueue, { name = evName, payload = payload }, priority or 0)
	if self._evProcessing then return end
	self._evProcessing = true
	local ev = heapPop(self._evQueue)
	while ev do
		if not self:_dispatchEvent(ev.name, ev.payload) then
			self:_log(("event '%s' unhandled in '%s'"):format(ev.name, self._current))
		end
		for _, rn in ipairs(self._regionOrder) do
			local r = self._regions[rn]
			if r and r._running then r:send(ev.name, ev.payload) end
		end
		ev = heapPop(self._evQueue)
	end
	self._evProcessing = false
end

function SMP:update()
	assert(self._running, "[SMP] machine has been destroyed.")
	if self._paused then return end
	local def = self._states[self._current]
	if not def then return end

	if def.timeout and def.timeoutNext then
		local nxt = def.timeoutNext
		if self:_elapsed(self._stateStart) >= def.timeout
			and nxt ~= self._current
			and self._states[self:_resolveLeaf(nxt)]
		then
			self:_executeTransition(nxt, ("timeout %.2fs"):format(def.timeout))
			return
		end
	end

	if not self._locked then
		local target, lbl = self:_evalTransitions()
		if target and self._states[self:_resolveLeaf(target)] then
			self:_executeTransition(target, lbl or "auto")
			return
		end
	end

	if def.onUpdate then
		local ok, err = pcall(def.onUpdate, self._context, self._previous)
		if not ok then warn(("[SMP] onUpdate '%s': %s"):format(self._current, err)) end
	end

	if self._parallelRegions and task then
		for _, rn in ipairs(self._regionOrder) do
			local r = self._regions[rn]
			if r and r._running and not r._paused then
				task.spawn(function() r:update() end)
			end
		end
	else
		for _, rn in ipairs(self._regionOrder) do
			local r = self._regions[rn]
			if r and r._running and not r._paused then r:update() end
		end
	end
end

function SMP:addRegion(name: string, machine: StateMachine): StateMachine
	assert(self._running, "[SMP] machine has been destroyed.")
	assert(type(name) == "string" and #name > 0, "[SMP] region name must be non-empty.")
	assert(type(machine) == "table",             "[SMP] machine must be a StateMachine.")
	if not self._regions[name] then table.insert(self._regionOrder, name) end
	self._regions[name] = machine
	return self
end

function SMP:removeRegion(name: string)
	assert(self._running, "[SMP] machine has been destroyed.")
	self._regions[name] = nil
	removeFirst(self._regionOrder, name)
end

function SMP:getRegion(name: string): StateMachine?
	return self._regions[name]
end

function SMP:getRegionStates(): { [string]: string }
	local r = {}
	for n, m in pairs(self._regions) do r[n] = m._current end
	return r
end

function SMP:setDebug(on: boolean)
	self._debug = on
end

function SMP:setMaxStackDepth(n: number)
	assert(type(n) == "number" and n > 0, "[SMP] maxStackDepth must be a positive number.")
	self._maxStackDepth = n
end

function SMP:setTimeScale(s: number)
	assert(type(s) == "number" and s >= 0, "[SMP] timeScale must be >= 0.")
	self._timeScale = s
end

function SMP:getTimeScale(): number
	return self._timeScale
end

function SMP:setParallelRegions(on: boolean)
	self._parallelRegions = on
end

function SMP:setDeterministic(on: boolean)
	self._deterministic = on
	self._detTick       = 0
end

function SMP:tickDeterministic(dt: number)
	assert(self._deterministic, "[SMP] not in deterministic mode.")
	assert(type(dt) == "number" and dt >= 0, "[SMP] dt must be >= 0.")
	self._detTick += dt
	self:update()
end

function SMP:serialize(): Snapshot
	assert(self._running, "[SMP] machine has been destroyed.")
	return {
		version           = VERSION,
		current           = self._current,
		previous          = self._previous,
		history           = deepCopy(self._history),
		stack             = deepCopy(self._stack),
		context           = deepCopy(self._context),
		replay            = deepCopy(self._replayLog),
		deterministicTick = self._deterministic and self._detTick or nil,
	}
end

function SMP:deserialize(snap: Snapshot)
	assert(self._running, "[SMP] machine has been destroyed.")
	assert(type(snap) == "table" and type(snap.current) == "string",
		"[SMP] invalid snapshot.")
	assert(self._states[snap.current],
		("[SMP] snapshot state '%s' not found."):format(snap.current))
	self._current     = snap.current
	self._previous    = snap.previous
	self._history     = deepCopy(snap.history or { snap.current })
	self._stack       = deepCopy(snap.stack   or {})
	self._context     = deepCopy(snap.context or {})
	self._prevCtxSnap = shallowCopy(self._context)
	self._replayLog   = deepCopy(snap.replay  or {})
	self._stateStart  = self:_rawNow()
	if snap.deterministicTick then self._detTick = snap.deterministicTick end
	self:_syncIds()
	self:_log(("deserialized → '%s'[%d]"):format(self._current, self._currentId))
end

function SMP:serializeDelta(): Delta
	assert(self._running, "[SMP] machine has been destroyed.")
	local diff = {}
	for k, v in pairs(self._context) do
		if self._prevCtxSnap[k] ~= v then diff[k] = v end
	end
	for k in pairs(self._prevCtxSnap) do
		if self._context[k] == nil then diff[k] = "__nil__" end
	end
	return {
		version  = VERSION,
		current  = self._current,
		previous = self._previous,
		context  = diff,
		tick     = self._detTick,
	}
end

function SMP:applyDelta(delta: Delta)
	assert(self._running, "[SMP] machine has been destroyed.")
	assert(type(delta) == "table" and type(delta.current) == "string",
		"[SMP] invalid delta.")
	local def = self._states[delta.current]
	if def and self._current ~= delta.current then
		self._previous   = self._current
		self._previousId = self._currentId
		self._current    = delta.current
		self._currentId  = def.id
		self._stateStart = self:_rawNow()
	end
	if delta.context then
		for k, v in pairs(delta.context) do
			self._context[k] = v ~= "__nil__" and v or nil
		end
		self._prevCtxSnap = shallowCopy(self._context)
	end
	if delta.tick then self._detTick = delta.tick end
	self:_log(("delta applied → '%s'"):format(self._current))
end

function SMP:enableInputLog()
	self._inputLogEnabled = true
	self._inputLog        = {}
end

function SMP:disableInputLog()
	self._inputLogEnabled = false
end

function SMP:getInputLog()
	return deepCopy(self._inputLog)
end

function SMP:replayInputLog(log: { any })
	assert(self._running,        "[SMP] machine has been destroyed.")
	assert(self._deterministic,  "[SMP] replayInputLog requires deterministic mode.")
	assert(type(log) == "table", "[SMP] log must be a table.")
	self:reset()
	local sorted = deepCopy(log)
	table.sort(sorted, function(a, b) return a.tick < b.tick end)
	local prev = 0
	for _, e in ipairs(sorted) do
		local dt = e.tick - prev
		if dt > 0 then self:tickDeterministic(dt) end
		self:send(e.event, e.payload)
		prev = e.tick
	end
end

function SMP:enableReplay()
	self._replayEnabled = true
	self._replayLog     = {}
	self._wallStart     = os.clock()
end

function SMP:disableReplay()
	self._replayEnabled = false
end

function SMP:getReplayLog(): { ReplayEvent }
	return deepCopy(self._replayLog)
end

function SMP:exportReplay(): string
	local lines = { "-- SMP Replay v" .. tostring(VERSION) }
	for _, e in ipairs(self._replayLog) do
		table.insert(lines, ("t=%.4f  %-24s → %-24s  [%s]"):format(
			e.time, e.from, e.to, e.reason))
	end
	return table.concat(lines, "\n")
end

function SMP:getProfile(): { [string]: ProfileEntry }
	local result = deepCopy(self._profile)
	local orig   = self._profile[self._current]
	local cur    = result[self._current]
	if cur and orig then
		cur.totalTime = orig.totalTime + (self:_rawNow() - orig.lastEnter)
	end
	return result
end

function SMP:printProfile()
	assert(self._running, "[SMP] machine has been destroyed.")
	local data, names = self:getProfile(), {}
	for n in pairs(data) do table.insert(names, n) end
	table.sort(names, function(a, b) return data[a].totalTime > data[b].totalTime end)
	print("[SMP] Profile:")
	for _, n in ipairs(names) do
		local e  = data[n]
		local id = self._states[n] and self._states[n].id or 0
		print(("  [%3d] %-28s  total:%7.4fs  visits:%3d  avg:%.4fs"):format(
			id, n, e.totalTime, e.enterCount,
			e.enterCount > 0 and e.totalTime / e.enterCount or 0))
	end
end

function SMP:getState(): string
	assert(self._running, "[SMP] machine has been destroyed.")
	return self._current
end

function SMP:getStateId(): number
	assert(self._running, "[SMP] machine has been destroyed.")
	return self._currentId
end

function SMP:getPreviousState(): string?
	assert(self._running, "[SMP] machine has been destroyed.")
	return self._previous
end

function SMP:getStateTime(): number
	assert(self._running, "[SMP] machine has been destroyed.")
	return self:_elapsed(self._stateStart)
end

function SMP:is(state: string): boolean
	if self._current == state then return true end
	local par = self._states[self._current] and self._states[self._current].parent
	while par do
		if par == state then return true end
		par = self._states[par] and self._states[par].parent or nil
	end
	return false
end

function SMP:isId(id: number): boolean
	return self._currentId == id
end

function SMP:isAny(...: string): boolean
	for i = 1, select("#", ...) do
		if self:is(select(i, ...)) then return true end
	end
	return false
end

function SMP:hasTag(tag: string): boolean
	assert(type(tag) == "string", "[SMP] tag must be a string.")
	local cur = self._current
	while cur do
		local def = self._states[cur]
		if not def then break end
		for _, t in ipairs(def.tags) do if t == tag then return true end end
		cur = def.parent and self._states[def.parent] and def.parent or nil
	end
	return false
end

function SMP:getTags(): { string }
	local seen, result = {}, {}
	local cur = self._current
	while cur do
		local def = self._states[cur]
		if not def then break end
		for _, t in ipairs(def.tags) do
			if not seen[t] then seen[t] = true; table.insert(result, t) end
		end
		cur = def.parent and self._states[def.parent] and def.parent or nil
	end
	return result
end

function SMP:getStatesWithTag(tag: string): { string }
	assert(type(tag) == "string", "[SMP] tag must be a string.")
	if not self._tagIdxValid then self:_buildTagIndex() end
	return deepCopy(self._tagIdx[tag] or {})
end

function SMP:isPaused(): boolean  return self._paused  end
function SMP:isLocked(): boolean  return self._locked  end
function SMP:pause()              self._paused = true   end
function SMP:resume()             self._paused = false  end
function SMP:lock()               self._locked = true   end
function SMP:unlock()             self._locked = false  end

function SMP:getContext(): any
	assert(self._running, "[SMP] machine has been destroyed.")
	return self._context
end

function SMP:setContext(key: string, value: any)
	assert(self._running, "[SMP] machine has been destroyed.")
	assert(type(key) == "string", "[SMP] key must be a string.")
	self._context[key] = value
end

function SMP:getHistory(limit: number?): { string }
	assert(self._running, "[SMP] machine has been destroyed.")
	if not limit then return deepCopy(self._history) end
	local result = {}
	for i = math.max(1, #self._history - limit + 1), #self._history do
		table.insert(result, self._history[i])
	end
	return result
end

function SMP:clearHistory()
	self._history = { self._current }
end

-- Reset the machine back to its initial state.
-- Correctly fires onExit for the current state chain, then onEnter for the initial.
-- After reset, _previous is nil (clean slate).
function SMP:reset()
	assert(self._running, "[SMP] machine has been destroyed.")
	local leaf = self:_resolveLeaf(self._rawInitial)
	assert(self._states[leaf] or leaf == self._rawInitial,
		("[SMP] initial state '%s' was never registered."):format(self._rawInitial))
	self._paused      = false
	self._locked      = false
	self._stack       = {}
	self._history     = {}
	self._prevCtxSnap = {}

	-- Exit the current state chain fully (no LCA — full exit).
	local exit = self._current
	while exit do
		local def = self._states[exit]
		if not def then break end
		if def.onExit then
			local ok, err = pcall(def.onExit, self._context, self._current)
			if not ok then warn(("[SMP] reset onExit '%s': %s"):format(exit, err)) end
		end
		exit = def.parent and self._states[def.parent] and def.parent or nil
	end

	local rawNow  = self:_rawNow()
	local prevStr = self._current

	self._previous    = nil
	self._previousId  = nil
	self._current     = self._rawInitial
	self._currentId   = self._states[self._rawInitial] and self._states[self._rawInitial].id or 0
	self._stateStart  = rawNow
	table.insert(self._history, self._rawInitial)

	if not self._profile[self._rawInitial] then
		self._profile[self._rawInitial] = { totalTime = 0, enterCount = 0, lastEnter = rawNow }
	end
	local prof = self._profile[self._rawInitial]
	prof.enterCount += 1
	prof.lastEnter   = rawNow

	-- Enter the initial state chain fully (no LCA — full enter).
	local chain = self:_ancestorChain(self._rawInitial)
	for _, name in ipairs(chain) do
		local def = self._states[name]
		if def and def.onEnter then
			local ok, err = pcall(def.onEnter, self._context, prevStr)
			if not ok then warn(("[SMP] reset onEnter '%s': %s"):format(name, err)) end
		end
	end

	local list = self._listeners[self._rawInitial]
	if list then for _, cb in ipairs(list) do pcall(cb, self._context, prevStr) end end
	for _, cb   in ipairs(self._globalCbs)  do pcall(cb, prevStr, self._rawInitial, self._context) end
	for _, hook in ipairs(self._afterHooks) do pcall(hook, prevStr, self._rawInitial, self._context) end
	self:_log(("reset → '%s'"):format(self._rawInitial))
end

function SMP:onEnterState(state: string, cb: StateCallback): () -> ()
	assert(type(state) == "string",    "[SMP] state must be a string.")
	assert(type(cb) == "function",     "[SMP] callback must be a function.")
	if not self._listeners[state] then self._listeners[state] = {} end
	table.insert(self._listeners[state], cb)
	return unsub(self._listeners[state], cb)
end

function SMP:onTransition(cb: HookCallback): () -> ()
	assert(type(cb) == "function", "[SMP] callback must be a function.")
	table.insert(self._globalCbs, cb)
	return unsub(self._globalCbs, cb)
end

function SMP:onBeforeTransition(cb: HookCallback): () -> ()
	assert(type(cb) == "function", "[SMP] callback must be a function.")
	table.insert(self._beforeHooks, cb)
	return unsub(self._beforeHooks, cb)
end

function SMP:onAfterTransition(cb: HookCallback): () -> ()
	assert(type(cb) == "function", "[SMP] callback must be a function.")
	table.insert(self._afterHooks, cb)
	return unsub(self._afterHooks, cb)
end

function SMP:printGraph()
	assert(self._running, "[SMP] machine has been destroyed.")
	local names = {}
	for n in pairs(self._states) do table.insert(names, n) end
	table.sort(names)
	print(("[SMP v%d] '%s'[%d]  states=%d  compiled=%s  ×%.1f  det=%s"):format(
		VERSION, self._current, self._currentId, #names,
		tostring(self._compiled), self._timeScale, tostring(self._deterministic)))
	print(string.rep("─", 64))
	for _, name in ipairs(names) do
		local def  = self._states[name]
		local mark = self:is(name) and "►" or " "
		local tags = #def.tags > 0 and (" [#%s]"):format(table.concat(def.tags, " #")) or ""
		local tout = def.timeout
			and (" ⏱%.2fs→%s"):format(def.timeout, def.timeoutNext or "?") or ""
		local par  = def.parent and (" ↑%s"):format(def.parent) or ""
		local evts = {}
		for ev in pairs(def.on) do table.insert(evts, ev) end
		local evs  = #evts > 0 and (" on:[%s]"):format(table.concat(evts, ",")) or ""
		print(("%s [%3d] %-28s%s%s%s%s"):format(mark, def.id, name, tags, tout, evs, par))
		for _, t in ipairs(def.transitions) do
			local g   = type(t.guard) == "function" and "guard"
				or (t.guard == false and "never" or "always")
			local p   = (t.priority or 0) ~= 0 and (" p%d"):format(t.priority) or ""
			local lbl = t.label and (' "%s"'):format(t.label) or ""
			local tid = self._states[t.target]
				and ("[%d]"):format(self._states[t.target].id) or "[?]"
			print(("    └─ [%s%s%s] → %s %s"):format(g, p, lbl, t.target, tid))
		end
	end
	print(string.rep("─", 64))
end

function SMP:exportGraph(): string
	assert(self._running, "[SMP] machine has been destroyed.")
	local lines, names = { "digraph SMP {", "  rankdir=LR;" }, {}
	for n in pairs(self._states) do table.insert(names, n) end
	table.sort(names)
	for _, name in ipairs(names) do
		local def   = self._states[name]
		local id    = name:gsub("[%.%s]", "_")
		local shape = self:is(name) and "doublecircle" or "circle"
		local tags  = #def.tags > 0
			and (" | #%s"):format(table.concat(def.tags, " #")) or ""
		table.insert(lines,
			('  %s [label="[%d] %s%s" shape=%s];'):format(id, def.id, name, tags, shape))
	end
	for _, name in ipairs(names) do
		local def  = self._states[name]
		local from = name:gsub("[%.%s]", "_")
		for _, t in ipairs(def.transitions) do
			local to  = self:_resolveLeaf(t.target):gsub("[%.%s]", "_")
			local p   = (t.priority or 0) ~= 0 and (" p%d"):format(t.priority) or ""
			local lbl = t.label or (type(t.guard) == "function" and "guard" or "always")
			table.insert(lines,
				('  %s -> %s [label="%s%s"];'):format(from, to, lbl, p))
		end
		for ev in pairs(def.on) do
			table.insert(lines,
				('  %s -> %s [label="on:%s" style=dashed color="#888888"];'):format(from, from, ev))
		end
	end
	table.insert(lines, "}")
	return table.concat(lines, "\n")
end

function SMP:exportEditorJSON(): string
	assert(self._running, "[SMP] machine has been destroyed.")
	local stateList, names = {}, {}
	for n in pairs(self._states) do table.insert(names, n) end
	table.sort(names)
	for _, name in ipairs(names) do
		local def = self._states[name]
		local ts  = {}
		for _, t in ipairs(def.transitions) do
			table.insert(ts, {
				target   = t.target,
				priority = t.priority or 0,
				label    = t.label or "",
				hasGuard = type(t.guard) == "function",
			})
		end
		local evts = {}
		for ev in pairs(def.on) do table.insert(evts, ev) end
		table.sort(evts)
		table.insert(stateList, {
			id          = def.id,
			name        = name,
			parent      = def.parent      or "",
			initial     = def.initial     or "",
			tags        = def.tags,
			timeout     = def.timeout     or 0,
			timeoutNext = def.timeoutNext or "",
			active      = self:is(name),
			transitions = ts,
			events      = evts,
		})
	end
	local regionList = {}
	for _, rn in ipairs(self._regionOrder) do
		local r = self._regions[rn]
		table.insert(regionList, { name = rn, current = r and r._current or "" })
	end
	return jsonEncode({
		version       = VERSION,
		current       = self._current,
		currentId     = self._currentId,
		timeScale     = self._timeScale,
		deterministic = self._deterministic,
		compiled      = self._compiled,
		states        = stateList,
		regions       = regionList,
	}, 1)
end

function SMP:exportDebugger(): string
	assert(self._running, "[SMP] machine has been destroyed.")
	local dot = self:exportGraph()
	local logLines = {}
	for _, l in ipairs(self._logBuf) do
		table.insert(logLines,
			l:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
	end
	local pRows, rRows, regRows = {}, {}, {}
	local prof, pNames = self:getProfile(), {}
	for n in pairs(prof) do table.insert(pNames, n) end
	table.sort(pNames, function(a, b) return prof[a].totalTime > prof[b].totalTime end)
	for _, n in ipairs(pNames) do
		local e  = prof[n]
		local id = self._states[n] and self._states[n].id or 0
		table.insert(pRows, ("<tr><td>[%d]</td><td>%s</td><td>%.4f</td><td>%d</td><td>%.4f</td></tr>"):format(
			id, n, e.totalTime, e.enterCount,
			e.enterCount > 0 and e.totalTime / e.enterCount or 0))
	end
	for _, e in ipairs(self._replayLog) do
		table.insert(rRows,
			("<tr><td>%.4f</td><td>%s</td><td>%s</td><td>%s</td></tr>"):format(
				e.time, e.from, e.to, e.reason))
	end
	for rn, r in pairs(self._regions) do
		if r._running then
			table.insert(regRows,
				("<tr><td>%s</td><td><b>%s</b>[%d]</td></tr>"):format(
					rn, r._current, r._currentId))
		end
	end
	local badges =
		'<span class="b">v' .. tostring(VERSION) .. '</span>' ..
		'<span class="b hi">' .. self._current ..
		'[' .. tostring(self._currentId) .. ']</span>' ..
		'<span class="b">&#x23F1;' .. ("%.2f"):format(self:getStateTime()) .. 's</span>' ..
		'<span class="b">&#xD7;' .. tostring(self._timeScale) .. '</span>' ..
		(self._compiled      and '<span class="b">compiled</span>'      or "") ..
		(self._deterministic and '<span class="b">deterministic</span>' or "")
	local dotEsc = dot
		:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;")
	local html = {
		'<!DOCTYPE html><html lang="en"><head><meta charset="UTF-8">',
		'<title>SMP Debugger</title>',
		'<script src="https://cdnjs.cloudflare.com/ajax/libs/viz.js/2.1.2/viz.js"></script>',
		'<script src="https://cdnjs.cloudflare.com/ajax/libs/viz.js/2.1.2/full.render.js"></script>',
		'<style>',
		'*{box-sizing:border-box;margin:0;padding:0}',
		'body{font-family:"Courier New",monospace;background:#0d0d0d;color:#e0e0e0;display:flex;flex-direction:column;height:100vh}',
		'header{background:#0f0f1e;padding:10px 18px;border-bottom:1px solid #222;display:flex;align-items:center;gap:10px;flex-wrap:wrap}',
		'h1{color:#00d4ff;font-size:14px;letter-spacing:2px;text-transform:uppercase}',
		'.b{background:#00d4ff14;border:1px solid #00d4ff33;color:#00d4ff;padding:2px 9px;border-radius:10px;font-size:11px}',
		'.b.hi{background:#00d4ff30;border-color:#00d4ff}',
		'.layout{display:grid;grid-template-columns:1fr 380px;flex:1;overflow:hidden}',
		'.graph{background:#0a0a0a;display:flex;align-items:center;justify-content:center;overflow:auto;padding:14px}',
		'.graph svg{max-width:100%;max-height:100%}',
		'.side{display:flex;flex-direction:column;border-left:1px solid #1a1a1a;overflow:hidden}',
		'.tabs{display:flex;background:#111;border-bottom:1px solid #1a1a1a}',
		'.tab{padding:7px 13px;cursor:pointer;font-size:11px;color:#555;border-bottom:2px solid transparent;transition:.12s}',
		'.tab:hover{color:#aaa}.tab.active{color:#00d4ff;border-bottom-color:#00d4ff}',
		'.pane{display:none;flex:1;overflow:auto;padding:10px}.pane.active{display:block}',
		'table{width:100%;border-collapse:collapse;font-size:11px}',
		'th{background:#111;padding:5px 8px;text-align:left;color:#00d4ff;font-weight:normal;position:sticky;top:0;z-index:1}',
		'td{padding:4px 8px;border-bottom:1px solid #141414}',
		'tr:hover td{background:#161616}',
		'.log{font-size:10px;line-height:1.8;color:#777;white-space:pre-wrap;word-break:break-all}',
		'.dn{display:none}',
		'</style></head><body>',
		'<header><h1>StateMachinePlus</h1>' .. badges .. '</header>',
		'<div class="layout">',
		'<div class="graph" id="graph"></div>',
		'<div class="side">',
		'<div class="tabs">',
		'<div class="tab active" onclick="show(\'profile\')">Profile</div>',
		'<div class="tab" onclick="show(\'replay\')">Replay</div>',
		'<div class="tab" onclick="show(\'regions\')">Regions</div>',
		'<div class="tab" onclick="show(\'log\')">Log</div>',
		'</div>',
		'<div class="pane active" id="pane-profile">',
		'<table><thead><tr><th>ID</th><th>State</th><th>Total</th><th>Visits</th><th>Avg</th></tr></thead>',
		'<tbody>' .. table.concat(pRows) .. '</tbody></table></div>',
		'<div class="pane" id="pane-replay">',
		'<table><thead><tr><th>t</th><th>From</th><th>To</th><th>Reason</th></tr></thead>',
		'<tbody>' .. table.concat(rRows) .. '</tbody></table></div>',
		'<div class="pane" id="pane-regions">',
		'<table><thead><tr><th>Region</th><th>State</th></tr></thead>',
		'<tbody>' .. table.concat(regRows) .. '</tbody></table></div>',
		'<div class="pane" id="pane-log">',
		'<div class="log">' .. table.concat(logLines, "\n") .. '</div></div>',
		'</div></div>',
		'<div class="dn" id="dot">' .. dotEsc .. '</div>',
		'<script>',
		'function show(id) {',
		'  document.querySelectorAll(".tab,.pane").forEach(function(e) {',
		'    e.classList.remove("active");',
		'  });',
		'  var tab = document.querySelector("[onclick=\'show(\\\'" + id + "\\\')\']");',
		'  if (tab) tab.classList.add("active");',
		'  var pane = document.getElementById("pane-" + id);',
		'  if (pane) pane.classList.add("active");',
		'}',
		'var raw = document.getElementById("dot").textContent',
		'  .replace(/&amp;/g, "&").replace(/&lt;/g, "<").replace(/&gt;/g, ">");',
		'new Viz().renderSVGElement(raw)',
		'  .then(function(svg) { document.getElementById("graph").appendChild(svg); })',
		'  .catch(function(e)  { document.getElementById("graph").textContent = "" + e; });',
		'</script></body></html>',
	}
	return table.concat(html, "\n")
end

function SMP:destroy()
	assert(self._running, "[SMP] machine is already destroyed.")
	for _, r in pairs(self._regions) do
		if r._running then r:destroy() end
	end
	self._running       = false
	self._states        = {}
	self._matrix        = {}
	self._dtrees        = {}
	self._transCache    = {}
	self._tagIdx        = {}
	self._listeners     = {}
	self._globalCbs     = {}
	self._beforeHooks   = {}
	self._afterHooks    = {}
	self._history       = {}
	self._stack         = {}
	self._context       = {}
	self._prevCtxSnap   = {}
	self._replayLog     = {}
	self._inputLog      = {}
	self._profile       = {}
	self._evQueue       = {}
	self._regions       = {}
	self._regionOrder   = {}
	self._logBuf        = {}
end

function SMP:__tostring(): string
	local n = 0
	for _ in pairs(self._states) do n += 1 end
	return ("[SMP v%d | '%s'[%d] | prev:'%s' | states:%d | t:%.2fs | stack:%d | regions:%d | ×%.1f | compiled:%s | det:%s]"):format(
		VERSION, self._current, self._currentId, self._previous or "nil",
		n, self:getStateTime(), #self._stack, #self._regionOrder,
		self._timeScale, tostring(self._compiled), tostring(self._deterministic))
end

local MachineGroup   = {}
MachineGroup.__index = MachineGroup

function MachineGroup.new(): MachineGroupType
	return setmetatable({ _machines = {}, _order = {} }, MachineGroup)
end

function MachineGroup:addMachine(name: string, machine: StateMachine): MachineGroupType
	assert(type(name) == "string" and #name > 0,
		"[MG] name must be a non-empty string.")
	assert(type(machine) == "table",
		"[MG] machine must be a StateMachine.")
	if not self._machines[name] then table.insert(self._order, name) end
	self._machines[name] = machine
	return self
end

function MachineGroup:removeMachine(name: string)
	self._machines[name] = nil
	removeFirst(self._order, name)
end

function MachineGroup:getMachine(name: string): StateMachine?
	return self._machines[name]
end

function MachineGroup:updateAll()
	for _, n in ipairs(self._order) do
		local m = self._machines[n]
		if m and m._running then m:update() end
	end
end

function MachineGroup:send(evName: string, payload: any?, priority: number?)
	for _, n in ipairs(self._order) do
		local m = self._machines[n]
		if m and m._running then m:send(evName, payload, priority) end
	end
end

function MachineGroup:serializeAll(): { [string]: Snapshot }
	local r = {}
	for _, n in ipairs(self._order) do
		local m = self._machines[n]
		if m and m._running then r[n] = m:serialize() end
	end
	return r
end

function MachineGroup:deltaAll(): { [string]: Delta }
	local r = {}
	for _, n in ipairs(self._order) do
		local m = self._machines[n]
		if m and m._running then r[n] = m:serializeDelta() end
	end
	return r
end

function MachineGroup:pauseAll()
	for _, n in ipairs(self._order) do
		local m = self._machines[n]
		if m and m._running then m:pause() end
	end
end

function MachineGroup:resumeAll()
	for _, n in ipairs(self._order) do
		local m = self._machines[n]
		if m and m._running then m:resume() end
	end
end

function MachineGroup:destroyAll()
	for _, n in ipairs(self._order) do
		local m = self._machines[n]
		if m and m._running then m:destroy() end
	end
	self._machines = {}
	self._order    = {}
end

function MachineGroup:printAll()
	print("[MachineGroup]")
	for _, n in ipairs(self._order) do
		print(("  %-16s %s"):format(n, tostring(self._machines[n])))
	end
end

local DataLoader = {}

function DataLoader.load(data: { [string]: any }): { [string]: StateDefinition }
	assert(type(data) == "table", "[DataLoader] data must be a table.")
	local function build(raw: any): StateDefinition
		assert(type(raw) == "table", "[DataLoader] state definition must be a table.")
		local def: StateDefinition = {
			tags        = raw.tags,
			timeout     = raw.timeout,
			timeoutNext = raw.timeoutNext,
			initial     = raw.initial,
			on          = raw.on,
		}
		if raw.transitions then
			local ts = {}
			for _, t in ipairs(raw.transitions) do
				assert(type(t.target) == "string",
					"[DataLoader] transition.target must be a string.")
				table.insert(ts, {
					target   = t.target,
					guard    = t.guard,
					priority = t.priority,
					label    = t.label,
				})
			end
			def.transitions = ts
		end
		if raw.states then
			def.states = {}
			for childName, childRaw in pairs(raw.states) do
				def.states[childName] = build(childRaw)
			end
		end
		return def
	end
	local result = {}
	for name, raw in pairs(data) do result[name] = build(raw) end
	return result
end

return {
	new          = SMP.new,
	MachineGroup = MachineGroup,
	DataLoader   = DataLoader,
}
