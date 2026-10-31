"""Read back a completed checkpoint portability comparison, without audit I/O."""
import argparse
import csv
import json
from pathlib import Path
import numpy as np
from .compare_colab_checkpoints import BRANCHES
from .evaluate_fixed_components import digest,file_hash,metrics,write_json
from .review_anchored_windows import exact_discordance_p

LABELS={'app':'App hiện tại: TCN + embedding cũ','app_tcn':'TCN cũ, điểm chung 0,60',
    'reference42_tcn':'Reference42 mới, TCN 0,60','reference137_tcn':'Reference137 mới, TCN 0,60',
    'latest137_tcn':'AD mới nhất, TCN 0,60','latest137_export_score':'AD, score export 0,80 trong app',
    'latest137_pair_fixed':'Cặp AD + embedding mới, phối hợp cố định'}


def verify(root,original,assets):
    contract=json.loads((root/'contract.json').read_text(encoding='utf-8'))
    report=json.loads((root/'comparison.json').read_text(encoding='utf-8'))
    if contract['smoke'] or not report['complete']:raise ValueError('Not a completed full run')
    if file_hash(Path(__file__).with_name('compare_colab_checkpoints.py'))!=contract['code_sha256']:raise ValueError('Comparison code changed')
    for name,sha in contract['dependencies'].items():
        if file_hash(Path(__file__).with_name(name))!=sha:raise ValueError('Dependency changed')
    inventory=json.loads((assets/'inventory.json').read_text(encoding='utf-8'))
    if file_hash(assets/'inventory.json')!=contract['assets_inventory_sha256'] or inventory!=contract['inventory']:
        raise ValueError('Asset inventory changed')
    for spec in inventory['models']:
        if file_hash(assets/spec['model'])!=spec['model_sha256'] or file_hash(assets/spec['config'])!=spec['config_sha256']:
            raise ValueError('Checkpoint changed')
    for name,sha in inventory['shared_expected'].items():
        if file_hash(assets/name)!=sha:raise ValueError('Shared asset changed')
    old=json.loads((original/'contract.json').read_text(encoding='utf-8'))
    if digest(old)!=contract['old_contract_sha256']:raise ValueError('Original contract changed')
    saved={r['item']['video_id']:r for line in (original/'results.jsonl').read_text(encoding='utf-8').splitlines() if (r:=json.loads(line))}
    expected={r['video_id']:r for r in contract['cohort']}
    training=json.loads((assets/'training_identity.json').read_text(encoding='utf-8'))
    if len(expected)!=204 or set(expected)&set(training['audit_ids']) or set(expected)&set(training['train_ids']):
        raise ValueError('Invalid permitted cohort')
    excluded={r['video_id'] for r in contract['excluded']}
    if len(excluded)!=93 or not excluded<=set(training['audit_ids']):raise ValueError('Audit exclusion changed')
    rows=[json.loads(line) for line in (root/'results.jsonl').read_text(encoding='utf-8').splitlines()]
    ids=[r['item']['video_id'] for r in rows]
    if len(ids)!=204 or len(set(ids))!=204 or set(ids)!=set(expected):raise ValueError('Missing/duplicate journal')
    words=json.loads((assets/'latest137_word_temporal_config.json').read_text(encoding='utf-8'))['labels']
    for row in rows:
        key=row['item']['video_id'];s=saved[key]
        if row['item']!=expected[key] or row['contract_sha256']!=digest(contract):raise ValueError('Row contract changed')
        if row['features']!=s['features'] or not row['results']['null_control_passed']:raise ValueError('Input/control changed')
        if row['results']['app']!={k:s['results']['reference'][k] for k in ('pred','events')}:
            raise ValueError('Reference differs from frozen app')
        feature=original/'features'/(key+'.npz')
        if file_hash(feature)!=row['features']['feature_sha256'] or file_hash(original/'sources'/(key+'.mp4'))!=row['features']['source_sha256']:
            raise ValueError('Source/feature changed')
        with np.load(feature,allow_pickle=False) as z:n=len(z['times']);end=float(z['times'][-1])
        if n!=row['results']['frames_controlled']:raise ValueError('Partial null control')
        for name in BRANCHES:
            r=row['results'][name];events=r['events']
            if r['pred']!=(events[-1]['label'] if events else None):raise ValueError('Final prediction inconsistent')
            if any(e['label'] not in words or not 0<=e['time']<=end+.002 for e in events):raise ValueError('Invalid event')
            if any(a['time']>b['time'] for a,b in zip(events,events[1:])):raise ValueError('Event order inconsistent')
    for role,field,n in [('checkpoint_calibration_development','calibration',95),('checkpoint_epoch_development','epoch_development',109)]:
        subset=[r for r in rows if r['item']['role']==role]
        if len(subset)!=n:raise ValueError('Split role size changed')
        for name in BRANCHES:
            if metrics(subset,name)!=report[field]['metrics'][name]:raise ValueError('Metrics do not recompute')
    for name in ('app','app_repeat'):
        if not report['webcam']['branches'][name]['control']['passed'] or report['webcam']['branches'][name]['control']['batches']!=231:
            raise ValueError('Webcam reference failed')
    if report['audit_arrays_loaded'] or report['deployment_eligible']:raise ValueError('Unjustified audit/promotion claim')
    return contract,report,rows,words


