#!/usr/local/bin/python2.7
# encoding: utf-8

import rumps,os,json,socket,thread,webbrowser
import xcodeaserver as xcs
#import xcodealog as xlog

app = rumps.App('xC')
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
	win = rumps.Window('computer\'s IP address:port number','Server address')
	win.default_text = prefs['ip_addr']
	response = win.run()
	if response.text != prefs['ip_addr']:
		win = rumps.Window('Open Safari on the iPad, go to http://'+response.text
			+'\nthen select all the code and copy it. Open Codea, long-press Add New Project, tap Paste new project, call it xCodea.',
			'Server address updated')
		win.run()
		sender.title = 'Server address: '+response.text
	print(response.text)

def click_projectsRoot(sender):
	if set_projectsRoot(prefs['projectsRoot']):
		sender.title = 'Projects folder: '+prefs['projectsRoot']


#homedir = os.getenv('HOME',os.getcwd())
#prefsfile = os.path.join(homedir,'.xcodea.prefs')

def set_projectsRoot(folder):
	folder_valid = False
	got_warning = False
	while not folder_valid:
		win = rumps.Window('','Projects folder')
		win.default_text = folder
		win.add_button('Cancel')
		if got_warning: win.add_button('Proceed anyway')
		response = win.run()
		folder = response.text
		if response.clicked == 2:
			return False
		print(os.path.abspath(folder))
		exists = os.path.isdir(os.path.abspath(folder))
		if not exists:
			rumps.alert('Error','The specified folder does not exist!')
		else:
			if len(os.listdir(folder))==0 or response.clicked==3:
				folder_valid = True
			else:
				rumps.alert('Warning','The specified fodler is not empty!')
				got_warning = True
	prefs['projectsRoot'] = folder
	flush_prefs()
	return True
#if not os.path.isfile(prefsfile):
#	f=open(prefsfile,'w')
#	f.write('{}')
#	f.close()
#prefs = json.load(open(prefsfile))

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
	cachefile = os.path.join(prefs['projectsRoot'],'.xcodea.cache')
	if os.path.isfile(cachefile):
		cache = json.load(open(cachefile))
		projects = cache.keys()
	for proj in projects:
		app.menu['Project'].add(rumps.MenuItem(proj,callback=click_project))
	app.menu['Project'].add(rumps.separator)
	app.menu['Project'].add(rumps.MenuItem('Rescan',callback=scan_projects))
	app.menu['Project'].add(rumps.MenuItem('New project...'))

def click_project(sender):
	set_project(sender.title)
def set_project(proj):
	app.menu['Project'].title = 'Project: '+(proj or '<NONE>')
	prefs['project'] = proj
	flush_prefs()

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
		'--src':'.',
		'--pull':False,
		'--push':False,
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


#app.menu.get('Project: '+(project or '<NONE>')).
app.menu = [
	rumps.MenuItem('Show log',callback=show_log),
	rumps.MenuItem('Project',callback=scan_projects), 
	rumps.MenuItem('Server',callback=click_server),
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
	]}, 
	rumps.separator,
]
scan_projects(None)
app.menu['Project'].title = 'Project: '+(prefs.get('project') or '<NONE>')

toggles = app.menu['Preferences']
toggles['Start server at launch'].state = prefs.get('startAtLaunch') or False
toggles['Log client print()s'].state = prefs.get('logging') or False
toggles['Show errors in notification center'].state = prefs.get('notify') or False
toggles['Emit sound on client events'].state = prefs.get('sound') or False
toggles['Verbose logging'].state = prefs.get('verbose') or False
if prefs.get('startAtLaunch') and prefs.get('project'): click_server(app.menu['Server'])
else: app.menu['Server'].title = 'Start server'
app.run()
#xlog.start()
