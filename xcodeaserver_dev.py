#!/usr/local/bin/python2.7
# encoding: utf-8

import sys,os,time,re,json,subprocess
from os import path,listdir
from lxml import etree
from time import sleep

#---------------------- utility functions
#----------------------------------------

#POLLING_MAX_WAIT = 4 # TODO long poll disabled until http.request bug is fixed
POLLING_WAIT = 0.2
RED='31'
GREEN='32'
BLUE='34'
NORMAL=''
html_color={'31':'#F44','32':'#AFA','34':'#AAF','':'#EEE'}
file_types = {'source':{
				'exts':['.lua'],
				'open':'r',
				'content-type':['text/plain'],
			},'image':{
				'exts':['.png','.gif','.jpg','.pdf'],
				'open':'rb',
				'content-type':['image/png','image/gif','image/jpg','application/pdf'],
			},'sound':{
				'exts':['.wav','.caf','.mp3'],
				'open':'rb',
				'content-type':['audio/wav','audio/x-caf','audio/mpeg3'],
				}
			}

def adler32(data):
	# TODO test with real unicode - probably broken
#	if isinstance(str,basestring): data = bytearray(str,'utf-8')
	data = bytearray(data)
	a = 1
	b = 0
	for i in range(len(data)):
		a = (a + int(data[i])) % 65521
		b = (b + a) % 65521
	return '%04x%04x'%(b,a)

def colorprint(c,data):
	if gui_app:
		log_buffer.insert(0,'<div style="color:%s">%s</div>'%(html_color[c],data))
		#return
	if color:
		data = '\x1b['+c+'m'+data+'\x1b[m'
	if c==RED:
		sys.stderr.write(data)
	else:
		print(data)

def shell(*args):
	try:
		subprocess.Popen(list(args),stdout=open(os.devnull, 'wb'))
	except OSError as e:
		print("Execution failed: ",e)

def error(data):
	colorprint(RED,'[server] ERROR '+data+'\n')
	if notify:
		shell('terminal-notifier','-title','xCodea server',
			'-sound','Sosumi','-group','xCodea.error','-message',data)
	elif sound:
		shell('afplay','/System/Library/Sounds/Sosumi.aiff')

def rerror(data):
	pasted = False
	for match in re.finditer('\[string "::(.+?)"\]:(.+?):',data):
		snippet = match.group(1)
		proj,file = snippet.split(':')
		#filename = path.normpath(path.join(projectsRoot,proj,file_dirs['source'],file+'.lua'))
		filename = path.normpath(path.join(proj,file_dirs['source'],file+'.lua'))
		if not pasted:
			os.system('echo "%s"|pbcopy -pboard find' % filename)
			os.system('echo "%s"|pbcopy -pboard font' % match.group(2))
			pasted = True
		#filename = path.normpath(path.join(file+'.lua'))
		data = data.replace(match.group(0),'('+filename+':'+match.group(2)+')')
		#data = '('+filename+':'+match.group(2)+')'+data.replace(match.group(0),'')

	colorprint(RED,data+'\n')
	if notify:
		os.system('terminal-notifier -title "xCodea ERROR" -sound Sosumi -group xCodea.error -message "\\%s" > /dev/null'% (data.replace('"','\\"')))
	elif sound:
		shell('afplay','/System/Library/Sounds/Sosumi.aiff')

def vlog(data):
	if verbose:
		colorprint(BLUE,'[server] '+data)

def log(data):
	colorprint(BLUE,'[server] '+data)
	#elif notify:
	#	os.system('terminal-notifier -title "xCodea server" -sound Pop -group xCodea.server -message "\\%s" > /dev/null'% (data))
def clog(data):
	colorprint(GREEN,data)
	if sound:
		shell('afplay','-v','0.34','/System/Library/Sounds/Pop.aiff')
	if notify:
		shell('terminal-notifier','-remove','xCodea.error')
	#if notify:
	#	os.system('terminal-notifier -title "xCodea client" -group xCodea.client -message "\\%s" > /dev/null'% (data))

def rlog(data):
	colorprint(NORMAL,data)

def get_ldtbuildpath(proj):
	bppath = path.join(projectsRoot,proj,ldtbuildpath)
	if not path.isfile(bppath): return None
	bp=etree.parse(open(bppath))
	if bp:
		root = bp.getroot()
		if root.tag=='buildpath':
			return root
	error('.buildpath file is malformed or unknown format!')
	return None

def write_ldtbuildpath(bp,proj):
	bp.getroottree().write(open(path.join(projectsRoot,proj,ldtbuildpath),'w'),xml_declaration=True,encoding='UTF-8',pretty_print=True)

