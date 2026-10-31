"""Recompute a completed fusion calibration journal; never opens audit arrays."""
import argparse
import csv
import json
from pathlib import Path
import sys
import numpy as np
from .calibrate_new_fusion import SPECS,CAL,EPOCH,selection,summarize_group
from .evaluate_fixed_components import file_hash,digest,metrics,write_json
from .compare_colab_checkpoints import select_cohort,verify_original_metadata


def verify(root,original,checkpoints,assets,webcam):
    contract=json.loads((root/'contract.json').read_bytes());base=contract['experiment']
    report=json.loads((root/'comparison.json').read_bytes())
    if contract['smoke'] or report['smoke_only'] or not report['complete']:raise ValueError('Need completed FULL run')
    if digest(base)!=contract['experiment_sha256'] or report['experiment_sha256']!=digest(base):raise ValueError('Experiment digest differs')
    if file_hash(Path(__file__).with_name('calibrate_new_fusion.py'))!=base['code_sha256']:raise ValueError('Experiment code changed')
    if file_hash(Path(__file__).parents[1]/'docs/FUSION_CALIBRATION_PROTOCOL_20261022.md')!=base['protocol_sha256']:
        raise ValueError('Registered protocol changed')
    for name,sha in base['dependencies'].items():
        if file_hash(Path(__file__).with_name(name))!=sha:raise ValueError('Dependency changed')
    if file_hash(assets/'inventory.json')!=base['assets_inventory_sha256']:raise ValueError('Assets inventory changed')
    if file_hash(webcam)!=base['webcam_sha256']:raise ValueError('Webcam recording changed')
    inventory=json.loads((assets/'inventory.json').read_bytes())
    for name,sha in inventory['shared_expected'].items():
        if file_hash(assets/name)!=sha:raise ValueError('Asset changed')
    for spec in inventory['models']:
        if file_hash(assets/spec['model'])!=spec['model_sha256'] or file_hash(assets/spec['config'])!=spec['config_sha256']:
            raise ValueError('Checkpoint changed')
    old=json.loads((original/'contract.json').read_bytes())
    raw=[json.loads(s) for s in (original/'results.jsonl').read_text(encoding='utf-8').splitlines()]
    verify_original_metadata(raw,old)
    allowed,excluded=select_cohort(raw,json.loads((assets/'training_identity.json').read_bytes()))
    if (base['original_contract_sha256']!=digest(old) or base['model_identity']!=old['model_identity']
            or base['excluded_audit']!=excluded or base['all_permitted_items']!=[r['item'] for r in allowed]):
        raise ValueError('Cohort/source contract differs')
    expected={r['item']['video_id']:r for r in allowed}
    prior_contract=json.loads((checkpoints/'contract.json').read_bytes())
    if digest(prior_contract)!=base['checkpoint_contract_sha256'] or file_hash(checkpoints/'results.jsonl')!=base['checkpoint_results_sha256']:
        raise ValueError('Prior checkpoint controls differ')
    prior={r['item']['video_id']:r for s in (checkpoints/'results.jsonl').read_text(encoding='utf-8').splitlines() if (r:=json.loads(s))}
    rows=[json.loads(s) for s in (root/'results.jsonl').read_text(encoding='utf-8').splitlines()]
    ids=[r['item']['video_id'] for r in rows]
    if len(ids)!=204 or len(set(ids))!=204 or set(ids)!=set(expected):raise ValueError('Incomplete/duplicate/unexpected cohort')
    if contract['cohort']!=[r['item'] for r in allowed]:raise ValueError('Changed cohort ordering')
    choice=selection(rows)
    frozen=json.loads((root/'frozen-nominee.json').read_bytes())
    if choice!=report['selection'] or frozen!=dict(experiment_sha256=digest(base),**choice):raise ValueError('Nomination differs')
    epoch_names=list(dict.fromkeys(['app','anchor',choice['nominee']]))
    words=json.loads((assets/'latest137_word_temporal_config.json').read_bytes())['labels']
    for row in rows:
        key=row['item']['video_id'];source=expected[key]['original'];names=['app',*SPECS] if row['item']['role']==CAL else epoch_names
        if row['item']!=expected[key]['item'] or row['features']!=source['features'] or set(row['results'])!=set(names):
            raise ValueError('Journal row differs')
        if row['contract_sha256']!=digest(contract) or not row['null_controls_passed']:raise ValueError('Null control/contract failed')
        for name,old_name in [('app','app'),('anchor','latest137_pair_fixed')]:
            if row['results'][name]!={k:prior[key]['results'][old_name][k] for k in ('pred','events')}:
                raise ValueError('Frozen reference does not match')
        # Audit IDs are absent from expected and cannot reach this I/O.
        feature=original/'features'/(key+'.npz')
        if file_hash(feature)!=row['features']['feature_sha256'] or file_hash(original/'sources'/(key+'.mp4'))!=row['features']['source_sha256']:
            raise ValueError('Feature/source changed')
        with np.load(feature,allow_pickle=False) as z:
            if len(z['times'])!=row['frames_controlled']:raise ValueError('Partial frame control')
            end=float(z['times'][-1])
        for value in row['results'].values():
            events=value['events']
            if value['pred']!=(events[-1]['label'] if events else None):raise ValueError('Final prediction differs from events')
            if any(e['label'] not in words or not 0<=e['time']<=end+.002 for e in events):raise ValueError('Invalid event')
            if any(a['time']>b['time'] for a,b in zip(events,events[1:])):raise ValueError('Reordered events')
    cal=[r for r in rows if r['item']['role']==CAL];epoch=[r for r in rows if r['item']['role']==EPOCH]
    small=[r for r in cal if not r['item']['unverified_chao_khangcn']]
    if (len(cal),len(small),len(epoch))!=(95,94,109):raise ValueError('Role size changed')
    for field,subset,names in [('calibration',cal,['app',*SPECS]),('calibration_excluding_unverified',small,['app',*SPECS]),('epoch',epoch,epoch_names)]:
        if report[field]!=summarize_group(subset,names):raise ValueError('Metrics/paired report do not recompute')
    capture=json.loads(webcam.read_bytes())
    expected_batches=sum(len(m.get('worker_diagnostic',{}).get('records',[])) for m in capture['messages'])
    control=report['webcam']['branches']['app']['control']
    if not control['passed'] or control['batches']!=expected_batches:raise ValueError('Webcam control failed')
    if report['audit_arrays_loaded'] or report['deployment_eligible'] or report['real_background_measured']:
        raise ValueError('Unjustified evaluation/deployment claim')
    return rows,words,report


