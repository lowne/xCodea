#!/usr/local/bin/python2.7
# encoding: utf-8

import rumps,os,json,socket,thread,webbrowser
from time import sleep
import xcodeaserver as xcs
#import xcodealog as xlog

app = rumps.App('xCodea')
prefsfile = '.xcodea.prefs'
try:
	with app.open(prefsfile) as f:
		prefs = json.load(f)
except IOError as e:
	prefs = {}

def flush_prefs():
	with app.open(prefsfile,'w') as f:
		json.dump(prefs,f)

def click_startAtLaunch(sender):
	sender.state = not sender.state
	prefs['startAtLaunch'] = sender.state
	flush_prefs()
def click_notify(sender):
	sender.state = not sender.state
	prefs['notify'] = sender.state
	flush_prefs()
def click_sound(sender):
	sender.state = not sender.state
	prefs['sound'] = sender.state
	flush_prefs()
def click_verbose(sender):
	sender.state = not sender.state
	prefs['verbose'] = sender.state
	flush_prefs()
def click_logging(sender):
	sender.state = not sender.state
	prefs['logging'] = sender.state
	flush_prefs()

def get_ip():
	s_getip = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
	s_getip.connect(('8.8.8.8', 80))
	ip = s_getip.getsockname()[0]
	s_getip.close()
	return ip

def click_serverIpPort(sender):
	win = rumps.Window('computer\'s IP address:port number','Server address',
		default_text=prefs['ip_addr'],cancel=True,dimensions=(320,20))
	response = win.run()
	print(response.clicked)
	if response.clicked==1 and response.text != prefs['ip_addr']:
		rumps.alert('Server address updated',
			'Open Safari on the iPad, go to http://'+response.text
			+'\nthen select all the code and copy it.\n'
			+'Open Codea, long-press Add New Project, tap Paste new project, call it xCodea.'
			)
		sender.title = 'Server address: '+response.text
	#print(response.text)

def click_projectsRoot(sender):
	if set_projectsRoot(prefs['projectsRoot']):
		sender.title = 'Projects folder: '+prefs['projectsRoot']


#homedir = os.getenv('HOME',os.getcwd())
#prefsfile = os.path.join(homedir,'.xcodea.prefs')

def set_projectsRoot(folder):
	folder_valid = False
	got_warning = False
	while not folder_valid:
		win = rumps.Window('','Projects folder',cancel=True,
			default_text=folder,dimensions=(320,20))
		if got_warning: win.add_button('Proceed anyway')
		response = win.run()
		folder = response.text
		if response.clicked == 0: return False
		exists = os.path.isdir(os.path.abspath(folder))
		if not exists:
			rumps.alert('Error','The specified folder does not exist!')
		else:
			if len(os.listdir(folder))==0 or response.clicked==2: folder_valid = True
			else:
				rumps.alert('Warning','The specified fodler is not empty!')
				got_warning = True
	prefs['projectsRoot'] = folder
	flush_prefs()
	save_client_source()
	return True

def save_client_source():
	contentdir = os.getcwd()
	file = open('Main.lua')
	source = file.read()
	file.close()
	root = prefs['projectsRoot']
	xcodeadir = os.path.join(root,'xCodea')
	if not os.path.isdir(xcodeadir):
		os.mkdir(xcodeadir)
	editpath = os.path.join(xcodeadir,'EDIT_THIS.lua')
	file = open(editpath,'w')
	file.write("xCodea_server = 'http://"+prefs['ip_addr']+"'\n")
	file.close()
	mainpath = os.path.join(xcodeadir,'Main.lua')
	file = open(mainpath,'w')
	file.write(source)
	file.close()

if not prefs.get('ip_addr'):
	prefs['ip_addr'] = get_ip()+':49374'
	flush_prefs()
if not prefs.get('projectsRoot'):
	homedir = os.getenv('HOME',os.getcwd())
	if not set_projectsRoot(os.path.join(homedir,'xCodea')):
		sys.exit(1)

def scan_projects(sender):
	projects = []
	if len(app.menu['Project'])>0:
		app.menu['Project'].clear()
	app.menu['Project'].add(rumps.MenuItem('New project...',callback=new_project))
	app.menu['Project'].add(rumps.MenuItem('Rescan',callback=scan_projects))
	app.menu['Project'].add(rumps.separator)
	cachefile = os.path.join(prefs['projectsRoot'],'.xcodea.cache')
	if os.path.isfile(cachefile):
		cache = json.load(open(cachefile))
		projects = cache.keys()
	for proj in projects:
		app.menu['Project'].add(rumps.MenuItem(proj,callback=click_project))

def click_project(sender):
	set_project(sender.title)

def set_project(proj):
	app.menu['Project'].title = 'Project: '+(proj or '<NONE>')
	prefs['project'] = proj
	flush_prefs()
	if xcs.is_running:
		rumps.alert('Project changed','Please restart the server')
		if menu_server.state:
			click_server(menu_server)

def new_project(sender):
	project_valid = False
	while not project_valid:
		win = rumps.Window('The project must already exist in Codea','New project',
			cancel=True,dimensions=(320,20))
		response = win.run()
		proj = response.text
		if response.clicked==1 and len(proj)>0:
			set_project(proj)
			project_valid = True

def click_server(sender):
	if not sender.state:
		start_server()
	else:
		stop_server()
	sender.state = not sender.state
	app.menu['Server'].title = sender.state and 'Server running - stop' or 'Start server'
	app.title = 'xC'+(sender.state and '>' or '')

