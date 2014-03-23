#!/usr/local/bin/python2.7
# encoding: utf-8
''' xCodea server


Usage: 
  xcodeaserver.py <projDir> [--root=<projectsRoot>] [--src=<srcSubDir>]
                            [--color] [--notify|--sound] [--logging]
                            [--polling=<interval>] [--verbose]
  xcodeaserver.py --push [-csv] <projDir>
  xcodeaserver.py --pull [-csv] <projDir>
  xcodeaserver.py --help


Options:
  --root=<projectsRoot>     Directory containing your projects [default: .]
  --src=<srcSubDir>         Location of .lua files in the project directory
                            (e.g. use --src=src for Eclipse/LDT) [default: .]
  -s --sound                Use afplay for feedback (sounds)
  -n --notify               Use terminal-notifier for feedback
  -c --color                Colorize output
  -l --logging              Log print() statements from Codea
  -p --polling=<interval>   Polling interval in seconds [default: 1]
  -v --verbose              Debug logging

  --pull                    Pulls
  --push                    Pushes

  -h --help                 Show this screen
'''

#not implemented yet
'''
  -o --overwrite            CAUTION - Overwrite the project in Codea with all
                            local changes since last connected (default is the
                            other way around - sync back any changes that were
                            made on your device); this is only useful if you
                            have more than one device

  -w --watches              Capture all parameter.watch from Codea to ./.watches

'''


import xcodeaserver_dev as x

DEV = False
DEV = True
import sys,time,os
from os.path import isdir,isfile,join,normpath
from os import listdir
import BaseHTTPServer
from docopt import docopt
import json

x.shutdown = None
x.counter=0
x.projectsRoot = '.'
x.srcdir = '.'
x.project = ''
x.cachefile = '.xcodea.cache'
if not os.path.isfile(x.cachefile):
	f=open(x.cachefile,'w')
	f.write('{}')
	f.close()
x.cache = json.load(open(x.cachefile))
x.ldtbuildpath = '.buildpath'

class XCodeaServer(BaseHTTPServer.BaseHTTPRequestHandler):
	def do_HEAD(self):
		if DEV:
			reload(x)
		x.do_HEAD(self)

	def do_GET(self):
		if DEV:
			reload(x)
		x.do_GET(self)

	def do_POST(self):
		if DEV:
			reload(x)
		x.do_POST(self)

	def do_PUT(self):
		if DEV:
			reload(x)
		x.do_PUT(self)

	def log_request(self, code='-', size='-'): #called by send_response()
		try:
			(200,204).index(code)
		except ValueError:
			self.log_message('"%s" %s %s',
		                 self.requestline, str(code), str(size))

if __name__ == '__main__':
	args = docopt(__doc__)
	proj=args['<projDir>']
	#x.notify = 'terminal-notifier' if args['--notify'] else None
	x.notify = args['--notify']
	x.sound = args['--sound']
	x.color = args['--color']
	x.pollingInterval = args['--polling']	
	x.logging = args['--logging']
	#x.watches = args['--watches']
	x.verbose = args['--verbose']
	#x.overwrite = args['--overwrite']
	x.projectsRoot = args['--root']
	x.srcdir = args['--src']
	x.pull = args['--pull']
	x.push = args['--push']

	proj = normpath(proj)

	if x.push:
		if not isdir(join(x.projectsRoot,proj)):
			print(x.colorwrap(x.RED,'Project '+proj+' not found!'))
			sys.exit(1)
		if not isfile(join(x.projectsRoot,proj,'Main.lua')):
			print(x.colorwrap(x.RED,'Project '+proj+' is not a valid Codea project!'))
			sys.exit(1)
	if proj=='xCodea':
		print('Better not :p')
		sys.exit(1)
	if not isdir(join(x.projectsRoot,proj)):
		print(x.colorwrap(x.RED,'Warning: project '+proj+' not found! Its folder will be created on successful connection'))
		print(x.colorwrap(x.RED,'If you are using LDT, better create an empty project *first* so that dependencies can be synced correctly'))
	x.project = proj
	httpd = BaseHTTPServer.HTTPServer(('', 49374), XCodeaServer)
	print(x.colorwrap(x.BLUE,'xCodea server started on port 49374'))
	if x.pull:
		print(x.colorwrap(x.RED,'Warning: will pull project '+proj+' from Codea. Any local files in the project or its dependencies will be overwritten or deleted.'))
	if x.push:
		print(x.colorwrap(x.RED,'Warning: will push project '+proj+' to Codea. Existing Codea tabs in the project or its dependencies will be overwritten or deleted.'))
	while not x.shutdown:
		httpd.handle_request()
#	httpd.serve_forever()
