----------------------------------------------------------
--                     xCodea
-- a live execution environment for large Codea projects
----------------------------------------------------------


xCodea = {}
local xc = {} -- #xc

---@function make_sandbox [parent=#xc]
--@param #string i the last tab that got sandboxed (or nil)
--@return #boolean true if all tabs were sandboxed correctly
function xc.make_sandbox()
	local tab = xc.to_sandbox[1]
	if not tab then
		xc.hijack_update()
		if xc.sandbox_started then return true end
		return xc.start_sandbox()
	end
	table.remove(xc.to_sandbox,1)
	xc.vlog('Running eval for tab '..tab)
	-- FIXME xCodea:Main below is never received (stack overflow!)
	if xc.eval(readProjectTab(tab),'::'..tab) then
		return xc.make_sandbox(tab)
	end
end


function xc.start_sandbox()
	xc.xlog('Running setup()')
	local success = xpcall(xCodea._SANDBOX.setup,xc.error_handler)
	if success then
		xc.sandbox_started = true
		xc.xlog('Starting sandbox!')
		return xc.run_sandbox()
	end
end

function xc.hijack_update()
	if xCodea._SANDBOX.update then
		if not xc.draw_original then xc.draw_original = xCodea._SANDBOX.draw end
		local found = xc.find_update_hook(xc.draw_original)
		if found then
			xc.vlog('Found update() hook')
			local success = loadstring(found,'>>[xCodea]')
			if success then
				setfenv(success,xCodea._SANDBOX)
				success = xpcall(success,xc.error_handler)
				if success then
					xc.vlog('update() hook successfully hijacked')
					xc.has_update_hook = true
				end
			end
		end
	end
end

function xc.find_update_hook(m)
	--	local m = xCodea._SANDBOX.draw
	local result = ''
	repeat
		print('Searching for',tostring(m)..'()')
		local target = type(m)=='function' and m or xCodea._SANDBOX[m]
		if not target then
			print("DRAMA!")
			return
		end
		local info = debug.getinfo(target)
		if not info then print('NOT FOUND!')return end
		local tab =	info.source:sub(3,-1)
		print('Found in',tab)
		if tab=='[xCodea]' then return end
		local source_tab = readProjectTab(tab)
		local source_arr = xc.splitstring(source_tab,'\n')
		local chunk = table.concat(source_arr,'\n',info.linedefined,info.lastlinedefined) -- #string
		result = chunk:gsub('\n','__NEWLINE_XC_'):gsub('%s+',' ')
		chunk = chunk:gsub('%s+','')
		-- it can be: draw = function() XXXXX()
		-- or         function draw() XXXXXX()
		m = chunk:match('..-=.-function%(%)(.-)%(%)') or chunk:match('function..-%(%)(.-)%(%)')
		print('It calls',m)
		local upn = nil local upv = nil local i = 1
		repeat
			upn,upv = debug.getupvalue(target,i)
			--			print(upn,upv)
			i = i + 1
		until upn == m or not upn
		if upn then print(upn..' is an upvalue:',upv) m=upv end
	until m == 'update' or not m
	if not m then print('update() not found') return end
	return result:gsub('__NEWLINE_XC_','\n'):gsub('update%(%)','')
		-- result is "function last_draw_in_chain() --update() is snipped .... end"
end

function xc.run_sandbox()
	-- <OLD> these used to be wrapped in: if xCodea._SANDBOX.draw ~= _G.draw then
	-- having them declared in the sandbox a priori makes it unnecessary
	-- but i'm keeping the reference, you never know</OLD>
	-- brought them back and removed declarations from sandbox as it could break some
	-- 'creative' ways to hijack them from dependencies
	draw = function()
		xc._update_callbacks()
		xpcall(function()xc._tween_update(DeltaTime)end,xc.tween_error_handler)

		-- TODO
		if xc.has_update_hook then
			xpcall(xCodea._SANDBOX.update,xc.error_handler)
		end
		if xCodea._SANDBOX.draw and xCodea._SANDBOX.draw ~= _G.draw then
			xpcall(xCodea._SANDBOX.draw,xc.error_handler)
		end
	end
	touched = function(touch)
		if xCodea._SANDBOX.touched and xCodea._SANDBOX.touched ~= _G.touched then
			xpcall(function() xCodea._SANDBOX.touched(touch) end, xc.error_handler)
		end
	end
	--	print(_G.touched,xCodea._SANDBOX.touched,rawget(xCodea._SANDBOX,touched))
	keyboard = function(key)
		if xCodea._SANDBOX.keyboard and xCodea._SANDBOX.keyboard ~= _G.keyboard then
			xpcall(function() xCodea._SANDBOX.keyboard(key) end, xc.error_handler)
		end
	end
	orientationChanged = function(newOrientation)
		if xCodea._SANDBOX.orientationChanged and xCodea._SANDBOX.orientationChanged ~= _G.orientationChanged then
			xpcall(function() xCodea._SANDBOX.orientationChanged(newOrientation) end, xc.error_handler)
		end
	end
	collide = function(contact)
		if xCodea._SANDBOX.collide and xCodea._SANDBOX.collide ~= _G.collide then
			xpcall(function() xCodea._SANDBOX.collide(contact) end, xc.error_handler)
		end
	end
	--	if xc.pending_tween then
	--		local success = pcall(tween.play,xc.pending_tween)
	--		if success then xc.pending_tween = nil else tween.stop(xc.pending_tween)end
	--	end
	xc.vlog('Sandbox (re)started')
	return true
end
function xc.pretty_print(...)
	local n = select('#',...)
	if n==0 then return 'nil' end
	local resp = {}
	for i=1, n do
		local arg = select(i,...)
		if type(arg)~='table' then table.insert(resp,tostring(arg))
		else
			local t = {'{'}
			for k, v in pairs(arg) do
				table.insert(t,'  '..tostring(k)..': '..tostring(v))
			end
			table.insert(t,'}')
			table.insert(resp,table.concat(t,'\n'))
		end
	end
	return table.concat(resp,', ')
end
function xc.eval(code,name,log)
	xc.vlog('Eval: '..name)
	--	if code=='restart()' then loadstring(code)() end
	--env = env or xCodea._SANDBOX
	local success, error, is_repl
	if log then
		success, error = loadstring('return '..code,name)
		if success then is_repl = true end
	end
	if not success then success,error = loadstring(code,name) end
	if not success then
		xc.vlog('error in loadstring()')
		return xc.sandbox_error(error,false)
	end
	if code:match "^%s*(.-)%s*$"~='xCodea.restart()' then setfenv(success,xCodea._SANDBOX) end
	local results = {xpcall(success, xc.error_handler)}
	success = results[1]
	--setfenv(1,_G) -- FIXME test??
	if success then
		if is_repl then
			--			return xc.log('[eval] '..name..' => '..	xc.pretty_print(results[2]),unpack(results,2))
			xc.log('[eval] '..name..' => '..xc.pretty_print(unpack(results,2)))
		end
		xc.error = nil
		return xc.sandbox_started and xc.run_sandbox() or true
	end
end


function xc.sandbox_error(err,is_runtime)
	--tween.stop(xc.tween)
	xc.log_error(err,is_runtime)
	draw = function()
		xc._update_callbacks()
		pcall(function()xc._tween_update(DeltaTime)end)
		-- TODO
		if xc.has_update_hook then
			pcall(xCodea._SANDBOX.update)
		end
		if xCodea._SANDBOX.draw ~= _G.draw then
			local success,err = pcall(xCodea._SANDBOX.draw)
			if not success then background(40) end
		else
			background(40)
		end
		resetStyle() resetMatrix()
		xc.draw_status()
	end
end

function xc.tween_error_handler(err)
	local lvl=2 local info=nil
	repeat
		lvl = lvl + 1
		info = debug.getinfo(lvl)
	until lvl == 20 or not info or info.name=='finishTween'
	if info then
		local name1,tweenid = debug.getlocal(lvl,1)
		tweenid.callback = nil
		--		xc.pending_tween = tweenid
		tween.stop(tweenid)
	else
		tween.stopAll()
	end
	err=err..debug.traceback('',3):gsub('%[C%]:.*','')
	xc.sandbox_error(err,true)
end

function xc.error_handler(err)
	err=err..debug.traceback('',3):gsub('%[C%]:.*','')
	xc.sandbox_error(err,true)
end


function xc.draw_status()
	pushStyle()
	noStroke()
	if xc.error then fill(255,0,0,60) rect(0,0,WIDTH,HEIGHT) end
	textMode(CORNER)
	rectMode(CORNERS)
	textAlign(LEFT)
	fontSize(18)
	textWrapWidth(WIDTH-80)
	local h = 0
	if xc.error then
		_,h=textSize(xc.error)
		h = h + 40
		fill(0,200)
		rect(20,20,WIDTH-20,20+h)
		fill(255,50,50,255)
		text(xc.error,40,40)
	end
	fill(160)
	if not xc.status_blink or math.floor(ElapsedTime*2) % 4 ~= 0 then
		for k,v in ipairs(xc.status) do
			local r = #xc.status-k
			fill(200,470-r*15)
			text(v,40,r*20+40+h)
		end
	end
	textMode(CENTER)
	fill(200,240,255)
	fontSize(80)
	text('xCodea',WIDTH/2,HEIGHT-40)
	popStyle()
end

function xc.null() end

function xc.log_error(s,is_sandbox)
	xc.error = xc.error or s
	s='[client] '..(is_sandbox and 'runtime 'or 'syntax ')..'error: '..s -- BASIC yeah! :)
	print(s)
	http.request(xCodea_server..'/error',xc.null,xc.null,{method='POST',data=s})
