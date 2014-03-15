---------------------------------------------------------
--                     xCodea
--  a live execution environment for large Codea projects
---------------------------------------------------------

------------------
-- edit this
local xCodea_server = 'http://192.168.1.100:49374'
-----------------



xCodea = { _SANDBOX = {} }
setmetatable(xCodea._SANDBOX, {__index = _G})

local xc={}
xc.polling_interval = 1 -- in seconds
xc.remote_logging = true
xc.remote_watches = false
xc.server_overwrites = false

xc.project = ''
xc.projects = {}
xc.changes = {}
xc.tween = tween.delay(0,function()end)
xc.status=''

function xc.make_sandbox()
	local tab = xc.project..':Main' -- #string
	local l = loadstring(readProjectTab(tab),tab:gsub(':','/src/')) -- #function
	if not l then print('error loading tab!') return end
	setfenv(l,xCodea._SANDBOX)
	l()
	-- now i have the 3 entry points inside my sandbox
	-- time to hijack them!
	return xc.start_sandbox() -- TODO proper tail call?
end


function xc.start_sandbox()
	local success, error = xpcall(xCodea._SANDBOX.setup,xc.error_handler)
	if not success then
		return xc.sandbox_error(error)
	else
		return xc.run_sandbox()
	end
end

function xc.run_sandbox()
	if xCodea._SANDBOX.touched then
		touched = function(touch)
			local success, error = xpcall(function() xCodea._SANDBOX.touched(touch) end,xc.error_handler)
			if not success then
				return xc.sandbox_error(error)
			end
		end
	end
	if xCodea._SANDBOX.draw then
		draw = function()
			local success, error = xpcall(xCodea._SANDBOX.draw,xc.error_handler)
			if not success then
				return xc.sandbox_error(error)
			end
		end
	end
end
function xc.sandbox_error(err)
	draw = function()
		fill(255,0,0,255)
		text(err,20,HEIGHT-20)
	end
	--TODO this must be reset once we get a new eval from the http server
end
function xc.error_handler(err)
	return err..debug.traceback('',2):gsub('%[C%]:.*','')
end


function xc.draw_status()
	if xc.status then
		fill(160)
		fontSize(18)
		if not xc.status_blink or math.floor(ElapsedTime*2) % 4 ~= 0 then
			text(xc.status,WIDTH/2,HEIGHT*2/3)
		end
	end
end
function xc.draw_error()
	if xc.error then
		textMode(CORNER)
		textAlign(LEFT)
		fill(255,50,50,255)
		fontSize(18)
		text(xc.error,40,40)
	end
end

function xc.null() end

function xc.log_error(s)
	xc.error = s
	s='[client] ERROR '..s
	print(s)
	http.request(xCodea_server..'/error',xc.null,xc.null,{method=POST,data=s})
	-- TODO
end
function xc.fatal_error(s)
	xc.log_error(s)
	xc.try_connect = function()end
	draw = function()
		background(50,20,0)
		textMode(CENTER)
		fill(255,0,0)
		fontSize(80)
		text('xCodea',WIDTH/2,HEIGHT-40)
		xc.draw_error()
	end
end
function xc.log(s)
	print(s)
	http.request(xCodea_server..'/log',xc.null,xc.null,{method=POST,data=s})
	-- TODO
end

function xc.xlog(s)
	s='[client] '..s
	print(s)
	http.request(xCodea_server..'/msg',xc.null,xc.null,{method=POST,data=s})
end

function xc.vlog(s)
	print(s)
end