def contrast(rows,before,after):
    gained=[];lost=[];changed=[];time_delta=[]
    for r in rows:
        truth=r['item']['label'];a=r['results'][before];b=r['results'][after]
        info=dict(video_id=r['item']['video_id'],word=truth,source=r['item']['source'],before=a['pred'],after=b['pred'])
        if a['pred']!=truth and b['pred']==truth:gained.append(info)
        if a['pred']==truth and b['pred']!=truth:lost.append(info)
        if a['events']!=b['events']:changed.append(info)
        if a['pred']==truth and b['pred']==truth:
            t=[[e['time'] for e in result['events'] if e['label']==truth][0] for result in (a,b)]
            time_delta.append(t[1]-t[0])
    return dict(gained=gained,lost=lost,event_changed=changed,
        exact_mcnemar_p=exact_discordance_p(len(gained),len(lost)),
        common_correct_first_event_delta=dict(videos=len(time_delta),median=float(np.median(time_delta)) if time_delta else None,
            scope='paired source clip start, not gesture onset or device latency'))


def reading(rows,report):
    cal=[r for r in rows if r['item']['role']=='checkpoint_calibration_development'];result={}
    before=report['calibration']['metrics']['app'];critical=['chào','nghe','nhìn','rau','bàn tay','cứu']
    for name in BRANCHES[1:]:
        after=report['calibration']['metrics'][name]
        tests=dict(correct_increased=after['correct']>before['correct'],
            precision_sufficient=after['accepted_precision'] is not None and before['accepted_precision'] is not None
                and after['accepted_precision']>=max(.95,before['accepted_precision']),
            wrong_not_increased=after['wrong']<=before['wrong'],wrong_events_not_increased=after['wrong_events']<=before['wrong_events'],
            duplicates_not_increased=after['consecutive_duplicate_events']<=before['consecutive_duplicate_events'],
            represented_critical_not_lost=all(metrics([r for r in cal if r['item']['label']==w],name)['correct']>=
                metrics([r for r in cal if r['item']['label']==w],'app')['correct'] for w in critical))
        ci=report['calibration']['paired'][name]['macro_recall_delta_ci95']
        result[name]=dict(app_comparison=contrast(cal,'app',name),checks=tests,
            development_screen_passed=all(tests.values()),deployment_eligible=False,
            macro_bootstrap_ci_degenerate=bool(ci is not None and np.isclose(ci[0],ci[1],atol=1e-12)))
        if name in ('reference42_tcn','reference137_tcn','latest137_tcn'):
            result[name]['weights_only_vs_old_tcn']=contrast(cal,'app_tcn',name)
    return result


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('root',type=Path);p.add_argument('--original',type=Path,required=True)
    p.add_argument('--assets',type=Path,required=True);p.add_argument('--report',type=Path,required=True)
    a=p.parse_args();contract,report,rows,words=verify(a.root,a.original,a.assets)
    comparisons=reading(rows,report)
    write_json(a.root/'verified-reading.json',dict(verified_complete=True,null_controls=204,
        primary_videos=95,secondary_videos=109,audit_excluded=93,comparisons=comparisons,deployment_eligible=False))
    table=[]
    for word in words:
        cal=[r for r in rows if r['item']['role']=='checkpoint_calibration_development' and r['item']['label']==word]
        epoch=[r for r in rows if r['item']['role']=='checkpoint_epoch_development' and r['item']['label']==word]
        value=dict(word=word,calibration_videos=len(cal),epoch_videos=len(epoch),
            primary_status='development_only' if cal else 'no_shared_calibration_sample')
        for name in BRANCHES:
            for role,subset in [('cal',cal),('epoch',epoch)]:
                m=metrics(subset,name)
                for key in ('correct','wrong','none','wrong_events'):value[name+'_'+role+'_'+key]=m[key]
        table.append(value)
    with (a.root/'all-181-words-comparison.csv').open('w',encoding='utf-8-sig',newline='') as f:
        writer=csv.DictWriter(f,fieldnames=list(table[0]));writer.writeheader();writer.writerows(table)
    lines=['# So checkpoint Colab mới với app — 22/10/2026','',
        '**Đã đối chiếu byte model/config trên Drive và chạy đủ 204 video được phép; không chạy model mới trên 93 video audit. App/public chưa thay đổi.**','',
        ('Không nhánh thay thế nào qua sàng lọc phát triển đã chốt; chưa có cơ sở chọn checkpoint mới để thay app ở các điểm vận hành này.' if not any(x['development_screen_passed'] for x in comparisons.values()) else
         'Có điểm vận hành qua sàng lọc phát triển, nhưng chưa đủ bằng chứng webcam/người mới/nền thật để triển khai.'),'',
        'Bản mới nhất là AD seed137 (21/10), đối chiếu thêm reference137 và reference42. Mọi model/config/encoder/prototype/normalizer khớp checksum. TRAIN không trùng theo ID hoặc content hash với tập đánh giá; các hàm feature AST khớp. Giữ runtime app, cadence 0,25s và gap 0,60s. Đây là kiểm tra checkpoint khi port vào app, không phải tái hiện số Colab dùng cadence 0,15s/gap 0,90s.','',
        '## Calibration chung — 95 clip, 87 từ','',
        '297 video cũ phân thành 95 calibration mới, 109 epoch VAL và 93 audit mới. Không so kết quả 95/204 với số 171/297 trước đó. Cả bảy nhánh dùng cùng 95 clip cho bảng này.','',
        'Lưu ý lộ dữ liệu giữa hai giao thức: 93 video audit mới đã từng được chạy với app trong các lượt 297 clip trước khi đối chiếu vai trò Colab. Vì vậy không thể coi phần này hoàn toàn chưa được xem đối với toàn bộ quá trình phát triển. Lượt hiện tại loại chúng trước I/O source/feature và không chạy checkpoint mới trên chúng. Kiểm chứng cuối vẫn cần dữ liệu webcam độc lập mới.','',
        '| Nhánh | Đúng | Sai | Không chốt | Precision trên clip đã chốt | Sự kiện sai |',
        '|---|---:|---:|---:|---:|---:|']
    for name in BRANCHES:
        m=report['calibration']['metrics'][name];precision='—' if m['accepted_precision'] is None else f"{100*m['accepted_precision']:.2f}%"
        lines.append(f"| {LABELS[name]} | {m['correct']} | {m['wrong']} | {m['none']} | {precision} | {m['wrong_events']} |")
    lines+=['','Precision không tính clip không chốt, không phải accuracy webcam. Các điểm TCN 0,60 dùng cùng cổng/feature/luồng để kiểm trọng số. Cặp mới 50/50, temperature 1/0,06 là điểm phối hợp cố định chưa calibration lại; không diễn giải nó thành chất lượng tối ưu của encoder mới.','',
        f"App chốt đúng {report['calibration']['metrics']['app']['correct']}/95 clip, bỏ qua {report['calibration']['metrics']['app']['none']} clip và vẫn có {report['calibration']['metrics']['app']['wrong_events']} sự kiện sai giữa clip. Precision 100% ở kết quả cuối không có nghĩa nhận đúng 95/95 hoặc không từng phát sai.",'',
        '## So sánh cặp calibration','']
    for name,data in comparisons.items():
        c=data['app_comparison'];lines.append(f"- {name}: thêm đúng {len(c['gained'])}, mất đúng {len(c['lost'])}; McNemar exact p={c['exact_mcnemar_p']:.4f}; qua sàng lọc phát triển={data['development_screen_passed']}.")
    lines+=['','CI tuyến tính hóa giữ trọng số lớp có thể suy biến khi mỗi từ chỉ có một clip; cờ trong verified-reading.json. P-value trên nhiều nhánh chưa hiệu chỉnh đa kiểm định, chỉ để mô tả, không dùng một p-value để chọn model. Không dùng khoảng rất hẹp để khẳng định khả năng với người mới. Tập calibration đã được sử dụng nhiều lần nên mọi số vẫn là phát triển. Danh sách clip được/mất và đối chiếu riêng trọng số TCN giữ trong verified-reading.json.','',
        '## Epoch VAL — 109 clip, báo riêng','',
        '| Nhánh | Đúng | Sai | Không chốt | Sự kiện sai |','|---|---:|---:|---:|---:|']
    for name in BRANCHES:
        m=report['epoch_development']['metrics'][name]
        lines.append(f"| {LABELS[name]} | {m['correct']} | {m['wrong']} | {m['none']} | {m['wrong_events']} |")
    lines+=['','Epoch đã tham gia chọn checkpoint nên không gộp với calibration hoặc coi là kiểm thử độc lập.','',
        '## Bản ghi webcam đã xem','',
        'Reference khớp 231/231 batch gốc; reference lặp lại cũng khớp. Bản ghi người dùng làm chào → nghe → nhìn → rau. Ranh giới video chỉ xấp xỉ. Các sự kiện dưới đây không phải accuracy độc lập:','']
    for name in BRANCHES:lines.append(f"- {name}: `{json.dumps(report['webcam']['branches'][name]['events'],ensure_ascii=False)}`.")
    lines+=['','## Kết luận và phạm vi','',
        'Không tự thay model hoặc ngưỡng trong app. Qua sàng lọc trên 95 clip không chứng minh webcam/người mới/nền thật đã tốt; chưa có false accept/phút. Không đạt chỉ nói chưa có bằng chứng chọn checkpoint đó ở các điểm vận hành đã thử, không chứng minh mọi cách calibration hay kiến trúc mới đều vô ích.','',
        f"Bảng đủ 181 từ có {sum(not r['calibration_videos'] for r in table)} từ thiếu mẫu calibration chung; không suy diễn đúng/sai cho các từ đó. 93 audit chỉ được dùng ID để loại, không mở source/feature hoặc suy luận model mới.",'',
        '- Bảng từng từ: `'+str(a.root/'all-181-words-comparison.csv')+'`.',
        '- Contract, journal, kiểm lại và clip được/mất: `'+str(a.root)+'`.',
        '- Giao thức: `docs/CHECKPOINT_COMPARISON_PROTOCOL_20261022.md`.',
        '- Nguồn checkpoint mới nhất: '+contract['inventory']['latest_drive_model_url']+'.',
        '- Nguồn model reference và encoder/prototypes: '+contract['inventory']['drive_reference_folder']+'.','']
    a.report.parent.mkdir(parents=True,exist_ok=True);a.report.write_text('\n'.join(lines),encoding='utf-8')
    print(json.dumps(dict(verified_complete=True,primary95={name:{k:m[k] for k in ['correct','wrong','none','wrong_events','accepted_precision']} for name,m in report['calibration']['metrics'].items()},development_screen={k:v['development_screen_passed'] for k,v in comparisons.items()},output=str(a.report.resolve())),ensure_ascii=True,indent=2))


if __name__=='__main__':main()