def main():
    if hasattr(sys.stdout,'reconfigure'):sys.stdout.reconfigure(encoding='utf-8')
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('root',type=Path)
    for name in ('original','checkpoints','assets','webcam'):p.add_argument('--'+name,required=True,type=Path)
    a=p.parse_args();rows,words,report=verify(a.root,a.original,a.checkpoints,a.assets,a.webcam)
    cal=[r for r in rows if r['item']['role']==CAL and not r['item']['unverified_chao_khangcn']]
    epoch=[r for r in rows if r['item']['role']==EPOCH];nominee=report['selection']['nominee']
    table=[]
    for word in words:
        c=[r for r in cal if r['item']['label']==word];e=[r for r in epoch if r['item']['label']==word]
        row=dict(word=word,selection_videos=len(c),epoch_videos=len(e),status='development_only' if c else 'no_selection_sample')
        for name in ('app',*SPECS):
            for role,subset in [('selection',c),('epoch',e)]:
                measured=role=='selection' or name in report['epoch']['metrics']
                m=metrics(subset,name) if measured else None
                for k in ('correct','wrong','none','wrong_events'):row[name+'_'+role+'_'+k]=m[k] if m is not None and subset else ''
        table.append(row)
    with (a.root/'all-181-words.csv').open('w',encoding='utf-8-sig',newline='') as f:
        writer=csv.DictWriter(f,fieldnames=list(table[0]));writer.writeheader();writer.writerows(table)
    by_source={source:{name:metrics([r for r in cal if r['item']['source']==source],name) for name in ('app',*SPECS)}
        for source in sorted({r['item']['source'] for r in cal})}
    m=report['calibration_excluding_unverified']['metrics'];app=m['app'];after=m[nominee]
    checks=dict(correct_increased=after['correct']>app['correct'],macro_recall_increased=after['macro_recall']>app['macro_recall'],
        precision_not_lower=after['accepted_precision'] is not None and after['accepted_precision']>=max(.95,app['accepted_precision'] or 0),
        wrong_not_increased=after['wrong']<=app['wrong'],wrong_events_not_increased=after['wrong_events']<=app['wrong_events'],
        duplicates_not_increased=after['consecutive_duplicate_events']<=app['consecutive_duplicate_events'])
    reading=dict(verified=True,clips=len(rows),selection_videos=94,epoch_videos=109,audit_excluded=93,
        nominee=nominee,reason=report['selection']['reason'],app_comparison_checks=checks,
        app_development_screen_passed=all(checks.values()),deployment_eligible=False,by_source=by_source,
        missing_selection_words=[r['word'] for r in table if not r['selection_videos']],
        missing_both_words=[r['word'] for r in table if not r['selection_videos'] and not r['epoch_videos']],
        ci_caution='Singleton/small clusters and reused development data; descriptive CI and unadjusted p-values are not a promotion test',
        calibration_exposures='Already used repeatedly in earlier experiments; this adds six registered full-stream operating points')
    write_json(a.root/'verified-reading.json',reading)
    print(json.dumps({k:v for k,v in reading.items() if k not in ('by_source','missing_selection_words')},ensure_ascii=False,indent=2))


if __name__=='__main__':main()