function xc.try_connect()
	draw = function()
		background(40)
		textMode(CENTER)
		fill(240)
		fontSize(80)
		text('xCodea',WIDTH/2,HEIGHT-40)
		textAlign(CENTER)
		xc.draw_status()
		xc.draw_error()
	end

	xc.status=xc.status..'Connecting to '..xCodea_server..'\n'
	xc.status_blink=true

	local function not_connected()
		xc.error = 'Cannot connect!'
		xc.tween = tween.delay(polling_interval,xc.try_connect)
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
		xc.tween = tween.delay(polling_interval,xc.try_connect)
		return
	end
	for k,v in pairs(headers) do
		xc.vlog('hdr: '..k..'='..v)
	end

	local proj=headers['project']
	if not proj or #proj==0 then
		xc.fatal_error('Invalid data received! (missing project)')
		return
	end
	local i = InfoPlist(proj)
	if not i:exists() then
		xc.fatal_error('Project "'..proj..'" does not exist in Codea!\n'..
			'Please restart the xCodea server with an appropriate project.\n\n'..
			'Or, if you want to work on a new project, remember that xCodea cannot\n'..
			'create new projects in Codea, so you must do it manually.\n'..
			'You can then reconnect to the xCodea server.')
		return
	end
	xc.status_blink=nil
	xc.status=xc.status..'\nConnected\nSyncing files\n'
	xc.project = proj
	xc.error=nil
	xc.polling_interval = headers['polling'] or 1
	xc.remote_logging = headers['logging']
	xc.remote_watches = headers['watches']
	xc.server_overwrites = headers['overwrite']

	xc.projects = i:getDependencies()
	local localdeps = table.concat(xc.projects,':')

	local remotefiles = {}
	for file,chk in string.gmatch(headers['checksums'] or '','(.-:.-):(.-):') do
		remotefiles[file] = chk
	end

	table.insert(xc.projects,xc.project)
	sendfiles={}
	for _,proj in pairs(xc.projects) do
		local pfiles = listProjectTabs(proj)
		for _,pfile in pairs(pfiles) do
			file = proj..':'..pfile
			chk = xc.adler32(readProjectTab(file))
			if chk ~= remotefiles[file] then
				sendfiles[file] = true
			end
			remotefiles[file]=nil
		end
	end


	local function send_files(i)
		file = next(sendfiles,i)
		if not file then
			print('DONE!')
			return xc.poll()
		end -- done sending tabs

		xc.status = xc.status .. 'Sending file '..file..'\n'
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
		file = next(remotefiles,i)
		if not file then
			-- done with deletions
			return send_files()
		end
		local function success(data,status,headers)
			if status~=200 then xc.log_error('Received status '..status) return end
			remotefiles[file]=nil

			return send_deletions()
		end
		xc.status = xc.status .. 'Deleting remote file '..file..'\n'
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
		xc.status = xc.status .. 'Sending dependencies: '..localdeps..'\n'
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
			xc.tween = tween.delay(xc.polling_interval,xc.poll)
			return
		end
		local deps = headers['dependencies']
		if deps then
			if xc.project==headers['project'] then
				xc.xlog('Received new dependencies: '..deps)
				remotedeps = {}
				for dep in (deps..':'):gmatch('(.-):') do
					local i=InfoPlist(dep)
					if not i:exists() then
						xc.fatal_error('Dependency "'..dep..'" that was added\n'..
							'on the server does not exist in Codea!\n'..
							'xCodea cannot create new projects in Codea, so you must do it manually.\n'..
							'You can then reconnect to the xCodea server.')
						return
					end
					table.insert(remotedeps,dep)
				end
				local i=InfoPlist(xc.project)
				i:setDependencies(remotedeps)
				local function dep_success(data,status,headers)
					if status~=200 then xc.log_error('Received status '..status) return end
					return xc.poll()
				end
				return http.request(xCodea_server..'/dependencies_saved',dep_success,xc.connection_error,
					{method = 'POST', headers = {project=xc.project,dependencies=table.concat(remotedeps,':')}})
			else xc.log_error('Invalid data received! (Wrong or missing project)')
			end
		end
		local file = headers['file']
		local delete = headers['delete']
		if file or delete then
			local proj,name=(file or delete):match('(.-):(.+)')
			xc.xlog('Received '..(file and 'updated' or 'deleted')..' file: '..proj..':'..name)
			local i=InfoPlist(proj)
			if not i:exists() then
				xc.fatal_error('Project "'..proj..'" does not exist in Codea!\n'..
					'xCodea cannot create new projects in Codea, so you must do it manually.\n'..
					'You can then reconnect to the xCodea server.')
				return
			end
			saveProjectTab(file or delete,file and data or nil)
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

