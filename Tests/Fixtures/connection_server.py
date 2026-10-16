from http.server import ThreadingHTTPServer,BaseHTTPRequestHandler
from threading import Thread
import json
state={'capture':0,'ping':0,'range':0,'csrf':0,'mode':'online'}
class Handler(BaseHTTPRequestHandler):
 def log_message(self,*args): pass
 def send(self,status,body=b'',headers={}):
  self.send_response(status)
  for k,v in headers.items():self.send_header(k,v)
  self.send_header('Content-Length',str(len(body)));self.end_headers()
  if self.command!='HEAD':self.wfile.write(body)
 def data(self,status,data):self.send(status,json.dumps(data).encode(),{'Content-Type':'application/json'})
 def do_GET(self):
  c=self.headers.get('Cookie','')
  if self.path.startswith('/redirect/api/ping'):return self.send(302,headers={'Location':'http://localhost:18079/capture'})
  if self.path=='/capture':state['capture']+=1;return self.data(200,{})
  if self.path=='/fixture-state':return self.data(200,state)
  if self.server.server_port==2000:
   self.send_response(302);self.send_header('Set-Cookie','umbrel_fixture=fixture; Path=/; HttpOnly');self.send_header('Location','http://127.0.0.1:18079/');self.end_headers();return
  if self.path=='/fixture-login':
   self.send_response(302);self.send_header('Set-Cookie','sessionid=fixture; Path=/; HttpOnly');self.send_header('Set-Cookie','csrftoken=fixture; Path=/');self.send_header('Location','/');self.end_headers();return
  if self.path.startswith('/api/'):
   if state['mode']=='offline':self.close_connection=True;self.connection.close();return
   if state['mode']=='maintenance':return self.send(503,b'<html>Fixture maintenance</html>',{'Content-Type':'text/html'})
   if state['mode']=='expired':return self.data(403,{'detail':'Fixture session expired'})
   if 'sessionid=fixture' not in c:return self.data(403,{'detail':'Authentication credentials were not provided.'})
   if self.path.startswith('/api/ping'):state['ping']+=1;return self.data(200,{'response':'pong','user':1,'version':'fixture'})
   if self.path.startswith('/api/user/account'):return self.data(200,{'id':1,'name':'Fixture','is_superuser':False,'is_staff':False})
   if self.path.startswith('/api/video'):return self.data(200,{'data':[],'paginate':{'current_page':1,'last_page':1,'total_hits':0}})
   return self.data(200,{'data':[]})
  if 'umbrel_fixture=fixture' not in c:return self.send(302,headers={'Location':'http://127.0.0.1:2000/login'})
  signed='sessionid=fixture' in c
  html='''<!doctype html><meta name="viewport" content="width=device-width, initial-scale=1"><style>body{font:17px system-ui;padding:26px;background:#f4f4f7;color:#202024}h1{font-size:28px}button,a{display:block;padding:16px;background:#006deb;color:white;border-radius:14px;text-align:center;text-decoration:none;margin:24px 0}small{color:#666}</style><small>LOCAL TEST FIXTURE</small><h1>Tube Archivist</h1>'''
  html+= '<p>Signed in to the fixture server. Tap Finish above to connect TAClient.</p>' if signed else '<p>Umbrel handoff complete. Tube Archivist still requires its own sign-in.</p><a href="/fixture-login">Sign in to fixture</a>'
  html+='<p><small>This test page uses dummy session cookies and no owner credentials.</small></p><a href="http://localhost:18079/capture">Test blocked external redirect</a>'
  self.send(200,html.encode(),{'Content-Type':'text/html'})
 def do_POST(self):
  if self.path=='/fixture-mode':
   data=json.loads(self.rfile.read(int(self.headers.get('Content-Length','0'))));state['mode']=data['mode'];return self.data(200,{'mode':state['mode']})
  state['csrf']+=int(self.headers.get('X-CSRFToken')=='fixture')
  self.send(204)
for port in [18079,2000]:
 server=ThreadingHTTPServer(('127.0.0.1',port),Handler)
 Thread(target=server.serve_forever,daemon=True).start()
print('Local connection fixture ready on ports 18079 and 2000',flush=True)
Thread().join() if False else __import__('threading').Event().wait()
