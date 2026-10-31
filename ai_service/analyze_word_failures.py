"""Read-only three-stage diagnosis on the frozen app development cohort.

Observe the actual head/decision returns, never replace their decision logic.
Every hooked replay must reproduce an unhooked replay at every input frame,
and the final events must also match the previously frozen component run.
"""
import argparse
from collections import Counter
import copy
import csv
import json
from pathlib import Path
import sys
import time
import numpy as np
from .diagnostic_replay import ATOL, RTOL, identity, plain
from .evaluate_fixed_components import digest, file_hash, write_json, InferenceMemo
from .review_fixed_components import verify


def new_session(engine, infer=None, embed=None):
    r = engine.runtime
    recognizer = copy.copy(engine.base)
    recognizer.config = copy.deepcopy(engine.base.config)
    h = engine.base.word_head
    recognizer.word_head = r.TemporalWordHead(list(h.labels), copy.deepcopy(h.config),
        h.infer if infer is None else infer, embed=h.embed if embed is None else embed,
        centers=h.centers, mean=h.mean, std=h.std, probability_fusion=h.probability_fusion)
    recognizer.set_mode('words')
    return r.LiveSession(recognizer, False)


def head_snapshot(head, loc, returned, truth):
    j = head.names.index(truth)
    result = dict(diagnostic=plain(head.last_diagnostics),
        target_score=float(returned[0][head.labels.index(truth)]),
        target_ready=bool(returned[1][head.labels.index(truth)]),
        windows=[])
    if not loc.get('batches'): return result
    probabilities = loc['probabilities']
    for k in range(len(probabilities)):
        winner = int(loc['raw_top'][k])
        result['windows'].append(dict(index=k, selected=k == loc['best'],
            raw_top=head.names[winner] if winner < len(head.names) else '__background__',
            target_score=float(probabilities[k,j]),
            target_rank=int(np.count_nonzero(probabilities[k] > probabilities[k,j]))+1,
            target_supported=bool(loc['masks'][k][j]),
            eligible_after_primary_preference=bool(loc['eligible'][k]),
            primary_eligible=bool(loc['primary_eligible'][k]),
            raw_supported=bool(loc['raw_supported'][k]),
            coverage=float(loc['coverage'][k]), observations=int(loc['observations'][k]),
            winner_margin=float(loc['raw_margin'][k]),
            required_score=float(loc['required_score'][k]),
            required_margin=float(loc['required_margin'][k]),
            swapped=bool(loc['variants'][k])))
    return result


def decision_snapshot(decision, loc, returned, truth):
    confirmed, ranked, gap, reliable = returned
    top = int(loc['top'])
    ready = loc['ready_for'](top)
    blockers = []
    if decision.smoothed[top] < loc['minimum']: blockers.append('score')
    if gap < loc['margin']: blockers.append('margin')
    if loc['needs_sequence'] and not ready: blockers.append('head_readiness')
    if bool(blockers) == bool(reliable): raise RuntimeError('Decision blocker interpretation disagrees with runtime')
    return dict(top=decision.labels[top], score=float(decision.smoothed[top]),
        target_score=float(decision.smoothed[decision.labels.index(truth)]),
        margin=float(gap), minimum=float(loc['minimum']), minimum_margin=float(loc['margin']),
        ready=bool(ready), reliable=bool(reliable), blockers=blockers,
        candidate=None if decision.candidate is None else decision.labels[decision.candidate],
        candidate_since=float(decision.since),
        candidate_elapsed=float(loc['now']-decision.since) if reliable else None,
        dwell=float(loc['dwell']) if reliable else None,
        locked=bool(loc.get('locked', False)),
        confirmed=None if confirmed is None else decision.labels[confirmed])


