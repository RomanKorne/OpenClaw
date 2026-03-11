#!/usr/bin/env python3
"""
Process Prompt Feedback from Airtable and create proposal pages in Notion.
"""
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

# find Agent Prompt page id
def find_agent_prompt():
    url='https://api.notion.com/v1/search'
    headers={'Authorization':f'Bearer {NOTION_TOKEN}','Notion-Version':'2022-06-28','Content-Type':'application/json'}
    res=call_json(url, method='POST', headers=headers, data={'query':'Agent Prompt (Strategos)'})
    for r in res.get('results',[]):
        props=r.get('properties',{})
        title=(props.get('title',{}).get('title',[{}])[0].get('plain_text','') if props.get('title') else '')
        if 'Agent Prompt' in title:
            return r.get('id')
    return None

def airtable_list_pending():
    url=f'https://api.airtable.com/v0/{BASE}/Prompt%20Feedback?filterByFormula=OR({{State}}='"'"'pending'"'"',{{State}}='"'"''"'"')'
    headers={'Authorization':f'Bearer {AIRTABLE_TOKEN}'}
    return call_json(url, headers=headers).get('records',[])

def notion_create_proposal(parent_page_id, title, body_text):
    url='https://api.notion.com/v1/pages'
    headers={'Authorization':f'Bearer {NOTION_TOKEN}','Notion-Version':'2022-06-28','Content-Type':'application/json'}
    data={
        'parent':{'type':'page_id','page_id':parent_page_id},
        'properties':{'title':{'title':[{'type':'text','text':{'content':title}}]}},
        'children':[{'object':'block','type':'paragraph','paragraph':{'rich_text':[{'type':'text','text':{'content':body_text}}]}}]
    }
    return call_json(url, method='POST', headers=headers, data=data)

# update airtable record state
def airtable_update_record(record_id, state):
    url=f'https://api.airtable.com/v0/{BASE}/Prompt%20Feedback'
    headers={'Authorization':f'Bearer {AIRTABLE_TOKEN}','Content-Type':'application/json'}
    return call_json(url, method='PATCH', headers=headers, data={'records':[{'id':record_id,'fields':{'State':state}}]})

parent=find_agent_prompt()
if not parent:
    print('Agent Prompt page not found')
    sys.exit(1)

pending=airtable_list_pending()
print('Pending records:',len(pending))
for rec in pending:
    rid=rec.get('id')
    f=rec.get('fields',{})
    uid=f.get('Action_ID')
    user_fb=f.get('User_Feedback')
    if user_fb=='Fix':
        title=f'Patch proposal: {uid or rid}'
        body=f'Suggestion from feedback {uid}\n\nFields: %s' % json.dumps(f)
        r=notion_create_proposal(parent, title, body)
        print('created proposal', r.get('id'))
        airtable_update_record(rid,'processed')
    elif user_fb=='OK':
        # mark processed (could implement counter logic later)
        airtable_update_record(rid,'processed')
        print('marked OK processed',rid)

