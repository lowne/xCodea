#!/usr/local/bin/python2.7
# encoding: utf-8
''' xCodea server


Usage: 
  xcodeaserver.py <projDir> [--root=<projectsRoot>] [--src=<srcSubDir>]
                            [--color] [--notify|--sound] [--logging]
                            [--polling=<interval>] [--verbose]
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
from os.path import isdir,join,normpath
from os import listdir
import BaseHTTPServer
from docopt import docopt
import json

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
	proj = normpath(proj)
	if not isdir(join(x.projectsRoot,proj)):
		print('Project '+proj+' not found!')
		sys.exit(1)
	if proj=='xCodea':
		print('Better not :p')
		sys.exit(1)
	x.project = proj
	httpd = BaseHTTPServer.HTTPServer(('', 49374), XCodeaServer)
	print(x.colorwrap(x.BLUE,'xCodea server started on port 49374'))
	httpd.serve_forever()