def replay_trace(engine, arrays, truth, expected):
    h = engine.base.word_head
    infer, embed = InferenceMemo(h.infer), InferenceMemo(h.embed)
    session = new_session(engine, infer, embed)
    head = session.recognizer.word_head
    head_code = type(head).predict.__code__
    decision_code = type(session.decision).update.__code__
    pending = {}
    steps = []

    def profile(frame, event, returned):
        if event != 'return': return
        if frame.f_code is head_code and frame.f_locals['self'] is head:
            pending['head'] = head_snapshot(head, frame.f_locals, returned, truth)
        elif frame.f_code is decision_code and frame.f_locals['self'] is session.decision:
            pending['decision'] = decision_snapshot(session.decision, frame.f_locals, returned, truth)

    snapshots = []
    previous_profile = sys.getprofile()
    try:
        sys.setprofile(profile)
        for p,w,now,context in zip(*arrays):
            pending.clear()
            before = len(session.events)
            session.update(p,w,float(now),context=context)
            if pending:
                if set(pending) != {'head','decision'}: raise RuntimeError('Incomplete observed prediction')
                steps.append(dict(time=float(now), **pending,
                    emitted=copy.deepcopy(session.events[before:])))
            scores = session.decision.smoothed
            snapshots.append((None if scores is None else scores.copy(),plain(session.output)))
    finally:
        sys.setprofile(previous_profile)
    if plain(session.events) != expected['events']:
        raise RuntimeError('Hooked events differ from frozen reference')
    control = new_session(engine, infer, embed)
    for index,(p,w,now,context) in enumerate(zip(*arrays)):
        control.update(p,w,float(now),context=context)
        wanted, wanted_output = snapshots[index]
        actual = control.decision.smoothed
        if actual is None or wanted is None:
            if actual is not None or wanted is not None: raise RuntimeError('Null score control mismatch')
        elif not np.allclose(actual,wanted,atol=ATOL,rtol=RTOL):
            raise RuntimeError('Hook changed score vector')
        # Integer rankings/flags/events and numeric output are deterministic here:
        # identical model inputs are memoized within this paired control.
        if plain(control.output) != wanted_output: raise RuntimeError('Hook changed output')
    if plain(control.events) != expected['events']: raise RuntimeError('Unhooked event control mismatch')
    return steps, plain(session.events), dict(input_frames=len(snapshots),
        all_input_scores_equal=True,all_input_outputs_equal=True,frozen_events_equal=True)


def cut_snapshot(engine, arrays, truth):
    r = engine.runtime
    pose,wrist,times,context=arrays
    p,w=r.prepare_sign_sequence(pose,wrist)
    usable=int(np.any(p!=0,axis=1).sum())
    if usable<3:
        return dict(top=None,target_score=None,target_ready=False,available=False,
            unavailable_reason='fewer_than_3_usable_hand_frames',usable_hand_frames=usable,
            diagnostic=dict(inference_ran=False),first=None,last=None,
            future_boundary_used=True,not_a_live_prediction=True)
    first,last=r.gesture_interval(p,w,context)
    observed=np.any(pose[first:last].reshape(-1,2,21,3)!=0,axis=(2,3))
    head=new_session(engine).recognizer.word_head
    scores,ready=head.predict([(pose[first:last],wrist[first:last],context[first:last],times[first:last],observed)])
    top=int(np.argmax(scores));j=head.labels.index(truth)
    return dict(top=head.labels[top] if scores[top]>=0 else None,available=True,
        target_score=float(scores[j]),target_ready=bool(ready[j]),
        diagnostic=plain(head.last_diagnostics),first=int(first),last=int(last),
        future_boundary_used=True,not_a_live_prediction=True)


