#!/usr/bin/env python3
"""
Apply patches automatically when feedback conditions met (N=3 OK).
"""
import os,sys,json,urllib.request,urllib.error
NOTION_TOKEN=os.environ.get('NOTION_API_KEY')
AIRTABLE_TOKEN=os.environ.get('AIRTABLE_API_KEY')
BASE='appB2VMy9GXqq0I8O'
N=3
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

# helper
def airtable_list_all():
    url=f'https://api.airtable.com/v0/{BASE}/Prompt%20Feedback'
    headers={'Authorization':f'Bearer {AIRTABLE_TOKEN}'}
    return call_json(url, headers=headers).get('records',[])

def append_to_agent_prompt(text):
    # find agent prompt page
    search_url='https://api.notion.com/v1/search'
    headers={'Authorization':f'Bearer {NOTION_TOKEN}','Notion-Version':'2022-06-28','Content-Type':'application/json'}
    res=call_json(search_url, method='POST', headers=headers, data={'query':'Agent Prompt (Strategos)'})
    pid=None
    for r in res.get('results',[]):
        props=r.get('properties',{})
        title=(props.get('title',{}).get('title',[{}])[0].get('plain_text','') if props.get('title') else '')
        if 'Agent Prompt' in title:
            pid=r.get('id'); break
    if not pid:
        return {'error':'no parent'}
    # append child
    url='https://api.notion.com/v1/blocks/%s/children' % pid
    headers={'Authorization':f'Bearer {NOTION_TOKEN}','Notion-Version':'2022-06-28','Content-Type':'application/json'}
    data={'children':[{'object':'block','type':'paragraph','paragraph':{'rich_text':[{'type':'text','text':{'content':text}}]}}]}
    return call_json(url, method='PATCH', headers=headers, data=data)

records=airtable_list_all()
# group by Action_ID
by_action={}
for r in records:
    f=r.get('fields',{})
    aid=f.get('Action_ID') or r.get('id')
    by_action.setdefault(aid,[]).append((r.get('id'), f))

applied_any=False
for aid, items in by_action.items():
    oks=[i for i in items if i[1].get('User_Feedback')=='OK']
    fixes=[i for i in items if i[1].get('User_Feedback')=='Fix']
    # if there are >=N OK and at least one Fix previously, apply
    if len(oks)>=N and fixes:
        # prepare patch text
        patch_text='Auto-applied patch for %s based on %d OKs and %d Fixes.' % (aid, len(oks), len(fixes))
        # include suggested_patch if present
        sp = fixes[-1][1].get('Suggested_Patch') or ''
        if sp:
            patch_text += '\n\nSuggested patch:\n' + sp
        r=append_to_agent_prompt(patch_text)
        print('applied to notion:', r)
        # mark all related feedback as applied
        rec_ids=[x[0] for x in items]
        url=f'https://api.airtable.com/v0/{BASE}/Prompt%20Feedback'
        headers={'Authorization':f'Bearer {AIRTABLE_TOKEN}','Content-Type':'application/json'}
        data={'records':[{'id':rid,'fields':{'State':'applied'}} for rid in rec_ids]}
        call_json(url, method='PATCH', headers=headers, data=data)
        applied_any=True

if not applied_any:
    print('No patches to apply')
