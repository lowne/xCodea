#!/usr/local/bin/python2.7
# encoding: utf-8

import sys,os,time,re,json
from os import path,listdir
from lxml import etree

#---------------------- utility functions
#----------------------------------------


RED='31'
GREEN='32'
BLUE='34'


def adler32(str):
	# TODO test with real unicode - probably broken
	data = str.encode('utf-8')
	data = bytearray(str)
	a = 1
	b = 0
	for i in range(len(data)):
		a = (a + int(data[i])) % 65521
		b = (b + a) % 65521
	return '%04x%04x'%(b,a)

def colorwrap(c,data):
	if not color:return data
	return '\x1b['+c+'m'+data+'\x1b[m'

def error(data):
	sys.stderr.write(colorwrap(RED,'[server] ERROR '+data))
	if sound:
		os.system('afplay /System/Library/Sounds/Sosumi.aiff')
	elif notify:
		os.system('terminal-notifier -title "xCodea server" -sound Sosumi -group xCodea.error -message "\\%s" > /dev/null'% (data.replace('"','\\"')))

def rerror(data):
	for match in re.finditer('\[string "::(.+?)"\]:(.+?):',data):
		snippet = match.group(1)
		proj,file = snippet.split(':')
		filename = path.normpath(path.join(projectsRoot,proj,srcdir,file+'.lua'))
		#filename = path.normpath(path.join(file+'.lua'))
		data = data.replace(match.group(0),'('+filename+':'+match.group(2)+')')
		#data = '('+filename+':'+match.group(2)+')'+data.replace(match.group(0),'')

	sys.stderr.write(colorwrap(RED,data)+'\n')
	if sound:
		os.system('afplay /System/Library/Sounds/Sosumi.aiff')
	elif notify:
		os.system('terminal-notifier -title "xCodea ERROR" -sound Sosumi -group xCodea.error -message "\\%s" > /dev/null'% (data.replace('"','\\"')))

def vlog(data):
	if verbose:
		print(colorwrap(BLUE,'[server] '+data))

def log(data):
	print(colorwrap(BLUE,'[server] '+data))
	if sound:
		os.system('afplay /System/Library/Sounds/Pop.aiff')
	elif notify:
		os.system('terminal-notifier -title "xCodea server" -sound Pop -group xCodea.server -message "\\%s" > /dev/null'% (data))

def clog(data):
	print(colorwrap(GREEN,data))
	if notify:
		os.system('terminal-notifier -title "xCodea client" -group xCodea.client -message "\\%s" > /dev/null'% (data))

def rlog(data):
	print(data)

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
	if httpd.path=='/poll':
		do_poll(httpd)
	elif httpd.path=='/connect':
		do_connect(httpd)
	elif httpd.path=='/':
		filepath = path.join(projectsRoot,'xCodea',srcdir,'Main.lua')
		if path.isfile(filepath):
			httpd.send_response(200)
			httpd.send_header('content-type','text/text')
			file = open(filepath)
			data = file.read()
			file.close()
			data = '--# Main\n' + data
			httpd.send_header('content-length',len(data))
			httpd.end_headers()
			httpd.wfile.write(data)
		else:
			httpd.send_response(404)
			httpd.end_headers()
	else:
		error('Invalid request!')
		connected=None
		httpd.send_response(500)
		httpd.end_headers()

def do_POST(httpd):
	#vlog('POST '+httpd.path)
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
	#if watches: httpd.send_header('watches','true')
	#if overwrite: httpd.send_header('overwrite','true')
	httpd.send_header('project',project)
	httpd.send_header('dependencies',':'.join(deps))
	data=''
	deps.append(project)
	for proj in deps:
		files = (cache.get(proj) or dict()).get('files') or dict()
		for file,chk in files.items():
			data = data + proj+':'+file+':' + chk + ':'
	httpd.send_header('checksums',data)
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
	if proj!=project or tabname.find(':')<1:
		error('Invalid state in request!')
		httpd.send_response(500)
		return
	log('Received file '+tabname)
	proj, filename = tabname.split(':')
	projpath = path.normpath(path.join(projectsRoot,proj,srcdir))
	if not path.isdir(projpath):
		os.mkdir(projpath)
	filepath = path.join(projpath,filename+'.lua')
	is_overwrite = os.path.isfile(filepath)
	if is_overwrite: log('File %s already exists! Overwriting.' % filepath)
	file = open(filepath,'w')
	file.write(data)
	file.close()
	if not cache.get(proj):	cache[proj] = dict()
	if not cache[proj].get('files'): cache[proj]['files'] = dict()
	cache[proj]['files'][filename] = adler32(data)
	flush_cache()
	log('Saved file '+ filepath)
	httpd.send_response(200)
	httpd.send_header('project',project)
	