def flush_cache():
	f=open(cachefile,'w')
	json.dump(cache,f)
	f.close()

#------------------------ http methods
#-------------------------------------

def do_GET(httpd):
	#print('GET',httpd.path)
	if httpd.path=='/poll':
		do_poll(httpd)
	elif httpd.path=='/connect':
		do_connect(httpd)
	elif httpd.path=='/server_log':
		httpd.send_response(200)
		#data = '<style>code{font-family:Lucida Grande,Consolas,monospace;}</style>'
		data = '<body style="font-family:Lucida Grande;font-size:11pt;background:#222" >'+'\n'.join(log_buffer)
		httpd.send_header('content-length',len(data))
		httpd.send_header('content-type','text/html')
		httpd.send_header('refresh','2;url=/server_log')
		httpd.end_headers()
		httpd.wfile.write(data)
	elif httpd.path=='/':
#		editpath = path.join(projectsRoot,'xCodea',srcdir,'EDIT_THIS.lua')
#		mainpath = path.join(projectsRoot,'xCodea',srcdir,'Main.lua')
		editpath = path.join(projectsRoot,'xCodea','EDIT_THIS.lua')
		mainpath = path.join(projectsRoot,'xCodea','Main.lua')
		if path.isfile(editpath) and path.isfile(mainpath):
			httpd.send_response(200)
			httpd.send_header('content-type','text/text')
			file = open(editpath)
			data = file.read()
			file.close()
			data = '--# EDIT_THIS\n' + data + '\n'
			file = open(mainpath)
			main = file.read()
			file.close()
			data = data + '--# Main\n' + main
			httpd.send_header('content-length',len(data))
			httpd.end_headers()
			httpd.wfile.write(data)
		else:
			httpd.send_response(404)
			httpd.end_headers()
	elif httpd.path=='/favicon.ico':
		httpd.send_response(200)
		httpd.send_header('content-length',0)
		httpd.end_headers()
	else:
		error('Invalid request!')
		connected=None
		httpd.send_response(500)
		httpd.end_headers()

def do_POST(httpd):
	#print('POST '+httpd.path)
	try:
		length = int(httpd.headers.getheader('content-length'))
	except (TypeError, ValueError):
		length = 0
	data = httpd.rfile.read(length) if length>0 else ''
	if httpd.path=='/log':
		rlog(data)
		httpd.send_response(200)
	elif httpd.path=='/msg':
		clog(data)
		httpd.send_response(200)
	elif httpd.path=='/error':
		rerror(data)
		httpd.send_response(200)
	elif httpd.path=='/file':
		do_file(httpd,data)
	elif httpd.path=='/delete':
		do_delete(httpd)
	elif httpd.path=='/set_dependencies':
		do_set_dependencies(httpd)
	elif httpd.path=='/file_saved':
		do_file_saved(httpd)
	elif httpd.path=='/file_deleted':
		do_file_deleted(httpd)
	elif httpd.path=='/dependencies_saved':
		do_dependencies_saved(httpd)
	else:
		error('Invalid request!')
		connected=None
		httpd.send_response(500)
	httpd.end_headers()

#----------------------------------------------
#----------------------------------------------

def do_connect(httpd):
	global polling_wait
	polling_wait = 0.1
	log('Client connected to project '+project)
	if not cache.get(project):
		cache[project] = dict()
		flush_cache()
	if not cache[project].get('dependencies'):
		cache[project]['dependencies'] = list()
		flush_cache()
	deps = sorted(cache[project]['dependencies'])
	httpd.send_response(200)
	httpd.send_header('polling',pollingInterval)
	if logging:	httpd.send_header('logging','true')
	if verbose: httpd.send_header('verbose','true')
	if pull: httpd.send_header('pull','true'); log('Starting pull command')
	if push: httpd.send_header('push','true'); log('Starting push command')
	#if watches: httpd.send_header('watches','true')
	#if overwrite: httpd.send_header('overwrite','true')
	httpd.send_header('project',project)
	httpd.send_header('dependencies',':'.join(deps))
	vlog('Sending dependencies: '+':'.join(deps))
	data=''
	datalog=''
	deps.append(project)
	for ftype in file_types.keys():
		datalog = datalog + ftype +': '
		for proj in deps:
			files = (cache.get(proj) or dict()).get(ftype) or dict()
			for file,chk in files.items():
				data = data + proj+':'+file+':' + chk + ':'
				datalog = datalog + proj+':'+file+', '
		if push:
			for proj in deps:
				if cache.get(proj): cache[proj][ftype] = dict()
		if not pull: httpd.send_header(ftype,data);
	vlog('Sending known files: '+datalog)
	httpd.end_headers()