function xc.cache_deps_get()
	local t={}
	for dep in string.gmatch(readGlobalData('xCodea.'..xc.project..'.dependencies') or '','(.-):') do
		t[dep] = true
	end
	return t
end

function xc.cache_deps_save(deps)
	-- table.concat only for arrays?
	local s=''
	for dep in pairs(deps) do
		s=s..dep..':'
	end
	saveGlobalData('xCodea.'..xc.project..'.dependencies',s)
end

function xc.cache_deps_add(dep)
	deps = xc.cache_deps_get()
	if deps[dep] then xc.log_error('Dependency '..dep..' in project '..xc.project..' is already present! Skipping add.') return end
	deps[dep] = true
	xc.cache_deps_save(deps)
end

function xc.cache_deps_remove(dep)
	deps = xc.cache_deps_get()
	if not deps[dep] then xc.log_error('Dependency "'..dep..'" in project "'..xc.project..'" is already missing! Skipping remove.') return end
	deps[dep] = nil
	xc.cache_deps_save(deps)
end


---@return #boolean true if no changes
function xc.check_dependencies(remotedeps)
	xc.vlog('Checking project dependencies')
	local localdeps = InfoPlist(xc.project):getDependencies()
	--xc.changes.add_deps = {}--i:getDependencies() -- lazy deep copy ;)
	--xc.changes.remove_deps = {}
	local cacheddeps = xc.cache_deps_get()
	local local_done = true
	local remote_done = true

	for dep,_ in pairs(localdeps) do
		if not remotedeps[dep] then
			if not cacheddeps[dep] then
				-- new dep client-side, send to server
				if xc.server_overwrites then
					xc.log_error('WARNING! Found new dependency "'..dep..'" on the client.\nUndoing change: overwrite option is enabled on the server!')
					localdeps[dep] = nil
					InfoPlist(xc.project):setDependencies(localdeps)
					local_done = false
				else
					xc.xlog('New dependency "'..dep..'" on the client, sending change to server')
					remote_done = false
				end
			else
				-- deleted server-side, sync locally
				xc.xlog('Dependency "'..dep..'" removed server-side, syncing locally')
				localdeps[dep] = nil
				InfoPlist(xc.project):setDependencies(localdeps)
				cacheddeps[dep] = nil
				xc.cache_deps_remove(dep)
				local_done = false
			end
		else
			-- make sure cache is updated
			if not cacheddeps[dep] then
				xc.xlog('Updated local cache for dependency '..dep)
				xc.cache_deps_add(dep)
				cacheddeps[dep]=true
			end
		end
	end

	for dep,_ in pairs(remotedeps) do
		if not localdeps[dep] then
			if not cacheddeps[dep] then
				-- new dep server-side, sync locally
				xc.xlog('New dependency "'..dep..'" on the server, syncing locally')
				local_done = false
				local i = InfoPlist(dep)
				if not i:exists() then
					xc.fatal_error('Dependency "'..dep..'" that was added\n'..
						'on the server does not exist in Codea!\n'..
						'xCodea cannot create new projects in Codea, so you must do it manually.\n'..
						'You can then reconnect to the xCodea server.')
					return
				end
				localdeps[dep] = true
				InfoPlist(xc.project):setDependencies(localdeps)
				cacheddeps[dep] = true
				xc.cache_deps_add(dep)
			else
				-- deleted client-side, send deletion
				if xc.server_overwrites then
					local i = InfoPlist(dep)
					if not i:exists() then
						xc.fatal_error('Dependency '..dep..' and its project were removed on the client.\n'..
							'The overwrite option is enabled on the server, but this change cannot be undone!')
						return
					end
					xc.log_error('WARNING! Dependency "'..dep..'" removed on the client.\nUndoing change: overwrite option is enabled on the server!')
					local_done = false
					localdeps[dep] = true
					InfoPlist(xc.project):setDependencies(localdeps)
				else
					xc.xlog('Dependency "'..dep..'" removed on the client, sending change to server')
					remote_done = false
				end
			end
		else
			-- make sure cache is updated
			if not cacheddeps[dep] then
				cacheddeps[dep]=true
				xc.cache_deps_add(dep)
			end
		end
	end
	return local_done, remote_done