end

function xc.fatal_error(s)
	xc.log_error(s)
	xc.try_connect = function()end
end

function xc.log(...)
	print(...)
	local sarg = {}
	for i = 1, select('#', ...) do
		local v = select(i, ...)
		table.insert(sarg, tostring(v))
	end
	if #sarg>0 then xc.log_buffer = xc.log_buffer..table.concat(sarg,' ')..'\n' end
	--	tween.stop(xc.ltween)
	if #xc.log_buffer>100 then
		xc.send_log()
	elseif #xc.log_buffer>2 then
		xc.register_callback(0.2,xc.send_log)
		--		xc.ltween=tween.delay(0.2,xc.send_log)
	end
end

---@field [parent=#xc] #string log_buffer desc
function xc.send_log()
	http.request(xCodea_server..'/log',xc.null,xc.null,{method='POST',data=xc.log_buffer:sub(1,-2)})
	xc.log_buffer=''
end

function xc.xlog(s)
	table.insert(xc.status,s)
	if #xc.status>30 then table.remove(xc.status,1) end
	s = '[client] '..s
	print(s)
	http.request(xCodea_server..'/msg',xc.null,xc.null,{method='POST',data=s})
end

function xc.vlog(s)
	if xc.verbose then return xc.xlog(s) end
	print('[client] '..s)
end

function xc.try_connect()
	draw = function()
		xc._update_callbacks()
		--		xc._tween_update(DeltaTime)
		background(40)
		xc.draw_status()
	end
	if xCodea_server =='http://IP_ADDR_OR_HOSTNAME_HERE:49374' then
		return xc.fatal_error('Please enter the server\'s IP address in tab EDIT_THIS')
	end
	table.insert(xc.status,'Connecting to '..xCodea_server)
	xc.status_blink=true

	local function not_connected()
		xc.error = 'Cannot connect!'
		--		xc.tween = tween.delay(xc.polling_interval,xc.try_connect)
		xc.register_callback(xc.polling_interval,xc.try_connect)
	end
	http.request(xCodea_server..'/connect',xc.connected,not_connected)
end

function xc.connection_error(err)
	xc.error = 'Connection error! '..(err or '')
	print(xc.error)
	-- do nothing, must restart manually
end


function xc.connected(data,status,headers)
	if status~=200 then
		xc.log_error('Received status '..status)
		--		xc.tween = tween.delay(xc.polling_interval,xc.try_connect)
		xc.register_callback(xc.polling_interval,xc.try_connect)
		return
	end
	for k,v in pairs(headers) do
	--		xc.vlog('hdr: '..k..'='..v)
	end

	local proj=headers['project']
	if not proj or #proj==0 then
		xc.fatal_error('Invalid data received! (missing project)')
		return
	end
	local i = xc.InfoPlist(proj)
	if not i:exists() then
		xc.fatal_error('Project "'..proj..'" does not exist in Codea! '..
			'Please restart the xCodea server with an appropriate project.\n'..
			'Or, if you want to work on a new project, remember that xCodea cannot '..
			'create new projects in Codea, so you must do it manually. '..
			'You can then reconnect to the xCodea server.')
		return
	end
	xc.status_blink=nil
	xc.xlog('Connected. Syncing files')
	xc.project = proj
	xc.error = nil
	xc.polling_interval = tonumber(headers['polling']) or 1
	xc.remote_logging = headers['logging']
	xc.verbose = headers['verbose']
	xc.remote_watches = headers['watches'] --TODO
	xc.remote_pull = headers['pull']
	xc.remote_push = headers['push']
	--- injections
	if xc.remote_logging then
		xCodea._SANDBOX.print = function(...) xc.log(...) end
	end

	xc.projects = i:getDependencies()
	local localdeps = table.concat(xc.projects,':')
	table.insert(xc.projects,xc.project)

	local remotefiles = {}
	for file,chk in string.gmatch(headers['source'] or '','(.-:.-):(.-):') do
		remotefiles[file] = chk
	end

	local remotedeps = {}
	for dep in ((headers['dependencies'] or '')..':'):gmatch('(..-):') do
		local i=xc.InfoPlist(dep)
		if not i:exists() then
			xc.fatal_error('Dependency "'..dep..'" that was received\n'..
				'from the server does not exist in Codea!\n'..
				'xCodea cannot create new projects in Codea, so you must do it manually.\n'..
				'You can then reconnect to the xCodea server.')
			return
		end
		table.insert(remotedeps,dep)
	end

	if xc.remote_pull then xc.xlog('Pull request from server. Remote files will be overwritten.')
	elseif xc.remote_push then
		xc.xlog('Push request from server. Local files will be overwritten.')
		local i=xc.InfoPlist(xc.project)
		i:setDependencies(remotedeps)
		return xc.poll()
	end

	-- remove files from old server-side deps from remotefiles, or they'll get deleted on the server
	-- (if i remove a dep in codea, it doesn't mean i want its files nuked on the server)
	local remotedepsdict = xc.array2dict(remotedeps)
	for _,v in pairs(xc.projects) do
		remotedepsdict[v] = nil
	end
	for v,_ in pairs(remotefiles) do
		local elproj = string.sub(v,1,string.find(v,':')-1)
		if remotedepsdict[elproj] then remotefiles[v] = nil xc.vlog('File '..v..' belongs to a removed dependency, ignoring') end
	end

	-- determine files to send (changed locally wrt server known files)
	local sendfiles={}
	for _,proj in pairs(xc.projects) do
		local pfiles = listProjectTabs(proj)
		for _,pfile in pairs(pfiles) do
			local file = proj..':'..pfile
			if proj==xc.project or pfile~='Main' then table.insert(xc.to_sandbox,file) end
			local chk = xc.adler32(readProjectTab(file))
			if chk ~= remotefiles[file] then
				sendfiles[file] = true
			end
			remotefiles[file] = nil -- don't delete the file right before we send the update :)
		end
	end


	local function send_files(i)
		local file = next(sendfiles,i)
		if not file then
			if xc.remote_pull then
				http.request(xCodea_server..'/done',xc.null,xc.null)
				return xc.fatal_error('Operation completed.')
			end
			return xc.poll()
		end -- done sending tabs

		xc.xlog('Sending file '..file)
		local data = readProjectTab(file)
		local function success(responsedata,status,headers)
			if status ~= 200 then xc.log_error('Received status '..status) return end
			send_files(file)
		end
		http.request(xCodea_server..'/file', success, xc.connection_error,
			{method = 'POST', headers={project=xc.project,file=file,ftype='source'},data = data})
	end

	local function send_deletions(i)
		local file = next(remotefiles,i)
		if not file then
			-- done with deletions
			return send_files()
		end
		local function success(data,status,headers)
			if status~=200 then xc.log_error('Received status '..status) return end
			remotefiles[file]=nil

			return send_deletions()
		end
		xc.xlog('Deleting remote file '..file)
		http.request(xCodea_server..'/delete', success, xc.connection_error,
			{method = 'POST', headers={project=xc.project,file=file,ftype='source'}})
	end
	local function send_dependencies()
		if localdeps == (headers['dependencies'] or '') then
			return send_deletions()
		end
		local function success(data,status,headers)
			if status~=200 then xc.log_error('Received status '..status) return end
			return send_deletions()
		end
		-- deps have changed locally
		xc.xlog('Sending dependencies: '..localdeps)
		http.request(xCodea_server..'/set_dependencies',success,xc.connection_error,
			{method = 'POST', headers={project=xc.project,dependencies=localdeps}})
	end

	return send_dependencies()
end

function xc.poll()
	local function success(data,status,headers)
		if status~=200 and status~=204 then xc.log_error('Received status '..status) return end
		if status==204 then
			if xc.remote_push then
				http.request(xCodea_server..'/done',xc.null,xc.null)
				return xc.fatal_error('Operation completed.')
			end

			if not xc.error then
				xc.make_sandbox()
			end
			--			tween.stop(xc.tween)
			--			xc.tween = tween.delay(xc.polling_interval,xc.poll)
			xc.register_callback(xc.polling_interval,xc.poll)
			return
		end
		if xc.project~=headers['project'] then
			return xc.log_error('Invalid data received! (Wrong or missing project)')
		end
		local deps = headers['dependencies']
		if deps then
			xc.xlog('Received new dependencies: '..deps)
			local remotedeps = {}
			for dep in (deps..':'):gmatch('(..-):') do
				local i=xc.InfoPlist(dep)
				if not i:exists() then
					xc.fatal_error('Dependency "'..dep..'" that was added\n'..
						'on the server does not exist in Codea!\n'..
						'xCodea cannot create new projects in Codea, so you must do it manually.\n'..
						'You can then reconnect to the xCodea server.')
					return
				end
				table.insert(remotedeps,dep)
			end
			local i=xc.InfoPlist(xc.project)
			i:setDependencies(remotedeps)
			xc.error = nil
			local function dep_success(data,status,headers)
				if status~=200 then xc.log_error('Received status '..status) return end
				return xc.poll()
			end
			return http.request(xCodea_server..'/dependencies_saved',dep_success,xc.connection_error,
				{method = 'POST', headers = {project=xc.project,dependencies=table.concat(remotedeps,':')}})
		end

		local file = headers['file']
		local delete = headers['delete']
		if file or delete then
			local chk = headers['chk']
			local path = file or delete
			local proj,name = path:match('(.-):(.+)')
			local ftype=headers['type']
			xc.xlog('Received '..(file and 'updated' or 'deleted')..' file: '..(file or delete)..' ('..ftype..')')
			if ftype=='source' then
				saveProjectTab(path, file and data or nil)
				if file then chk = xc.adler32(readProjectTab(path)) end
				if proj==xc.project or name~='Main' then
					xc.error = nil
					if file then table.insert(xc.to_sandbox,path) end
				end
			elseif ftype=='image' then
				local key = 'Documents:'..proj..'.codea/'..name
				saveImage(key,file and data or nil)
				xCodea._SANDBOX._inv_img_cache = readImage(key) -- will you pleeease invalidate the cache?
				--				if file then chk = xc.adler32(readImage(key).data,headers['Content-Length'] or 0) end
			elseif ftype=='sound' then

			end
			local function file_success(data,status,headers)
				if status~=200 then xc.log_error('Received status '..status) return end
				return xc.poll()
			end
			return http.request(xCodea_server..'/file_'..(file and 'saved' or 'deleted'),file_success,xc.connection_error,
				{method = 'POST', headers = {project=xc.project,file=path,type=ftype,chk=chk}})
		end

		local eval = headers['eval']
		if eval then
			xc.error = nil
			local name=#data>23 and data:sub(1,20)..'...' or data
			name=name:gsub('\n',' ')
			xc.xlog('Received eval request: '..name)
			--			tween.stop(xc.tween)
			--			xc.tween = tween.delay(xc.polling_interval,xc.poll)
			xc.register_callback(xc.polling_interval,xc.poll)
			return xc.eval(data,name,true)
		end

		return xc.log_error('Invalid data received from poll!')
	end
	http.request(xCodea_server..'/poll',success,xc.connection_error,
		{headers = {project=xc.project}})
end

function xc.adler32(data,len)
	local a = 1
	local b = 0
	for i=1, (len or #data) do
		a = (a + data:byte(i)) % 65521
		b = (b + a) % 65521
	end
	return string.format('%04x',b)..string.format('%04x',a)
		--	return b*65536 + a -- loss of precision (cough codea)
end
function xc.dict2array(dict)
	local a = {}
	for v,_ in pairs(dict) do
		table.insert(a,v)
	end
	table.sort(a)
	return a
end

function xc.array2dict(arr)
	local d = {}
	for _,v in ipairs(arr) do
		d[v] = true
	end
	return d
end

function xc.splitstring(str,sep)
	if (sep=='') then return false end
	local pos,arr = 0,{}
	for st,sp in function() return string.find(str,sep,pos,true) end do
		table.insert(arr,string.sub(str,pos,st-1))
		pos = sp + 1
	end
	table.insert(arr,string.sub(str,pos))
	return arr
end

function xc.register_callback(delay,fn)
	for t in pairs(xc._callbacks) do
		if t.fn == fn then xc._callbacks[t]=nil end -- only one callback per function
	end
	local t = {time = 0, expire = math.max(delay,0.01), fn = fn}
	xc._callbacks[t] = t
end
function xc._update_callbacks()
	for t in pairs(xc._callbacks) do
		t.time = t.time + DeltaTime
		if t.time >= t.expire then
			xc._callbacks[t] = nil
			t.fn()
		end
	end
end

-- INFOPLIST ----------------------------------
xc.InfoPlist=class()

-- necessary as changes to .plist aren't "flushed" until Codea is properly "reset"
-- (i.e. the current project is stopped and another one is started)

-- FIXME nope, it seems in some cases (I'm guessing when Codea has the file open somewhere) the writes are just silently discarded...
-- more testing necessary
xc.InfoPlist.cache = {}

function xc.InfoPlist:init(projectName)
	self.proj = projectName
	self.path = os.getenv('HOME') .. '/Documents/'..projectName..'.codea/Info.plist'
end

function xc.InfoPlist:exists()
	local file = io.open(self.path,'r')
	if file then file:close() return true end
	return false
end

function xc.InfoPlist:_getAll()
	if xc.InfoPlist.cache[self.proj] then return xc.InfoPlist.cache[self.proj] end
	local file = io.open(self.path,'r')
	local plist
	if file then
		plist = file:read('*a'):gsub('[\t\n]','')
		file:close()
		local emptydeps = '<key>Dependencies</key><array/>'
		if not plist:match('<key>Dependencies') then
			plist = plist:gsub('<key>Created.-</string>','%0'..emptydeps)
		end
		plist = plist:gsub(emptydeps,'<key>Dependencies</key><array></array>')
		xc.InfoPlist.cache[self.proj] = plist
	end
	return plist
end

function xc.InfoPlist:getDependencies()
	local plist=self:_getAll() or ''
	local deps=plist:match('Dependencies</key><array>(.-)</array>') or ''
	local found={}
	for dep in deps:gmatch('<string>(.-)</string>') do
		print('Found Dependency: '..dep)
		table.insert(found,dep)
	end
	table.sort(found)
	return found
end


function xc.InfoPlist:setDependencies(dependencies)
	local plist=self:_getAll()
	if not plist then print('Cannot find project\'s Info.plist file') return end

	local depsmatch = '<key>Dependencies</key><array>(.-)</array>'
	local deps = ''
	for _,dep in pairs(dependencies) do
		deps = deps .. '<string>' .. dep .. '</string>'
		print('Dependency '..dep..' added')
	end
	plist = plist:gsub(depsmatch,'<key>Dependencies</key><array>'..deps..'</array>')
	local write = io.open(self.path, "w")
	write:write(plist)
	write:close()
	xc.InfoPlist.cache[self.proj] = plist
end



--if not xc.sandbox_started then
--	setup=function()
--		xc.try_connect()
--	end
--end

xCodea.restart = function()
	xCodea._SANDBOX = setmetatable({
		--		draw = function() end,
		--		touched = function(_) end,
		--		keyboard = function(_) end,
		--		orientationChanged = function(_) end,
		--		collide = function(_) end,
		loadstring = function(code,name)
			local success, error = _G.loadstring(code,name)
			if success then
				setfenv(success, xCodea._SANDBOX)
			end
			return success,error
		end,
		-- TODO as of 1.5.5 almost everything is allowed in Codea's sandbox
		-- only things removed are arg, os.execute and os.exit
		-- so: load,loadstring,dofile, require, packages etc are all there!
		-- FIXME dofile(file) breaks the sandbox. if necessary (is it ever used?) find a way to wrap it
		-- FIXME look into require()
		parameter = setmetatable({},{
			--- see below
			__index = function(tbl,key)
				if key=='clear' then return function()
					xCodea._escape_sandbox = {}
					_G.parameter.clear()
				end
				else return function(name,...)
					xCodea._escape_sandbox[name] = true
					return _G.parameter[key](name,...)
				end
				end
			end
		})
	}, {__index=function(tbl,key)
		if key~='draw' and key~='touched' and key~='keyboard'
			and key~='orientationChanged' and key~='collide' then
			return _G[key]
		else return nil end
	end})

	--- these are required for parameter.*
	-- they only talk to _G, so relevant globals are 'inverse referenced' to the sandbox from _G
	-- FIXME parameter.text does not work for mysterious reasons after an xCodea.restart()
	-- I suspect caching of some sort runtime-side (probably they store the pointer, which is lost at restart)
	-- (parameter.color works though? Wouldn't that also be a pointer to userdata?)
	xCodea._escape_sandbox = {}
	setmetatable(_G,{
		__index = function(tbl,key)
			if xCodea._escape_sandbox[key] then tbl = xCodea._SANDBOX end
			return rawget(tbl,key)
		end,
		__newindex = function(tbl,key,val)
			if xCodea._escape_sandbox[key] then tbl = xCodea._SANDBOX end
			rawset(tbl,key,val)
		end
	})

	--- setup
	xc.polling_interval = 1
	xc.remote_logging = true
	xc.remote_watches = false
	xc.verbose = false
	xc.remote_push = false
	xc.remote_pull = false

	xc.project = ''
	xc.projects = {}
	xc._callbacks = {}
	--	xc.tween = xc.tween or tween.delay(0,function()end)
	--	xc.ltween = xc.ltween or tween.delay(0,function()end)
	xc.log_buffer = ''
	xc.status = {}
	xc.to_sandbox = {}
	xc.sandbox_started=nil

	output.clear()
	--	tween.stop(xc.tween)
	--	tween.stop(xc.ltween)
	if not xc._tween_update then
		xc._tween_update = tween.update
		tween.update = function() end
	end
	xCodea._SANDBOX.parameter.clear()
	xc.try_connect()
end

xCodea.restart()