def start_server():
	if xcs.is_running:
		rumps.alert('','Server already started!')
		#return
	xcs.args = {
		'--root':prefs['projectsRoot'],
		'<projDir>': prefs['project'],
		'--notify':prefs.get('notify'),
		'--sound':prefs.get('sound'),
		'--color':True,
		'--polling':1,
		'--logging':prefs.get('logging'),
		'--verbose':prefs.get('verbose'),
#		'--src':'.',
		'--src':prefs.get('sources_dir'),
		'--images':prefs.get('images_dir'),
		'--shaders':prefs.get('shaders_dir'),
		'--sounds':prefs.get('sounds_dir'),
		'--music':prefs.get('music_dir'),
		'--pull':False,
		'--push':False,
		'--long-polling':True,
		'gui_app':True,
	}
	thread.start_new_thread(xcs.start_server,())
def stop_server():
	if not xcs.is_running:
		rumps.alert('','Server already stopped!')
	xcs.stop_server()
#	xcs.x.shutdown = True
def show_log(sender):
#	thread.start_new_thread(xlog.show_log,())
	webbrowser.open(prefs['ip_addr']+'/server_log')

def input_ftype_dir(what):
	win = rumps.Window('Location of your '+what+' inside the project directory',what.capitalize(),
		cancel=True,default_text=prefs[what+'_dir'],dimensions=(320,20))
	response = win.run()
	if response.clicked==0: return prefs[what+'_dir']
	dir = response.text
	if len(dir)==0: return '.'
	return dir

def click_sources(sender):
	set_ftype_dir('sources',input_ftype_dir('sources'),sender)
def click_images(sender):
	set_ftype_dir('images',input_ftype_dir('images'),sender)
def click_shaders(sender):
	set_ftype_dir('shaders',input_ftype_dir('shaders'),sender)
def click_sounds(sender):
	set_ftype_dir('sounds',input_ftype_dir('sounds'),sender)
def click_music(sender):
	set_ftype_dir('music',input_ftype_dir('music'),sender)

def set_ftype_dir(pref,dir,sender):
	prefs[pref+'_dir'] = dir
	flush_prefs()
	sender.title = pref.capitalize()+': '+dir

def get_eval_luac():
	if not prefs.get('projectsRoot'): return
	return os.path.join(prefs['projectsRoot'],'eval.luac')

def click_eval(sender):
	if not xcs.is_running: return
	last_eval = prefs.get('last_eval') or ''
	win = rumps.Window('Lua chunk to execute (ctrl-return for new line):','Eval',
		cancel=True,default_text=last_eval,dimensions=(320,320))
	response = win.run()
	if response.clicked==2: return
	res = response.text.replace(u'\u2028','\n').replace(u'\u2029','\n')
	prefs['last_eval'] = res
	flush_prefs()
	file = open(get_eval_luac(),'w')
	file.write(res)
	file.close()


def click_eval_clipboard(sender):
	if not xcs.is_running: return
	os.system('pbpaste > "'+get_eval_luac()+'"')

def click_restart_project(sender):
	if not xcs.is_running: return
	os.system('echo "xCodea.restart()" > "'+get_eval_luac()+'"')


#app.menu.get('Project: '+(project or '<NONE>')).
app.menu = [
	rumps.MenuItem('Eval...',callback=click_eval),
	rumps.MenuItem('Eval clipboard',callback=click_eval_clipboard),
	rumps.separator,
	rumps.MenuItem('Restart project',callback=click_restart_project),
	rumps.separator,
	rumps.MenuItem('Server',callback=click_server),
	rumps.MenuItem('Show log',callback=show_log),
	rumps.MenuItem('Project',callback=scan_projects),
	rumps.separator,
	{'Preferences':[
		rumps.MenuItem('Server address: '+prefs['ip_addr'],callback=click_serverIpPort,),
		rumps.MenuItem('Projects folder: '+prefs['projectsRoot'],callback=click_projectsRoot),
		rumps.MenuItem('Start server at launch',callback=click_startAtLaunch),
		rumps.separator,
		rumps.MenuItem('Log client print()s',callback=click_logging),
		rumps.MenuItem('Show errors in notification center',callback=click_notify),
		rumps.MenuItem('Emit sound on client events',callback=click_sound),
		rumps.MenuItem('Verbose logging',callback=click_verbose),
		rumps.separator,
		{'Project structure':[
			rumps.MenuItem('sources',callback=click_sources),
			rumps.MenuItem('images',callback=click_images),
			rumps.MenuItem('shaders',callback=click_shaders),
			rumps.MenuItem('sounds',callback=click_sounds),
			rumps.MenuItem('music',callback=click_music),
			],
		}
		]
	},
	rumps.separator,
]
app.title='xC'
scan_projects(None)
app.menu['Project'].title = 'Project: '+(prefs.get('project') or '<NONE>')


toggles = app.menu['Preferences']
# for p in ['startAtLaunch','logging','notify','sound','verbose']:
# 	toggles[p].state = prefs.get(p) or False
toggles['Start server at launch'].state = prefs.get('startAtLaunch') or False
toggles['Log client print()s'].state = prefs.get('logging') or False
toggles['Show errors in notification center'].state = prefs.get('notify') or False
toggles['Emit sound on client events'].state = prefs.get('sound') or False
toggles['Verbose logging'].state = prefs.get('verbose') or False

subdirs = toggles['Project structure']
for el in subdirs:
	pref = el.title().lower()
	set_ftype_dir(pref,prefs.get(pref) or '.',subdirs[el])

menu_server = app.menu['Server']
if prefs.get('startAtLaunch') and prefs.get('project'): click_server(menu_server)
else: menu_server.title = 'Start server'


app.run()




#xlog.start()



#for p in ['srcSubDir','imgSubDir','shdSubDir','sndSubDir','musSubDir']:
#	if not prefs.get(p):
#		prefs[p] = '.'
#		flush_prefs()