end




function xc.assert_headers(loc,rem)
	if loc~=rem then xc.log_error('Invalid data received! '..(rem or '<MISSING>')..' (was '..loc..')') return false end
	return true
end

function xc.send_dependencies()
	local localdeps = InfoPlist(xc.project):getDependencies()
	local deps_string = ''
	for dep in pairs(localdeps) do
		deps_string = deps_string .. dep .. ':'
	end

	local function success(data,status,headers)
		if status~=200 then xc.log_error('Received status '..status) return end
		if not xc.assert_headers(xc.project,headers['project']) then return false end

		-- FIXME this won't work as deps order is shuffled around :/
		-- if not xc.assert_headers(deps_string,headers['dependencies']) then return false end
		local remotedeps_string = headers['dependencies'] or ''
		local remotedeps = {}
		for dep in string.gmatch(remotedeps_string,'(.-):') do
			remotedeps[dep] = true
		end
		xc.cache_deps_save(remotedeps)
		xc.xlog('Dependencies synced')
		return xc.try_connect()
	end
	xc.xlog('Sending dependencies: '..deps_string)
	http.request(xCodea_server..'/set_dependencies',success,xc.connection_error,
		{method='POST',headers={project=xc.project,dependencies=deps_string}})
end





function xc.check_files(remotefiles)
	xc.vlog('Checking files')
	local local_done = true
	local remote_done = true
	local localfiles = {}
	local cachedfiles = {}
	for dep,_ in pairs(xc.projects) do
		local pfiles = listProjectTabs(dep)
		for _,pfile in pairs(pfiles) do
			file = dep..':'..pfile
			chk = xc.adler32(readProjectTab(file))
			localfiles[file] = chk
			cachedfiles[file] = readGlobalData('xCodea.'..file)
		end
	end
	for file,chk in pairs(localfiles) do
		if chk ~= remotefiles[file] then
			if chk ~= cachedfiles[file] then
				if xc.server_overwrites then
					xc.log_error('WARNING! Found updated file "'..file..'" on the client.\nUndoing change: overwrite option is enabled on the server!')
					localfiles[file] = nil
					saveProjectTab(file,nil)
					local_done=false
				else
					xc.xlog('New file "'..file..'" on the client, sending change to server')
					remote_done=false
				end
			else
			-- deleted server-side, sync locally?

			end
		end
	end

end

--[[
local projs=headers['projects']
local projects={}
if projs then
for proj in projs:gmatch('(.-):') do
projects[proj]=true
end
end
for proj,_ in pairs(projects) do
local i = InfoPlist(proj)
if i:exists() then
xc.projects[proj]=true
end
end
--]]



function xc.connect()
--    http.request(xCodea_server,connected,xc.log,{method='HEAD',headers={x-codea='connect'}})
--,projects=table.concat(project_dependencies,'::')}})
end

function setup()
	xc.try_connect()
end







-- INFOPLIST ----------------------------------
InfoPlist=class()

function InfoPlist:init(projectName)
	self.path = os.getenv('HOME') .. '/Documents/'..projectName..'.codea/Info.plist'
end
function InfoPlist:exists()
	local file = io.open(self.path,'r')
	if file then file:close() return true end
	return false
end

function InfoPlist:_getAll()
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

function InfoPlist:getDependencies()
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


function InfoPlist:setDependencies(dependencies)
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