def do_set_dependencies(httpd):
	proj = httpd.headers.getheader('project')
	if proj!=project:
		error('Invalid state in request!')
		# TODO connect all over again?
		httpd.send_response(500)
		return
	deps_string = httpd.headers.getheader('dependencies')
	deps=list()
	for dep in deps_string.split(':'):
		if len(dep)>0: #skip empty last
			deps.append(dep)

	deps=sorted(deps)
	vlog('Received dependencies: '+', '.join(deps))
	cache[project]['dependencies'] = deps
	flush_cache()
	bp = get_ldtbuildpath(project)
	if bp is not None:
		_ = [bp.remove(e) for e in bp if e.get('kind')=='prj']
		for dep in deps:
			bp.append(etree.Element('buildpathentry', combinedaccessrules='false',kind='prj',path='/'+dep))
		write_ldtbuildpath(bp,project)
		vlog('Updated .buildpath')
	httpd.send_response(200)
	httpd.send_header('project',project)

def do_file(httpd,data):
	proj = httpd.headers.getheader('project') or ''
	tabname = httpd.headers.getheader('file') or ''
	ftype = httpd.headers.getheader('type')
	if proj!=project or tabname.find(':')<1 or not ftype:
		error('Invalid state in request!')
		httpd.send_response(500)
		return
	log('Received file '+tabname)
	proj, filename = tabname.split(':')
	projpath = path.normpath(path.join(projectsRoot,proj,file_dirs[ftype]))
	if not path.isdir(projpath):
		os.mkdir(projpath)
	filepath = path.join(projpath,filename+'.lua')
	is_overwrite = os.path.isfile(filepath)
	if is_overwrite: log('File %s already exists! Overwriting.' % filepath)
	file = open(filepath,'w')
	file.write(data)
	file.close()
	if not cache.get(proj):	cache[proj] = dict()
	if not cache[proj].get('source'): cache[proj]['source'] = dict()
	cache[proj]['source'][filename] = adler32(data)
	flush_cache()
	log('Saved file '+ filepath)
	httpd.send_response(200)
	httpd.send_header('project',project)

def do_delete(httpd):
	proj = httpd.headers.getheader('project') or ''
	tabname = httpd.headers.getheader('file') or ''
	ftype = httpd.headers.getheader('type')
	if proj!=project or tabname.find(':')<1 or not ftype:
		error('Invalid state in request!')
		httpd.send_response(500)
		return
	log('Received delete request for file '+tabname)
	proj, filename = tabname.split(':')
	((cache.get(proj) or dict()).get('source') or dict()).pop(filename,'')
	flush_cache()
	projpath = path.normpath(path.join(projectsRoot,proj,file_dirs[ftype]))
	if not path.isdir(projpath):
		error('Project directory %s does not exist!' % projpath)
		httpd.send_response(200)
		return
	filepath = path.join(projpath,filename+'.lua')
	if not os.path.isfile(filepath):
		error('File %s does not exist!' %filepath)
		httpd.send_response(200)
		return
	os.remove(filepath)
	log('File %s deleted' % filepath)

