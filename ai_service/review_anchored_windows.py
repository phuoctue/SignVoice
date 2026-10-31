"""Independent journal/event checks and a human-readable anchored-window report."""
import argparse
from collections import Counter
import csv
import json
import math
from pathlib import Path
import numpy as np
from .evaluate_fixed_components import digest,file_hash,metrics,write_json


def exact_discordance_p(gained,lost):
    n=gained+lost
    if not n:return 1.
    return min(1.,2*sum(math.comb(n,k) for k in range(min(gained,lost)+1))/2**n)


def verify(root,original,word_config):
    contract=json.loads((root/'contract.json').read_text(encoding='utf-8'))
    report=json.loads((root/'comparison.json').read_text(encoding='utf-8'))
    if contract['smoke'] or not report['complete']:raise ValueError('Incomplete full evaluation')
    if file_hash(Path(__file__).with_name('experiment_anchored_windows.py'))!=contract['code_sha256']:
        raise ValueError('Experiment changed after run')
    for name,value in contract['dependencies'].items():
        if file_hash(Path(__file__).with_name(name))!=value:raise ValueError('Experiment dependency changed')
    old=json.loads((original/'contract.json').read_text(encoding='utf-8'))
    if digest(old)!=contract['input_contract_sha256'] or old['model_identity']!=contract['model_identity']:
        raise ValueError('Original identity changed')
    if file_hash(word_config)!=contract['model_identity']['model_hashes']['word_temporal_config.json']:
        raise ValueError('Word config is from another bundle')
    words=json.loads(word_config.read_text(encoding='utf-8'))['labels']
    if len(words)!=181 or len(set(words))!=181:raise ValueError('Unexpected vocabulary')
    expected={r['item']['video_id']:r for line in (original/'results.jsonl').read_text(encoding='utf-8').splitlines()
        if (r:=json.loads(line))['item']['role']=='calibration_development'}
    rows=[json.loads(line) for line in (root/'results.jsonl').read_text(encoding='utf-8').splitlines()]
    ids=[r['item']['video_id'] for r in rows]
    if len(ids)!=297 or len(set(ids))!=297 or set(ids)!=set(expected) or ids!=contract['cohort_ids']:
        raise ValueError('Wrong cohort/order/duplicate rows')
    for row in rows:
        key=row['item']['video_id'];reference=expected[key]
        if row['item']!=reference['item'] or row['features']!=reference['features']:
            raise ValueError('Changed source metadata')
        if row['contract_sha256']!=digest(contract) or not row['results']['null_control_passed']:
            raise ValueError('Contract/null control mismatch')
        if row['results']['reference']['events']!=reference['results']['reference']['events']:
            raise ValueError('Changed reference event history')
        if row['results']['anchored']['window_stats']['added_windows']==0:
            if row['results']['anchored']['events']!=row['results']['reference']['events']:
                raise ValueError('Candidate changed events without adding a window')
        feature=original/'features'/(key+'.npz')
        if file_hash(feature)!=row['features']['feature_sha256']:raise ValueError('Changed feature')
        if file_hash(original/'sources'/(key+'.mp4'))!=row['features']['source_sha256']:raise ValueError('Changed source')
        with np.load(feature,allow_pickle=False) as z:
            length=len(z['times']);end=float(z['times'][-1])
        if row['results']['input_frames_controlled']!=length:raise ValueError('Partial input control')
        for branch in ('reference','anchored'):
            result=row['results'][branch];events=result['events']
            if result['pred']!=(events[-1]['label'] if events else None):raise ValueError('Final/event mismatch')
            if any(e['label'] not in words or not 0<=e['time']<=end+.002 for e in events):raise ValueError('Invalid event')
            if any(a['time']>b['time'] for a,b in zip(events,events[1:])):raise ValueError('Reordered event')
    for branch in ('reference','anchored'):
        if metrics(rows,branch)!=report[branch]:raise ValueError('Metrics do not recompute')
    if (report['reference']['correct'],report['reference']['wrong'],report['reference']['none'])!=(171,8,118):
        raise ValueError('Reference baseline changed')
    if report['deployment_eligible'] or report['real_background_measured']:raise ValueError('Unjustified promotion/background claim')
    return contract,report,rows,words


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('root',type=Path);p.add_argument('--original',type=Path,required=True)
    p.add_argument('--word-config',type=Path,required=True);p.add_argument('--report',type=Path,required=True)
    a=p.parse_args();contract,report,rows,words=verify(a.root,a.original,a.word_config)
    table=[]
    for word in words:
        subset=[r for r in rows if r['item']['label']==word]
        before,after=(metrics(subset,name) for name in ('reference','anchored'))
        table.append(dict(word=word,clips=len(subset),status='development_only' if subset else 'no_calibration_data',
            correct_before=before['correct'],correct_after=after['correct'],wrong_before=before['wrong'],wrong_after=after['wrong'],
            none_before=before['none'],none_after=after['none'],wrong_events_before=before['wrong_events'],wrong_events_after=after['wrong_events']))
    assert len(table)==181 and sum(t['clips'] for t in table)==297
    with (a.root/'all-181-words-comparison.csv').open('w',encoding='utf-8-sig',newline='') as f:
        writer=csv.DictWriter(f,fieldnames=list(table[0]));writer.writeheader();writer.writerows(table)
    changed=[];latencies=[];new_wrong_events=[];removed_wrong_events=[]
    for row in rows:
        truth=row['item']['label'];before=row['results']['reference'];after=row['results']['anchored']
        if before['pred']!=after['pred'] or before['events']!=after['events']:
            changed.append(dict(video_id=row['item']['video_id'],word=truth,source=row['item']['source'],
                before=before['pred'],after=after['pred'],before_events=before['events'],after_events=after['events']))
        a_wrong=Counter(e['label'] for e in before['events'] if e['label']!=truth)
        b_wrong=Counter(e['label'] for e in after['events'] if e['label']!=truth)
        for label,n in (b_wrong-a_wrong).items():
            new_wrong_events.append(dict(video_id=row['item']['video_id'],word=truth,emitted=label,count=n))
        for label,n in (a_wrong-b_wrong).items():
            removed_wrong_events.append(dict(video_id=row['item']['video_id'],word=truth,emitted=label,count=n))
        if before['pred']==truth and after['pred']==truth:
            t=[[e['time'] for e in r['events'] if e['label']==truth][0] for r in (before,after)]
            latencies.append(t[1]-t[0])
    verified=dict(verified_complete=True,clips=len(rows),null_controls_passed=len(rows),
        contract_sha256=digest(contract),changed_clips=changed,new_wrong_events=new_wrong_events,
        removed_wrong_events=removed_wrong_events,
        common_correct_first_event_time_delta=dict(clips=len(latencies),
            median=float(np.median(latencies)),p95=float(np.quantile(latencies,.95)),
            scope='paired from source clip start, not annotated gesture onset or device latency'),
        words_with_correct_gain=sum(t['correct_after']>t['correct_before'] for t in table),
        words_with_correct_loss=sum(t['correct_after']<t['correct_before'] for t in table),
        words_without_calibration=[t['word'] for t in table if not t['clips']],
        deployment_eligible=False)
    verified['exact_mcnemar_p']=exact_discordance_p(len(report['gained_videos']),len(report['lost_videos']))
    ci=report['paired']['macro_recall_delta_ci95']
    verified['bootstrap_interval_degenerate']=bool(ci is not None and np.isclose(ci[0],ci[1],atol=1e-12)
        and (report['gained_videos'] or report['lost_videos']))
    write_json(a.root/'verified-reading.json',verified)
    b=report['reference'];c=report['anchored']
    lines=['# Thử giữ điểm bắt đầu cửa sổ — kết quả 22/10/2026','',
        '**Đã chạy đủ 297 clip phát triển thuộc 157/181 từ; mọi đối chứng null khớp. Model, score/margin/dwell và nhịp dự đoán giữ nguyên.**','',
        'Can thiệp: thêm tối đa một cửa sổ nối tiếp từ điểm bắt đầu active interval vừa đủ điều kiện, luôn dùng khung mới nhất; hết hạn sau 0,60 giây hoặc khi buffer reset. Không nhớ nhãn, không lấy lại điểm cũ.','',
        '| Chỉ số | Reference | Cửa sổ nối tiếp |','|---|---:|---:|',
        f"| Clip đúng | {b['correct']} | {c['correct']} |",f"| Clip sai cuối cùng | {b['wrong']} | {c['wrong']} |",
        f"| Không chốt | {b['none']} | {c['none']} |",
        f"| Precision trên clip đã chốt | {100*b['accepted_precision']:.2f}% | {100*c['accepted_precision']:.2f}% |",
        f"| Macro recall | {100*b['macro_recall']:.2f}% | {100*c['macro_recall']:.2f}% |",
        f"| Sự kiện sai (kể cả clip cuối đúng) | {b['wrong_events']} | {c['wrong_events']} |",
        f"| Sự kiện trùng nhãn liên tiếp | {b['consecutive_duplicate_events']} | {c['consecutive_duplicate_events']} |",'',
        f"Thêm đúng {len(report['gained_videos'])} clip, mất đúng {len(report['lost_videos'])} clip; {verified['words_with_correct_gain']} từ tăng và {verified['words_with_correct_loss']} từ giảm số đúng. Danh sách cụ thể giữ trong comparison.json và verified-reading.json, không chỉ xem một từ hứa hẹn.",'',
        f"Cận mô tả 95% của delta macro recall: {ci}. Bootstrap tuyến tính hóa giữ trọng số lớp có khoảng suy biến: **{verified['bootstrap_interval_degenerate']}**. Khi khác biệt chỉ ở một lớp có một clip, residual lớp đó bằng 0 nên khoảng này không thể hiện bất định của lớp; không dùng để tuyên bố thua có ý nghĩa thống kê. Kiểm định McNemar exact hai phía cho clip được/mất: p={verified['exact_mcnemar_p']:.4f}. Cụm gần như từng video, không phải kiểm chứng người ký mới; tập phát triển đã được xem nhiều lần.",'',
        f"{report['added_windows']} cửa sổ bổ sung được dựng trong lượt này; chưa đo chi phí trên điện thoại thật.",'',
        '## Các điều kiện đã chốt','']
    for key,value in report['checks'].items():lines.append(f'- `{key}`: **{value}**.')
    lines+=['',f"Qua toàn bộ sàng lọc phát triển: **{report['development_screen_passed']}**. Không đạt không chứng minh mọi biến thể cửa sổ đều vô ích; không được đổi tham số sau khi xem rồi gọi đó là kiểm thử độc lập.",'',
        '## Bản ghi webcam đã xem','']
    probe=report.get('webcam_probe')
    if probe:
        lines +=[f"Nhánh null khớp {probe['null_control']['batches']}/231 batch. Reference có {len(probe['reference_events'])} sự kiện; candidate có {len(probe['candidate_events'])}: `{json.dumps(probe['candidate_events'],ensure_ascii=False)}`.",'',
            'Bản ghi này theo thứ tự chào → nghe → nhìn → rau, ranh giới đối chiếu video là xấp xỉ. Nhận thêm một từ không chứng minh đã sửa những từ còn lại hoặc cải thiện webcam độc lập. Không dùng video này để chỉnh TTL/ngưỡng cho đẹp kết quả.','']
    lines+=['## Quyết định','',
        ('Phương pháp chỉ qua sàng lọc phát triển; chưa đủ điều kiện bật trong app/public do chưa có nền thật và tập webcam độc lập.' if report['development_screen_passed'] else
         'Không bật nhánh thử trong app hoặc public vì chưa qua các điều kiện đã chốt. Giữ reference hiện tại làm đối chứng; không gọi chất lượng webcam hiện tại là đạt.'),'',
        'Không thay kiến trúc hay train lại trong lượt này. Không tuyên bố đã tối ưu FPS hoặc độ trễ điện thoại: mọi lượt ở đây là replay feature offline. Không đo false accept/phút khi thiếu nền thật. 24 từ không có calibration vẫn chưa được kiểm chứng.','',
        '## Tệp tái hiện','',
        f'- Bảng đầy đủ 181 từ: `{a.root/"all-181-words-comparison.csv"}`.',
        f'- Hợp đồng, journal từng clip, bảng clip được/mất và đối chứng: `{a.root}`.',
        '- Giao thức: `docs/ANCHORED_WINDOW_PROTOCOL_20261022.md`.',
        '- Mã thử offline: `ai_service/experiment_anchored_windows.py`; kiểm lại: `ai_service/review_anchored_windows.py`.','']
    a.report.parent.mkdir(parents=True,exist_ok=True);a.report.write_text('\n'.join(lines),encoding='utf-8')
    print(json.dumps(dict(verified_complete=True,clips=len(rows),gained=len(report['gained_videos']),
        lost=len(report['lost_videos']),new_wrong_events=new_wrong_events,
        development_screen_passed=report['development_screen_passed'],output=str(a.report.resolve())),ensure_ascii=True,indent=2))


if __name__=='__main__':main()