def classify(truth, cut, steps, events):
    """Ordered observed-state categories, not causal proof or oracle accuracy."""
    final=events[-1]['label'] if events else None
    target_emissions=[e for e in events if e['label']==truth]
    all_windows=[w for s in steps for w in s['head']['windows']]
    qualified=[s for s in steps if s['decision']['top']==truth and s['decision']['reliable']]
    head_ready=[s for s in steps if s['head']['target_ready']]
    any_eligible=any(w['raw_top']==truth and w['eligible_after_primary_preference'] for w in all_windows)
    any_top=any(w['raw_top']==truth for w in all_windows)
    mature=[s for s in qualified if s['decision']['candidate_elapsed']+1e-6>=s['decision']['dwell']]
    unexplained=[s['time'] for s in mature if s['decision']['confirmed']!=truth and not s['decision']['locked']]
    if final==truth: category='final_correct'
    elif target_emissions: category='target_emitted_then_other_label'
    elif mature: category='mature_target_without_completed_event'
    elif qualified: category='qualified_target_run_shorter_than_dwell'
    elif head_ready: category='head_ready_but_no_reliable_target_decision'
    elif any_eligible: category='eligible_target_window_not_confirmed'
    elif any_top: category='target_top_but_head_gates_not_met'
    elif all_windows: category='target_never_top_in_live_windows'
    else: category='no_usable_live_inference'
    # Startup and windows with no neural inference are excluded from denominators.
    evidence=[s for s in steps if s['head']['diagnostic'].get('inference_ran')]
    target_top=[s for s in evidence if s['decision']['top']==truth]
    combinations=Counter('+'.join(s['decision']['blockers']) or 'qualified'
                         for s in target_top)
    totals=sum(combinations.values())
    return dict(category=category,cut_top_correct=cut['top']==truth,
        cut_target_qualified=cut['target_ready'],live_any_target_top=any_top,
        live_any_eligible_target=any_eligible,selected_target_ready_steps=len(head_ready),
        reliable_target_steps=len(qualified),mature_target_steps=len(mature),
        maximum_candidate_elapsed=max((s['decision']['candidate_elapsed'] for s in qualified),default=None),
        unexplained_mature_target_times=unexplained,
        inference_steps=len(evidence),decision_target_top_steps=len(target_top),
        target_top_blocker_fraction={k:v/totals for k,v in combinations.items()} if totals else {},
        wrong_events=sum(e['label']!=truth for e in events),
        consecutive_duplicate_events=sum(a['label']==b['label'] for a,b in zip(events,events[1:])))