def	do_poll(httpd):
	if not gui_app:
		global counter
		#sys.stdout.write('-\\|/'[counter]+'\b')
		sys.stdout.write('- '[counter]+'\b')
		counter = (counter + 1) % 2
		sys.stdout.flush()
	proj = httpd.headers.getheader('project') or ''
	#print(proj,project)
	if proj!=project:
		error('Invalid state in request (wrong project). Please restart the client.')
		httpd.send_response(500)
		httpd.end_headers()
		return
	elapsed = 0
	global polling_wait
	acc_wait = polling_wait
	polling_wait = 0.1
	while elapsed<acc_wait:
		elapsed = elapsed + 0.1
		bp = get_ldtbuildpath(project)
		if bp is not None:
			deps = sorted([e.get('path')[1:] for e in bp if e.get('kind')=='prj'])
			if deps!=cache[project]['dependencies']:
				# print(deps,cache[project]['dependencies'])
				log('Dependencies changed in .buildpath, sending updated: '+', '.join(deps))
				httpd.send_response(200)
				httpd.send_header('project',project)
				httpd.send_header('dependencies',':'.join(deps))
				#cache[project]['dependencies']=deps
				#flush_cache()
				return
		deps=sorted(cache[project]['dependencies'])
		deps.append(project)


		known_files = {ftype:set() for ftype in file_types.keys()}
		#'sources':set(),'images':set(),'sounds':set()}
		for proj in deps:
			if not cache.get(proj): cache[proj]=dict()
			for ftype in file_types.keys():
				if not cache[proj].get(ftype): cache[proj][ftype] = dict()
				for filename in cache[proj][ftype].keys():
					known_files[ftype].add(proj+':'+filename)
			for ftype,params in file_types.items():
				projpath = path.normpath(path.join(projectsRoot,proj,file_dirs[ftype]))
				for fullname in [f for f in listdir(projpath) if path.isfile(path.join(projpath,f)) and not f.startswith('.')]:
					filepath = path.join(projpath,fullname)
					filename, ext = path.splitext(fullname)
					ext = ext.lower()
					tabpath = proj+':'+filename
					if ext in params['exts']:
						file = open(filepath,params['open'])
						data = file.read()
						file.close()
						known_files[ftype].discard(tabpath)
						chk = adler32(data)
						if chk != cache[proj][ftype].get(filename):
							idx = params['exts'].index(ext)
							ctype = params['content-type'][idx]
							vlog('Sending updated file: '+tabpath+' ('+ftype+')')
							httpd.send_response(200)
							httpd.send_header('project',project)
							httpd.send_header('content-type',ctype)
							httpd.send_header('content-length',len(data))
							httpd.send_header('type',ftype)
							httpd.send_header('file',tabpath)
							httpd.send_header('chk',chk) #can't do adler32 fo binaries in lua
							httpd.end_headers()
							httpd.wfile.write(data)
							return
		for ftype in file_types.keys():
			for tabpath in known_files[ftype]:
				proj,filename = tabpath.split(':')
				if filename!='Main' or ftype!='source':
					#filename, ext = path.splitext(fullname)
					#for exts,pars in types.items():
					#	if ext in exts:
					vlog('Sending delete request for removed file: '+tabpath)
					httpd.send_response(200)
					httpd.send_header('project',project)
					#httpd.send_header('content-length',0)
					httpd.send_header('type',ftype)
					httpd.send_header('delete',tabpath)
					httpd.end_headers()
					return

		evalpath = path.normpath(path.join(projectsRoot,'eval.luac'))
		global last_eval
		if path.isfile(evalpath):
   			file = open(evalpath)
			data = file.read()
			file.close()
			os.remove(evalpath)
			if data != last_eval:
				last_eval = data
				vlog('Sending eval request')
				httpd.send_response(200)
				httpd.send_header('project',project)
				httpd.send_header('eval','true')
				httpd.send_header('content-length',len(data))
				httpd.end_headers()
				httpd.wfile.write(data)
				return
		else:
			last_eval = ''
		sleep(0.1)
	polling_wait = min(acc_wait + 0.1, POLLING_MAX_WAIT)
	httpd.send_response(204)
	httpd.end_headers()

def do_dependencies_saved(httpd):
	proj = httpd.headers.getheader('project') or ''
	if proj!=project:
		error('Invalid state in request!')
		httpd.send_response(500)
		httpd.end_headers()
		return
	hdeps = httpd.headers.getheader('dependencies')
	deps = sorted(hdeps.split(':'))
	if hdeps == '': deps = []
	cache[project]['dependencies']=deps
	flush_cache()
	log('Dependencies updated successfully: '+', '.join(deps))
	httpd.send_response(200)
	httpd.end_headers()
	evalpath = path.normpath(path.join(projectsRoot,'eval.luac'))
	file = open(evalpath,'w')
	file.write('xCodea.restart()')
	file.close()

def do_file_saved(httpd):
	proj = httpd.headers.getheader('project') or ''
	if proj!=project:
		error('Invalid state in request!')
		httpd.send_response(500)
		httpd.end_headers()
		return
	tabname = httpd.headers.getheader('file')
	proj, fullname = tabname.split(':')
	chk = httpd.headers.getheader('chk')
	ftype = httpd.headers.getheader('type')
	cache[proj][ftype][fullname] = chk
	flush_cache()
	log('File updated successfully: '+tabname)
	httpd.send_response(200)
	httpd.end_headers()

def do_file_deleted(httpd):
	proj = httpd.headers.getheader('project') or ''
	if proj!=project:
		error('Invalid state in request!')
		httpd.send_response(500)
		httpd.end_headers()
		return
	tabname = httpd.headers.getheader('file')
	proj, fullname = tabname.split(':')
	ftype = httpd.headers.getheader('type')
	cache[proj][ftype].pop(fullname)
	flush_cache()
	log('File deleted successfully: '+tabname)
	httpd.send_response(200)
	httpd.end_headers()

