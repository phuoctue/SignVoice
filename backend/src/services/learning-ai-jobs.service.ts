import {randomUUID} from 'crypto';
import {Types} from 'mongoose';
import {AppError} from '../common/errors/AppError';
import {analyzeLearningProgress} from './learning-analysis.service';
import {learningAdvice} from './learning-coach.service';

export type LearningAiKind = 'analysis' | 'coach';
type Job = {id:string; owner:string; kind:LearningAiKind; requestKey:string;
  state:'pending'|'completed'|'failed'; createdAt:number; result?:unknown};
const jobs=new Map<string,Job>();
const ttl=5*60*1000;
function prune() {
  const oldest=Date.now()-ttl;
  for(const [id,job] of jobs)if(job.createdAt<oldest)jobs.delete(id);
}
function view(job:Job) {
  return {id:job.id,kind:job.kind,state:job.state,
    ...(job.state==='completed'?{result:job.result}:{}),
    ...(job.state==='failed'?{message:'Chưa hoàn tất phân tích AI. Vui lòng thử lại.'}:{})};
}

/** Bound to authenticated owner. Short HTTP requests never wait for model generation. */
export function startLearningAiJob(owner:Types.ObjectId,kind:LearningAiKind,requestKey:string) {
  prune();
  const ownerId=String(owner);
  const existing=[...jobs.values()].find(job=>job.owner===ownerId && job.requestKey===requestKey && job.kind===kind);
  if(existing)return view(existing);
  const active=[...jobs.values()].filter(job=>job.state==='pending');
  if(active.length>=8 || active.filter(job=>job.owner===ownerId).length>=2) {
    throw new AppError('AI đang xử lý yêu cầu trước. Vui lòng chờ một chút rồi thử lại.',429,'LEARNING_AI_BUSY');
  }
  if(jobs.size>=256) {
    const finished=[...jobs.values()].find(job=>job.state!=='pending');
    if(finished)jobs.delete(finished.id);
  }
  const job:Job={id:randomUUID(),owner:ownerId,kind,requestKey,state:'pending',createdAt:Date.now()};
  jobs.set(job.id,job);
  // The worker has its own bounded LM timeout. A disconnected handset can poll again.
  void Promise.resolve().then<unknown>(()=>kind==='analysis'?analyzeLearningProgress(owner):learningAdvice(owner))
    .then(result=>{if(jobs.get(job.id)===job){job.result=result;job.state='completed';}})
    .catch(()=>{if(jobs.get(job.id)===job)job.state='failed';});
  return view(job);
}
export function getLearningAiJob(owner:Types.ObjectId,id:string) {
  prune();
  const job=jobs.get(id);
  if(!job || job.owner!==String(owner)) {
    throw new AppError('Phiên phân tích đã hết hạn. Vui lòng bắt đầu lại.',404,'LEARNING_AI_JOB_NOT_FOUND');
  }
  return view(job);
}
