----------------------------------------------------------
--                     xCodea
-- a live execution environment for large Codea projects

-- edit this (if you change the port, also change it in xcodeaserver.py)
local xCodea_server = 'http://192.168.1.100:49374'
----------------------------------------------------------


xCodea = {}
local xc = {} -- #xc



---@function make_sandbox [parent=#xc]
--@param #string i the last tab that got sandboxed (or nil)
--@return #boolean true if all tabs were sandboxed correctly
function xc.make_sandbox()
	local tab = xc.to_sandbox[1]
	if not tab then
		if xc.sandbox_started then return true end
		return xc.start_sandbox()
	end
	table.remove(xc.to_sandbox,1)
	xc.vlog('Running eval for tab '..tab)
	-- FIXME xCodea:Main below is never received (stack overflow!)
	if xc.eval(readProjectTab(tab),'::'..tab,tab=='xCodea:Main' and _G or nil) then
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

function xc.run_sandbox()
	-- <OLD> these used to be wrapped in: if xCodea._SANDBOX.draw ~= _G.draw then
	-- having them declared in the sandbox a priori makes it unnecessary
	-- but i'm keeping the reference, you never know</OLD>
	-- brought them back and removed declarations from sandbox as it could break some
	-- 'creative' ways to hijack them from dependencies
	draw = function()
		if xCodea._SANDBOX.draw ~= _G.draw then
			xpcall(xCodea._SANDBOX.draw,xc.error_handler) end
	end
	touched = function(touch)
		--if xCodea._SANDBOX.touched ~= _G.touched then
		xpcall(function() xCodea._SANDBOX.touched(touch) end, xc.error_handler)
		--end
	end
	--	print(_G.touched,xCodea._SANDBOX.touched,rawget(xCodea._SANDBOX,touched))
	keyboard = function(key)
		if xCodea._SANDBOX.keyboard ~= _G.keyboard then
			xpcall(function() xCodea._SANDBOX.keyboard(key) end, xc.error_handler)
		end
	end
	orientationChanged = function(newOrientation)
		if xCodea._SANDBOX.orientationChanged ~= _G.orientationChanged then
			xpcall(function() xCodea._SANDBOX.orientationChanged(newOrientation) end, xc.error_handler)
		end
	end
	collide = function(contact)
		if xCodea._SANDBOX.collide ~= _G.collide then
			xpcall(function() xCodea._SANDBOX.collide(contact) end, xc.error_handler)
		end
	end
	xc.vlog('Sandbox (re)started')
	return true
end

function xc.eval(code,name,env)
	xc.vlog('Eval: '..name)
	--	if code=='restart()' then loadstring(code)() end
	env = env or xCodea._SANDBOX
	local success, error = loadstring(code,name)
	if not success then
		xc.xlog('error in loadstring')
		return xc.sandbox_error(error)
	end
	setfenv(success,env)
	success,_ = xpcall(success, xc.error_handler)
	--setfenv(1,_G) -- FIXME test??
	if success then
		xc.error = nil
		return xc.sandbox_started and xc.run_sandbox() or true
	end
end

function xc.sandbox_error(err)
	--tween.stop(xc.tween)
	xc.log_error(err,true)
	draw = function()
		if xCodea._SANDBOX.draw ~= _G.draw then
			pcall(xCodea._SANDBOX.draw)
		else
			background(40)
		end
		xc.draw_status()
	end
end

function xc.error_handler(err)
	--err=err..debug.traceback()
	err=err..debug.traceback('',2):gsub('%[C%]:.*','')
	xc.sandbox_error(err)
end


function xc.draw_status()
	if xc.error then fill(255,0,0,60) rect(0,0,WIDTH,HEIGHT) end
	pushStyle()
	textMode(CORNER)
	textAlign(LEFT)
	fontSize(18)
	fill(255,50,50,255)
	textWrapWidth(WIDTH-80)
	local _,h=textSize(xc.error or '')
	text(xc.error or '',40,40)
	fill(160)
	if not xc.status_blink or math.floor(ElapsedTime*2) % 4 ~= 0 then
		text(xc.status,40,40+h)
	end
	textMode(CENTER)
	fill(100,240,255)
	fontSize(80)
	text('xCodea',WIDTH/2,HEIGHT-40)
	popStyle()
end

function xc.null() end

function xc.log_error(s,is_sandbox)
	xc.error = s
	s='[client] '..(is_sandbox and 'runtime 'or'')..'error: '..s
	print(s)
	http.request(xCodea_server..'/error',xc.null,xc.null,{method=POST,data=s})
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
	tween.stop(xc.ltween)
	if #xc.log_buffer>500 then
		xc.send_log()
	elseif #xc.log_buffer>0 then
		xc.ltween=tween.delay(0.2,xc.send_log)
	end
end

---@field [parent=#xc] #string log_buffer desc
function xc.send_log()
	http.request(xCodea_server..'/log',xc.null,xc.null,{method=POST,data=xc.log_buffer:sub(1,-2)})
	xc.log_buffer=''
end

function xc.xlog(s)
	xc.status = xc.status..s..'\n'
	s='[client] '..s
	print(s)
	http.request(xCodea_server..'/msg',xc.null,xc.null,{method=POST,data=s})
end

function xc.vlog(s)
	print('[client] '..s)
end

function xc.try_connect()
	draw = function()
		background(40)
		xc.draw_status()
	end

	xc.status=xc.status..'Connecting to '..xCodea_server..'\n'
	xc.status_blink=true

	local function not_connected()
		xc.error = 'Cannot connect!'
		xc.tween = tween.delay(xc.polling_interval,xc.try_connect)
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
		xc.tween = tween.delay(xc.polling_interval,xc.try_connect)
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
	xc.error=nil
	xc.polling_interval = tonumber(headers['polling']) or 1
	xc.remote_logging = headers['logging']
	xc.remote_watches = headers['watches'] --TODO
	xc.server_overwrites = headers['overwrite'] --TODO
	--- injections
	if xc.remote_logging then
		xCodea._SANDBOX.print = function(...) xc.log(...) end
	end

	xc.projects = i:getDependencies()
	local localdeps = table.concat(xc.projects,':')

	local remotefiles = {}
	for file,chk in string.gmatch(headers['checksums'] or '','(.-:.-):(.-):') do
		remotefiles[file] = chk
	end

	table.insert(xc.projects,xc.project)

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
			remotefiles[file]=nil
		end
	end


	local function send_files(i)
		local file = next(sendfiles,i)
		if not file then
			return xc.poll()
		end -- done sending tabs

		xc.xlog('Sending file '..file)
		local data = readProjectTab(file)
		local function success(responsedata,status,headers)
			if status ~= 200 then xc.log_error('Received status '..status) return end
			send_files(file)
		end
		http.request(xCodea_server..'/file', success, xc.connection_error,
			{method = 'POST', headers={project=xc.project,file=file},data = data})
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
			{method = 'POST', headers={project=xc.project,file=file}})
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
			if not xc.error then
				xc.make_sandbox()
			end
			tween.stop(xc.tween)
			xc.tween = tween.delay(xc.polling_interval,xc.poll)
			return
		end
		if xc.project~=headers['project'] then
			return xc.log_error('Invalid data received! (Wrong or missing project)')
		end
		local deps = headers['dependencies']
		if deps then
			xc.xlog('Received new dependencies: '..deps)
			local remotedeps = {}
			for dep in (deps..':'):gmatch('(.-):') do
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
		local eval = headers['eval']
		if eval then
			xc.error = nil
			local name=#data>23 and data:sub(1,20)..'...' or data
			name=name:gsub('\n',' ')
			xc.xlog('Received eval request: '..name)
			tween.stop(xc.tween)
			xc.tween = tween.delay(xc.polling_interval,xc.poll)
			return xc.eval(data,name)
		end
		local file = headers['file']
		local delete = headers['delete']
		if file or delete then
			local proj,name=(file or delete):match('(.-):(.+)')
			xc.xlog('Received '..(file and 'updated' or 'deleted')..' file: '..proj..':'..name)
			local i=xc.InfoPlist(proj)
			if not i:exists() then
				xc.fatal_error('Project "'..proj..'" does not exist in Codea!\n'..
					'xCodea cannot create new projects in Codea, so you must do it manually.\n'..
					'You can then reconnect to the xCodea server.')
				return
			end
			saveProjectTab(file or delete,file and data or nil)

			if proj==xc.project or name~='Main' then
				xc.error = nil
				if file then table.insert(xc.to_sandbox,file) end
			end
			local function file_success(data,status,headers)
				if status~=200 then xc.log_error('Received status '..status) return end
				return xc.poll()
			end
			return http.request(xCodea_server..'/file_'..(file and 'saved' or 'deleted'),file_success,xc.connection_error,
				{method = 'POST', headers = {project=xc.project,file=file or delete,chk=xc.adler32(file and data or '')}})
		end
		return xc.log_error('Invalid data received from poll!')
	end
	http.request(xCodea_server..'/poll',success,xc.connection_error,
		{headers = {project=xc.project}})
end

function xc.adler32(data)
	local a = 1
	local b = 0
	for i=1, #data do
		a = (a + data:byte(i)) % 65521
		b = (b + a) % 65521
	end
	return string.format('%04x',b)..string.format('%04x',a)
		--	return b*65536 + a -- loss of precision (cough codea)
end



-- INFOPLIST ----------------------------------
xc.InfoPlist=class()

function xc.InfoPlist:init(projectName)
	self.path = os.getenv('HOME') .. '/Documents/'..projectName..'.codea/Info.plist'
end
function xc.InfoPlist:exists()
	local file = io.open(self.path,'r')
	if file then file:close() return true end
	return false
end

function xc.InfoPlist:_getAll()
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
end



--if not xc.sandbox_started then
--	setup=function()
--		xc.try_connect()
--	end
--end

xCodea.restart = function()
	xCodea._SANDBOX = setmetatable({
		draw = function() end,
		touched = function(_) end,
		keyboard = function(_) end,
		orientationChanged = function(_) end,
		collide = function(_) end,
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
	--	}, {__index=_G})
	}, {__index=function(tbl,key)
		if key~='draw' and key~='touched' and key~='keyboard'
			and key~='orientationChanged' and key~='collide' then
			return _G[key]
		else return nil end
	end})
	xc.polling_interval = 1
	xc.remote_logging = true
	xc.remote_watches = false
	xc.server_overwrites = false

	xc.project = ''
	xc.projects = {}
	xc.tween = xc.tween or tween.delay(0,function()end)
	xc.ltween = xc.ltween or tween.delay(0,function()end)
	xc.log_buffer = ''
	xc.status = ''
	xc.to_sandbox = {}
	xc.sandbox_started=nil

	output.clear()
	tween.stop(xc.tween)
	xc.try_connect()
end

xCodea.restart()