def do_delete(httpd):
	proj = httpd.headers.getheader('project') or ''
	tabname = httpd.headers.getheader('file') or ''
	if proj!=project or tabname.find(':')<1:
		error('Invalid state in request!')
		httpd.send_response(500)
		return
	log('Received delete request for file '+tabname)
	proj, filename = tabname.split(':')
	((cache.get(proj) or dict()).get('files') or dict()).pop(filename,'')
	flush_cache()
	projpath = path.normpath(path.join(projectsRoot,proj,srcdir))
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
	global counter
	#sys.stdout.write('-\\|/'[counter]+'\b')
	sys.stdout.write('- '[counter]+'\b')
	counter = (counter + 1) % 2
	sys.stdout.flush()
	proj = httpd.headers.getheader('project') or ''
	if proj!=project:
		error('Invalid state in request!')
		httpd.send_response(500)
		httpd.end_headers()
		return
	bp = get_ldtbuildpath(project)
	if bp is not None:
		deps = sorted([e.get('path')[1:] for e in bp if e.get('kind')=='prj'])
		if deps!=cache[project]['dependencies']:
			log('Dependencies changed in .buildpath, sending updated: '+', '.join(deps))
			httpd.send_response(200)
			httpd.send_header('project',project)
			httpd.send_header('dependencies',':'.join(deps))
			#cache[project]['dependencies']=deps
			#flush_cache()
			return
	deps=sorted(cache[project]['dependencies'])
	deps.append(project)
	known_files = set()
	for proj in deps:
		if not cache.get(proj): cache[proj]=dict()
		if not cache[proj].get('files'): cache[proj]['files'] = dict()
		for filename in cache[proj]['files'].keys():
			known_files.add(proj+':'+filename)
		projpath = path.normpath(path.join(projectsRoot,proj,srcdir))
		for fullname in [f for f in listdir(projpath) if path.isfile(path.join(projpath,f)) and not f.startswith('.')]:
			filepath = path.join(projpath,fullname)
			filename, ext = path.splitext(fullname)
			tabpath = proj+':'+filename
			if ext=='.lua':
				known_files.discard(tabpath)
				file = open(filepath)
				data = file.read()
				file.close()
				chk = adler32(data)
				if chk != cache[proj]['files'].get(filename):
					vlog('Sending updated file: '+tabpath)
					httpd.send_response(200)
					httpd.send_header('project',project)
					httpd.send_header('file',tabpath)
					httpd.send_header('content-length',len(data))
					httpd.end_headers()
					httpd.wfile.write(data)
					#cache[proj]['files'][filename] = chk
					#flush_cache()
					return
	for tabpath in known_files:
		vlog('Sending delete request for removed file: '+tabpath)
		httpd.send_response(200)
		httpd.send_header('project',project)
		httpd.send_header('delete',tabpath)
		httpd.end_headers()
		return
	evalpath = path.normpath(path.join(projectsRoot,'eval.luac'))
	if path.isfile(evalpath):
		file = open(evalpath)
		data = file.read()
		file.close()
		vlog('Sending eval request')
		httpd.send_response(200)
		httpd.send_header('project',project)
		httpd.send_header('eval','true')
		httpd.send_header('content-length',len(data))
		httpd.end_headers()
		httpd.wfile.write(data)
		os.remove(evalpath)
		return

	httpd.send_response(204)
	httpd.end_headers()

def do_dependencies_saved(httpd):
	proj = httpd.headers.getheader('project') or ''
	if proj!=project:
		error('Invalid state in request!')
		httpd.send_response(500)
		httpd.end_headers()
		return
	deps = sorted(httpd.headers.getheader('dependencies').split(':'))
	cache[project]['dependencies']=deps
	flush_cache()
	log('Dependencies updated successfully: '+', '.join(deps))
	httpd.send_response(200)
	httpd.end_headers()

def do_file_saved(httpd):
	proj = httpd.headers.getheader('project') or ''
	if proj!=project:
		error('Invalid state in request!')
		httpd.send_response(500)
		httpd.end_headers()
		return
	tabname = httpd.headers.getheader('file')
	proj, filename = tabname.split(':')
	chk = httpd.headers.getheader('chk')
	cache[proj]['files'][filename] = chk	
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
	proj, filename = tabname.split(':')
	cache[proj]['files'].pop(filename)
	flush_cache()
	log('File deleted successfully: '+tabname)
	httpd.send_response(200)
	httpd.end_headers()