def summarize(rows, words):
    def group(items):
        categories=Counter(x['classification']['category'] for x in items)
        failed=[x for x in items if x['classification']['category']!='final_correct']
        target_top=[x for x in failed if x['classification']['target_top_blocker_fraction']]
        keys=sorted({k for x in target_top for k in x['classification']['target_top_blocker_fraction']})
        return dict(clips=len(items),words=len({x['item']['label'] for x in items}),
            categories=dict(categories),cut_correct=sum(x['classification']['cut_top_correct'] for x in items),
            cut_unavailable=sum(not x['cut']['available'] for x in items),
            cut_qualified=sum(x['classification']['cut_target_qualified'] for x in items),
            failed_clips=len(failed),failed_with_target_top=len(target_top),
            mean_clip_normalized_blocker_fraction={k:float(np.mean([
                x['classification']['target_top_blocker_fraction'].get(k,0.) for x in target_top])) for k in keys},
            unexplained_mature_target=sum(bool(x['classification']['unexplained_mature_target_times']) for x in items),
            false_accept_per_minute=None,real_background_measured=False)
    cal=[x for x in rows if x['item']['role']=='calibration_development']
    result=dict(development_only=True,deployment_eligible=False,automatic_policy_selection=False,
        overall=group(cal),excluding_unverified_chao_khangcn=group([x for x in cal if not x['item']['unverified_chao_khangcn']]),
        by_source={s:group([x for x in cal if x['item']['source']==s]) for s in sorted({x['item']['source'] for x in cal})},
        by_word={w:group([x for x in cal if x['item']['label']==w]) for w in words},
        controls_passed=len(rows),words_without_calibration=[w for w in words if not any(x['item']['label']==w for x in cal)])
    wrong=[]
    for row in cal:
        for step in row['steps']:
            for event in step['emitted']:
                if event['label']!=row['item']['label']:
                    wrong.append(dict(video_id=row['item']['video_id'],truth=row['item']['label'],
                        source=row['item']['source'],event=event,decision=step['decision'],head=step['head']['diagnostic']))
    result['wrong_event_evidence']=wrong
    return result


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--input',type=Path,required=True)
    p.add_argument('--model-dir',type=Path,required=True)
    p.add_argument('--output',type=Path,required=True)
    p.add_argument('--smoke',action='store_true')
    a=p.parse_args()
    contract,rows,_=verify(a.input)
    from .engine import Engine
    engine=Engine(a.model_dir)
    if identity(engine,'words')!=contract['model_identity']: raise ValueError('Frozen identity changed')
    before_identity=identity(engine,'words')
    cal=[x for x in rows if x['item']['role']=='calibration_development']
    if a.smoke:
        # Deterministic engineering controls: first 3 of each final outcome.
        cal=sum(([x for x in cal if ('none' if x['results']['reference']['pred'] is None else
            'correct' if x['results']['reference']['pred']==x['item']['label'] else 'wrong')==state][:3]
            for state in ('correct','none','wrong')),[])
    registered=dict(version=1,smoke=a.smoke,tool_sha256=file_hash(__file__),
        dependency_sha256={f:file_hash(Path(__file__).with_name(f)) for f in
            ('review_fixed_components.py','evaluate_fixed_components.py','diagnostic_replay.py')},
        input_contract_sha256=digest(contract),model_identity=before_identity,
        cohort_ids=[x['item']['video_id'] for x in cal],
        rule='Observed state partition only; cut boundary uses future, no label-specific exceptions or threshold search',
        dominant_definition='strictly more than 50 percent of failed clips in one exclusive category; otherwise mixed',
        control='all input score vectors atol2e-5 rtol5e-4; all output/ranking/flags and frozen events exact')
    a.output.mkdir(parents=True,exist_ok=True)
    contract_path=a.output/'contract.json'
    if contract_path.exists() and json.loads(contract_path.read_text(encoding='utf-8'))!=registered:
        raise ValueError('Changed diagnostic contract; choose a new output directory')
    write_json(contract_path,registered)
    journal=a.output/'results.jsonl'
    done={}
    if journal.exists():
        for line in journal.read_text(encoding='utf-8').splitlines():
            row=json.loads(line);key=row['item']['video_id']
            if key in done or row['diagnostic_contract_sha256']!=digest(registered): raise ValueError('Invalid journal')
            done[key]=row
    expected={x['item']['video_id']:x for x in cal}
    if set(done)-set(expected): raise ValueError('Unknown resumed rows')
    for key,row in done.items():
        if row['item']!=expected[key]['item'] or row['features']!=expected[key]['features']:
            raise ValueError('Resumed row source mismatch')
    started=time.perf_counter()
    for source in cal:
        key=source['item']['video_id']
        if key in done: continue
        with np.load(a.input/'features'/(key+'.npz'),allow_pickle=False) as z:
            arrays=tuple(z[k].copy() for k in ('pose','wrist','times','context'))
        steps,events,control=replay_trace(engine,arrays,source['item']['label'],source['results']['reference'])
        cut=cut_snapshot(engine,arrays,source['item']['label'])
        row=dict(item=source['item'],features=source['features'],diagnostic_contract_sha256=digest(registered),
            cut=cut,events=events,steps=steps,control=control,
            classification=classify(source['item']['label'],cut,steps,events))
        with journal.open('a',encoding='utf-8') as f:
            f.write(json.dumps(plain(row),ensure_ascii=False,allow_nan=False)+'\n');f.flush()
        done[key]=row
        write_json(a.output/'status.json',dict(processed=len(done),expected=len(cal),complete=len(done)==len(cal)))
        if len(done)%20==0 or len(done)==len(cal): print(f'{len(done)}/{len(cal)} replayed',flush=True)
    if identity(engine,'words')!=before_identity: raise RuntimeError('Analysis mutated engine identity')
    report=summarize([done[x['item']['video_id']] for x in cal],engine.base.word_head.names)
    report['contract_sha256']=digest(registered)
    report['complete']=len(done)==len(cal)
    report['engineering_smoke_only']=a.smoke
    write_json(a.output/'summary.json',report)
    with (a.output/'all-181-words-failures.csv').open('w',encoding='utf-8-sig',newline='') as f:
        fields=['word','clips','cut_correct','cut_qualified','failed_clips','categories','status']
        writer=csv.DictWriter(f,fieldnames=fields);writer.writeheader()
        for word,stats in report['by_word'].items():
            writer.writerow(dict(word=word,**{k:stats[k] for k in fields[1:5]},
                categories=json.dumps(stats['categories'],ensure_ascii=False),
                status='development_only' if stats['clips'] else 'no_calibration_data'))
    print(json.dumps(dict(overall=report['overall'],elapsed_seconds=time.perf_counter()-started,
        output=str(a.output.resolve())),ensure_ascii=True,indent=2),flush=True)


if __name__=='__main__': main()
