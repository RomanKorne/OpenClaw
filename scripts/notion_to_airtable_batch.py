#!/usr/bin/env python3
import os,sys,json,urllib.request,urllib.error
NOTION_TOKEN=os.environ.get('NOTION_API_KEY')
AIRTABLE_TOKEN=os.environ.get('AIRTABLE_API_KEY')
BASE='appB2VMy9GXqq0I8O'
if not NOTION_TOKEN or not AIRTABLE_TOKEN:
    print('Missing tokens'); sys.exit(1)

def call_json(url, method='GET', headers=None, data=None):
    if headers is None: headers={}
    req=urllib.request.Request(url, method=method)
    for k,v in headers.items(): req.add_header(k,v)
    if data is not None:
        bdata=json.dumps(data).encode('utf-8')
        req.data=bdata
    try:
        with urllib.request.urlopen(req, timeout=30) as f:
            return json.load(f)
    except urllib.error.HTTPError as e:
        try:
            body=e.read().decode('utf-8')
            return json.loads(body)
        except Exception:
            return {'error':str(e)}

def notion_search():
    url='https://api.notion.com/v1/search'
    headers={'Authorization':f'Bearer {NOTION_TOKEN}','Notion-Version':'2022-06-28','Content-Type':'application/json'}
    return call_json(url, method='POST', headers=headers, data={}).get('results',[])

def airtable_get_titles():
    url=f'https://api.airtable.com/v0/{BASE}/Memories'
    headers={'Authorization':f'Bearer {AIRTABLE_TOKEN}'}
    r=call_json(url, headers=headers)
    records=r.get('records',[])
    return { (rec.get('fields',{}).get('Title') or '').strip(): rec for rec in records }

def airtable_add(records):
    url=f'https://api.airtable.com/v0/{BASE}/Memories'
    headers={'Authorization':f'Bearer {AIRTABLE_TOKEN}','Content-Type':'application/json'}
    return call_json(url, method='POST', headers=headers, data={'records':records})

pages=notion_search()
existing=airtable_get_titles()
to_add=[]
for p in pages:
    title=''
    try:
        title = p.get('properties',{}).get('title',{}).get('title',[{}])[0].get('plain_text','')
    except Exception:
        title=''
    if not title:
        title = p.get('url') or p.get('id') or ''
    title=title.strip()
    if not title or title in existing:
        continue
    link = p.get('url') or f"https://www.notion.so/{p.get('id')}"
    to_add.append({'fields':{'Title': title, 'Notion Link': link}})

if not to_add:
    print('Nothing to add')
    sys.exit(0)
print('Adding', len(to_add),'records in batches of 10')
for i in range(0, len(to_add), 10):
    chunk = to_add[i:i+10]
    resp = airtable_add(chunk)
    print('batch', i, '->', resp.get('records', []) and len(resp.get('records')) or resp)

